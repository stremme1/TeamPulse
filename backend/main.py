"""
Workout System Backend — FastAPI Server
Streams real-time workout data via WebSocket, persists to SQLite.
"""

import asyncio
import json
import logging
import uuid
from datetime import datetime
from typing import Optional

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException, BackgroundTasks, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from config import HOST, PORT, WS_HEARTBEAT_INTERVAL, get_hr_zone
from models import (
    init_db,
    create_session,
    get_session,
    end_session,
    store_heart_rate,
    store_calories,
    store_distance,
    queue_message,
    upsert_recovery_metrics,
    get_recovery_metrics,
    get_sessions,
    get_session_data,
    upsert_athlete,
    get_athlete,
)
from websocket_manager import manager

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s — %(message)s",
)
logger = logging.getLogger("backend")


# ─── FastAPI Setup ────────────────────────────────────────────────────────────

app = FastAPI(
    title="Workout System API",
    version="1.0.0",
    description="Real-time workout streaming backend",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, restrict to specific origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
async def startup():
    init_db()
    logger.info("Database initialized")
    logger.info(f"Server starting on {HOST}:{PORT}")


# ─── Pydantic Models ──────────────────────────────────────────────────────────


class SessionStartRequest(BaseModel):
    athlete_id: str
    workout_type: str = "running"


class HeartRateDataPoint(BaseModel):
    athlete_id: str
    session_id: str
    timestamp: Optional[str] = None
    heart_rate: int = Field(ge=30, le=250)
    calories: float = Field(default=0, ge=0)
    distance: float = Field(default=0, ge=0)
    device_status: str = "watch"


class WorkoutEndRequest(BaseModel):
    athlete_id: str
    session_id: str
    duration_seconds: int


class RecoveryMetricsRequest(BaseModel):
    athlete_id: str
    date: str  # ISO date YYYY-MM-DD
    session_id: Optional[str] = None
    sleep_hours: Optional[float] = None
    sleep_deep_hours: Optional[float] = None
    sleep_rem_hours: Optional[float] = None
    sleep_awake_minutes: Optional[int] = None
    spo2_avg: Optional[float] = None
    spo2_min: Optional[float] = None
    resting_hr: Optional[int] = None
    hrv_avg: Optional[int] = None
    vo2_max: Optional[float] = None
    recovery_score: Optional[float] = None
    fatigue_score: Optional[float] = None
    readiness_score: Optional[float] = None


# ─── REST API Routes ──────────────────────────────────────────────────────────


@app.get("/api/health")
async def health_check():
    """Health check endpoint."""
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "connections": manager.active_connections,
        "sessions": manager.active_sessions,
    }


# ─── Session Management ────────────────────────────────────────────────────────


@app.post("/api/sessions/start")
async def start_session(req: SessionStartRequest):
    """Start a new workout session."""
    session_id = str(uuid.uuid4())
    upsert_athlete(req.athlete_id)
    session = create_session(session_id, req.athlete_id, req.workout_type)
    logger.info(f"Session started: {session_id} athlete={req.athlete_id} type={req.workout_type}")
    return {"session_id": session_id, "session": session}


@app.post("/api/sessions/{session_id}/end")
async def end_workout(session_id: str, req: WorkoutEndRequest):
    """End a workout session."""
    session = get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    ended = end_session(
        session_id,
        req.duration_seconds,
        session.get("total_calories", 0),
        session.get("total_distance", 0),
    )

    # Notify via WebSocket
    await manager.broadcast_session(session_id, {
        "type": "workout_ended",
        "session_id": session_id,
        "athlete_id": req.athlete_id,
        "ended_at": ended["ended_at"],
        "duration_seconds": req.duration_seconds,
        "summary": ended,
    })

    logger.info(f"Session ended: {session_id} duration={req.duration_seconds}s")
    return {"session": ended}


@app.get("/api/sessions/{session_id}")
async def get_session_info(session_id: str):
    """Get session information."""
    session = get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    return session


@app.get("/api/sessions/{session_id}/data")
async def get_session_full_data(session_id: str):
    """Get full session data including all data points."""
    data = get_session_data(session_id)
    if not data:
        raise HTTPException(status_code=404, detail="Session not found")
    return data


# ─── Real-Time Data Ingestion ─────────────────────────────────────────────────


@app.post("/api/data/heart-rate")
async def ingest_heart_rate(data: HeartRateDataPoint, background_tasks: BackgroundTasks):
    """
    Primary endpoint for real-time heart rate data.
    Uses background task for storage to minimize latency.
    """
    timestamp = data.timestamp or datetime.utcnow().isoformat()
    zone = get_hr_zone(data.heart_rate)

    # Queue storage in background (non-blocking)
    background_tasks.add_task(
        store_heart_rate,
        data.session_id,
        timestamp,
        data.heart_rate,
        zone,
        data.device_status,
    )

    # Also update cumulative calories in background
    if data.calories > 0:
        background_tasks.add_task(
            store_calories,
            data.session_id,
            timestamp,
            data.calories,
            data.calories,  # cumulative
        )

    # Store distance if available
    if data.distance > 0:
        background_tasks.add_task(
            store_distance,
            data.session_id,
            timestamp,
            data.distance,
        )

    # Broadcast immediately to WebSocket subscribers
    broadcast_data = {
        "type": "heart_rate",
        "athlete_id": data.athlete_id,
        "session_id": data.session_id,
        "timestamp": timestamp,
        "heart_rate": data.heart_rate,
        "zone": zone,
        "calories": data.calories,
        "distance": data.distance,
        "device_status": data.device_status,
    }

    await manager.broadcast_heart_rate(data.session_id, data.athlete_id, broadcast_data)

    return {"received": True, "zone": zone}


@app.post("/api/data/batch")
async def ingest_batch(data_points: list[HeartRateDataPoint], background_tasks: BackgroundTasks):
    """
    Batch ingestion endpoint for offline replay.
    iPhone buffers data when offline, sends in batches on reconnect.
    """
    stored = 0
    for dp in data_points:
        timestamp = dp.timestamp or datetime.utcnow().isoformat()
        zone = get_hr_zone(dp.heart_rate)
        background_tasks.add_task(
            store_heart_rate, dp.session_id, timestamp, dp.heart_rate, zone, dp.device_status
        )
        if dp.calories > 0:
            background_tasks.add_task(
                store_calories, dp.session_id, timestamp, dp.calories, dp.calories
            )
        if dp.distance > 0:
            background_tasks.add_task(
                store_distance, dp.session_id, timestamp, dp.distance
            )
        stored += 1

    return {"stored": stored, "count": len(data_points)}


# ─── Recovery Metrics ──────────────────────────────────────────────────────────


@app.post("/api/recovery/sync")
async def sync_recovery_metrics(req: RecoveryMetricsRequest):
    """Sync post-workout recovery metrics from HealthKit."""
    metrics = upsert_recovery_metrics(
        req.athlete_id,
        req.date,
        req.model_dump(exclude_none=True),
    )
    logger.info(f"Recovery metrics synced: athlete={req.athlete_id} date={req.date}")
    return {"metrics": metrics}


@app.get("/api/recovery/{athlete_id}")
async def get_recovery(athlete_id: str, days: int = Query(default=7, ge=1, le=30)):
    """Get recovery metrics history for an athlete."""
    metrics = get_recovery_metrics(athlete_id, days)
    return {"athlete_id": athlete_id, "days": days, "metrics": metrics}


# ─── Athlete ──────────────────────────────────────────────────────────────────


@app.get("/api/athletes/{athlete_id}")
async def get_athlete_info(athlete_id: str):
    """Get athlete profile."""
    athlete = get_athlete(athlete_id)
    if not athlete:
        raise HTTPException(status_code=404, detail="Athlete not found")
    sessions = get_sessions(athlete_id, 10)
    return {"athlete": athlete, "recent_sessions": sessions}


# ─── WebSocket ────────────────────────────────────────────────────────────────


@app.websocket("/ws/{athlete_id}")
async def websocket_endpoint(websocket: WebSocket, athlete_id: str):
    """
    WebSocket endpoint for real-time dashboard streaming.
    Connect: wss://host/ws/{athlete_id}
    Send: {"type": "subscribe", "session_id": "..."}
    Receive: live workout data as JSON
    """
    await manager.connect(websocket, athlete_id)
    upsert_athlete(athlete_id)

    try:
        # Send connection acknowledgment
        await websocket.send_json({
            "type": "connected",
            "athlete_id": athlete_id,
            "timestamp": datetime.utcnow().isoformat(),
        })

        # Heartbeat task
        async def heartbeat():
            while True:
                try:
                    await asyncio.sleep(WS_HEARTBEAT_INTERVAL)
                    await websocket.send_json({"type": "heartbeat", "ts": datetime.utcnow().isoformat()})
                except Exception:
                    break

        heartbeat_task = asyncio.create_task(heartbeat())

        while True:
            raw = await websocket.receive_text()
            try:
                msg = json.loads(raw)
                msg_type = msg.get("type")

                if msg_type == "subscribe":
                    session_id = msg.get("session_id")
                    if session_id:
                        await manager.subscribe_session(athlete_id, session_id)
                        await websocket.send_json({
                            "type": "subscribed",
                            "session_id": session_id,
                        })
                        logger.info(f"WS {athlete_id} subscribed to {session_id}")

                elif msg_type == "unsubscribe":
                    session_id = msg.get("session_id")
                    if session_id:
                        await manager.unsubscribe_session(athlete_id, session_id)

                elif msg_type == "ping":
                    await websocket.send_json({"type": "pong", "ts": datetime.utcnow().isoformat()})

                else:
                    logger.warning(f"Unknown WS message type from {athlete_id}: {msg_type}")

            except json.JSONDecodeError:
                logger.warning(f"Invalid JSON from {athlete_id}: {raw[:100]}")
            except Exception as e:
                logger.error(f"WebSocket error for {athlete_id}: {e}")
                break

    except WebSocketDisconnect:
        logger.info(f"WebSocket disconnected: {athlete_id}")
    except Exception as e:
        logger.error(f"WebSocket error: {athlete_id} — {e}")
    finally:
        heartbeat_task.cancel()
        await manager.disconnect(websocket, athlete_id)


# ─── Dashboard Data ───────────────────────────────────────────────────────────


@app.get("/api/dashboard/{athlete_id}/live")
async def get_live_dashboard_data(athlete_id: str, session_id: str = Query(...)):
    """
    Get current session data for dashboard initialization.
    Returns the latest data point and session info.
    """
    session = get_session(session_id)
    if not session or session["athlete_id"] != athlete_id:
        raise HTTPException(status_code=404, detail="Session not found")

    from models import get_connection
    with get_connection() as conn:
        c = conn.cursor()

        # Latest heart rate
        c.execute(
            "SELECT * FROM heart_rate_data WHERE session_id = ? ORDER BY timestamp DESC LIMIT 1",
            (session_id,),
        )
        last_hr = dict(c.fetchone()) if c.fetchone() else None

        # Time in zones
        c.execute(
            "SELECT zone, COUNT(*) as count FROM heart_rate_data WHERE session_id = ? GROUP BY zone",
            (session_id,),
        )
        zone_counts = {row["zone"]: row["count"] for row in c.fetchall()}
        total = sum(zone_counts.values()) or 1

        # Recent HR trend (last 30 points)
        c.execute(
            "SELECT timestamp, hr, zone FROM heart_rate_data WHERE session_id = ? ORDER BY timestamp DESC LIMIT 30",
            (session_id,),
        )
        hr_trend = [dict(row) for row in c.fetchall()][::-1]

        # Latest calories
        c.execute(
            "SELECT * FROM calorie_data WHERE session_id = ? ORDER BY timestamp DESC LIMIT 1",
            (session_id,),
        )
        last_cal = dict(c.fetchone()) if c.fetchone() else None

    return {
        "session": session,
        "latest_heart_rate": last_hr,
        "time_in_zones": {
            zone: {"count": count, "percentage": round(count / total * 100, 1)}
            for zone, count in zone_counts.items()
        },
        "hr_trend": hr_trend,
        "latest_calories": last_cal,
    }


# ─── Entry Point ──────────────────────────────────────────────────────────────


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host=HOST,
        port=PORT,
        reload=False,
        log_level="info",
    )
