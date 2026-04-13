"""Database models and initialization."""

import sqlite3
import json
from datetime import datetime
from typing import Optional, List
from contextlib import contextmanager

from config import DB_PATH


def init_db():
    """Initialize the SQLite database with required tables."""
    with get_connection() as conn:
        c = conn.cursor()

        # Sessions table
        c.execute("""
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                athlete_id TEXT NOT NULL,
                workout_type TEXT NOT NULL,
                started_at TEXT NOT NULL,
                ended_at TEXT,
                duration_seconds INTEGER,
                total_calories REAL DEFAULT 0,
                total_distance REAL DEFAULT 0,
                avg_hr INTEGER,
                max_hr INTEGER,
                min_hr INTEGER,
                status TEXT DEFAULT 'active'
            )
        """)

        # Heart rate data points
        c.execute("""
            CREATE TABLE IF NOT EXISTS heart_rate_data (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                hr INTEGER NOT NULL,
                zone TEXT NOT NULL,
                device_status TEXT DEFAULT 'watch',
                FOREIGN KEY (session_id) REFERENCES sessions(id)
            )
        """)

        # Calories data points
        c.execute("""
            CREATE TABLE IF NOT EXISTS calorie_data (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                calories REAL NOT NULL,
                cumulative_calories REAL DEFAULT 0,
                FOREIGN KEY (session_id) REFERENCES sessions(id)
            )
        """)

        # Distance data points
        c.execute("""
            CREATE TABLE IF NOT EXISTS distance_data (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                distance REAL NOT NULL,
                FOREIGN KEY (session_id) REFERENCES sessions(id)
            )
        """)

        # Offline message queue (for eventual consistency)
        c.execute("""
            CREATE TABLE IF NOT EXISTS message_queue (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                athlete_id TEXT NOT NULL,
                payload TEXT NOT NULL,
                received_at TEXT NOT NULL,
                synced INTEGER DEFAULT 0
            )
        """)

        # Recovery metrics (post-workout sync from HealthKit)
        c.execute("""
            CREATE TABLE IF NOT EXISTS recovery_metrics (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                athlete_id TEXT NOT NULL,
                session_id TEXT,
                date TEXT NOT NULL,
                sleep_hours REAL,
                sleep_deep_hours REAL,
                sleep_rem_hours REAL,
                sleep_awake_minutes INTEGER,
                spo2_avg REAL,
                spo2_min REAL,
                resting_hr INTEGER,
                hrv_avg INTEGER,
                vo2_max REAL,
                recovery_score REAL,
                fatigue_score REAL,
                readiness_score REAL,
                synced_at TEXT NOT NULL,
                UNIQUE(athlete_id, date)
            )
        """)

        # Athletes (lightweight - just for tracking)
        c.execute("""
            CREATE TABLE IF NOT EXISTS athletes (
                id TEXT PRIMARY KEY,
                created_at TEXT NOT NULL,
                last_seen TEXT
            )
        """)

        # Indexes for performance
        c.execute("CREATE INDEX IF NOT EXISTS idx_hr_session ON heart_rate_data(session_id)")
        c.execute("CREATE INDEX IF NOT EXISTS idx_hr_timestamp ON heart_rate_data(timestamp)")
        c.execute("CREATE INDEX IF NOT EXISTS idx_calories_session ON calorie_data(session_id)")
        c.execute("CREATE INDEX IF NOT EXISTS idx_distance_session ON distance_data(session_id)")
        c.execute("CREATE INDEX IF NOT EXISTS idx_recovery_athlete ON recovery_metrics(athlete_id)")
        c.execute("CREATE INDEX IF NOT EXISTS idx_sessions_athlete ON sessions(athlete_id)")
        c.execute("CREATE INDEX IF NOT EXISTS idx_queue_synced ON message_queue(synced)")

        conn.commit()


@contextmanager
def get_connection():
    """Get a database connection with row factory."""
    conn = sqlite3.connect(DB_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
    finally:
        conn.close()


# ─── Session Operations ────────────────────────────────────────────────────────


def create_session(session_id: str, athlete_id: str, workout_type: str) -> dict:
    """Create a new workout session."""
    with get_connection() as conn:
        c = conn.cursor()
        now = datetime.utcnow().isoformat()
        c.execute(
            """INSERT INTO sessions (id, athlete_id, workout_type, started_at, status)
               VALUES (?, ?, ?, ?, 'active')""",
            (session_id, athlete_id, workout_type, now),
        )
        conn.commit()
        return get_session(session_id)


def get_session(session_id: str) -> Optional[dict]:
    """Get a session by ID."""
    with get_connection() as conn:
        c = conn.cursor()
        c.execute("SELECT * FROM sessions WHERE id = ?", (session_id,))
        row = c.fetchone()
        return dict(row) if row else None


def end_session(session_id: str, duration_seconds: int, total_calories: float, total_distance: float) -> Optional[dict]:
    """End a workout session."""
    with get_connection() as conn:
        c = conn.cursor()
        now = datetime.utcnow().isoformat()

        # Calculate HR stats
        c.execute(
            "SELECT MIN(hr), MAX(hr), AVG(hr) FROM heart_rate_data WHERE session_id = ?",
            (session_id,),
        )
        hr_row = c.fetchone()
        min_hr, max_hr, avg_hr = hr_row["MIN(hr)"], hr_row["MAX(hr)"], int(hr_row["AVG(hr)"])

        c.execute(
            """UPDATE sessions SET
               ended_at = ?, duration_seconds = ?, total_calories = ?,
               total_distance = ?, avg_hr = ?, max_hr = ?, min_hr = ?,
               status = 'completed'
               WHERE id = ?""",
            (now, duration_seconds, total_calories, total_distance, avg_hr, max_hr, min_hr, session_id),
        )
        conn.commit()
        return get_session(session_id)


# ─── Data Point Operations ────────────────────────────────────────────────────


def store_heart_rate(session_id: str, timestamp: str, hr: int, zone: str, device_status: str):
    """Store a heart rate data point."""
    with get_connection() as conn:
        c = conn.cursor()
        c.execute(
            "INSERT INTO heart_rate_data (session_id, timestamp, hr, zone, device_status) VALUES (?, ?, ?, ?, ?)",
            (session_id, timestamp, hr, zone, device_status),
        )
        conn.commit()


def store_calories(session_id: str, timestamp: str, calories: float, cumulative: float):
    """Store a calorie data point."""
    with get_connection() as conn:
        c = conn.cursor()
        c.execute(
            "INSERT INTO calorie_data (session_id, timestamp, calories, cumulative_calories) VALUES (?, ?, ?, ?)",
            (session_id, timestamp, calories, cumulative),
        )
        conn.commit()


def store_distance(session_id: str, timestamp: str, distance: float):
    """Store a distance data point."""
    with get_connection() as conn:
        c = conn.cursor()
        c.execute(
            "INSERT INTO distance_data (session_id, timestamp, distance) VALUES (?, ?, ?)",
            (session_id, timestamp, distance),
        )
        conn.commit()


# ─── Queue Operations ────────────────────────────────────────────────────────


def queue_message(session_id: str, athlete_id: str, payload: dict):
    """Queue a message for processing."""
    with get_connection() as conn:
        c = conn.cursor()
        c.execute(
            "INSERT INTO message_queue (session_id, athlete_id, payload, received_at) VALUES (?, ?, ?, ?)",
            (session_id, athlete_id, json.dumps(payload), datetime.utcnow().isoformat()),
        )
        conn.commit()


def get_pending_messages(limit: int = 100) -> List[dict]:
    """Get pending messages for processing."""
    with get_connection() as conn:
        c = conn.cursor()
        c.execute(
            "SELECT * FROM message_queue WHERE synced = 0 ORDER BY id LIMIT ?",
            (limit,),
        )
        return [dict(row) for row in c.fetchall()]


def mark_messages_synced(message_ids: List[int]):
    """Mark messages as synced."""
    if not message_ids:
        return
    placeholders = ",".join("?" * len(message_ids))
    with get_connection() as conn:
        c = conn.cursor()
        c.execute(f"UPDATE message_queue SET synced = 1 WHERE id IN ({placeholders})", message_ids)
        conn.commit()


# ─── Recovery Metrics Operations ─────────────────────────────────────────────


def upsert_recovery_metrics(athlete_id: str, date: str, metrics: dict) -> dict:
    """Insert or update recovery metrics for an athlete."""
    with get_connection() as conn:
        c = conn.cursor()
        c.execute(
            """INSERT INTO recovery_metrics (
                athlete_id, session_id, date, sleep_hours, sleep_deep_hours, sleep_rem_hours,
                sleep_awake_minutes, spo2_avg, spo2_min, resting_hr, hrv_avg, vo2_max,
                recovery_score, fatigue_score, readiness_score, synced_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(athlete_id, date) DO UPDATE SET
                sleep_hours = excluded.sleep_hours,
                sleep_deep_hours = excluded.sleep_deep_hours,
                sleep_rem_hours = excluded.sleep_rem_hours,
                sleep_awake_minutes = excluded.sleep_awake_minutes,
                spo2_avg = excluded.spo2_avg,
                spo2_min = excluded.spo2_min,
                resting_hr = excluded.resting_hr,
                hrv_avg = excluded.hrv_avg,
                vo2_max = excluded.vo2_max,
                recovery_score = excluded.recovery_score,
                fatigue_score = excluded.fatigue_score,
                readiness_score = excluded.readiness_score,
                synced_at = excluded.synced_at
            """,
            (
                athlete_id,
                metrics.get("session_id"),
                date,
                metrics.get("sleep_hours"),
                metrics.get("sleep_deep_hours"),
                metrics.get("sleep_rem_hours"),
                metrics.get("sleep_awake_minutes"),
                metrics.get("spo2_avg"),
                metrics.get("spo2_min"),
                metrics.get("resting_hr"),
                metrics.get("hrv_avg"),
                metrics.get("vo2_max"),
                metrics.get("recovery_score"),
                metrics.get("fatigue_score"),
                metrics.get("readiness_score"),
                datetime.utcnow().isoformat(),
            ),
        )
        conn.commit()

        c.execute(
            "SELECT * FROM recovery_metrics WHERE athlete_id = ? AND date = ?",
            (athlete_id, date),
        )
        return dict(c.fetchone())


def get_recovery_metrics(athlete_id: str, days: int = 7) -> List[dict]:
    """Get recovery metrics for the last N days."""
    with get_connection() as conn:
        c = conn.cursor()
        c.execute(
            """SELECT * FROM recovery_metrics
               WHERE athlete_id = ?
               ORDER BY date DESC
               LIMIT ?""",
            (athlete_id, days),
        )
        return [dict(row) for row in c.fetchall()]


# ─── Athlete Operations ───────────────────────────────────────────────────────


def upsert_athlete(athlete_id: str):
    """Create or update athlete last-seen timestamp."""
    with get_connection() as conn:
        c = conn.cursor()
        now = datetime.utcnow().isoformat()
        c.execute(
            """INSERT INTO athletes (id, created_at, last_seen)
               VALUES (?, ?, ?)
               ON CONFLICT(id) DO UPDATE SET last_seen = excluded.last_seen""",
            (athlete_id, now, now),
        )
        conn.commit()


def get_athlete(athlete_id: str) -> Optional[dict]:
    """Get athlete by ID."""
    with get_connection() as conn:
        c = conn.cursor()
        c.execute("SELECT * FROM athletes WHERE id = ?", (athlete_id,))
        row = c.fetchone()
        return dict(row) if row else None


# ─── Session History ──────────────────────────────────────────────────────────


def get_sessions(athlete_id: str, limit: int = 20) -> List[dict]:
    """Get recent sessions for an athlete."""
    with get_connection() as conn:
        c = conn.cursor()
        c.execute(
            """SELECT * FROM sessions
               WHERE athlete_id = ? AND status = 'completed'
               ORDER BY started_at DESC LIMIT ?""",
            (athlete_id, limit),
        )
        return [dict(row) for row in c.fetchall()]


def get_session_data(session_id: str) -> dict:
    """Get all data for a session."""
    with get_connection() as conn:
        c = conn.cursor()

        session = get_session(session_id)
        if not session:
            return {}

        c.execute(
            "SELECT timestamp, hr, zone FROM heart_rate_data WHERE session_id = ? ORDER BY timestamp",
            (session_id,),
        )
        hr_data = [dict(row) for row in c.fetchall()]

        c.execute(
            "SELECT timestamp, calories, cumulative_calories FROM calorie_data WHERE session_id = ? ORDER BY timestamp",
            (session_id,),
        )
        calorie_data = [dict(row) for row in c.fetchall()]

        c.execute(
            "SELECT timestamp, distance FROM distance_data WHERE session_id = ? ORDER BY timestamp",
            (session_id,),
        )
        distance_data = [dict(row) for row in c.fetchall()]

        # Calculate time in zones
        c.execute(
            "SELECT zone, COUNT(*) as count FROM heart_rate_data WHERE session_id = ? GROUP BY zone",
            (session_id,),
        )
        zone_counts = {row["zone"]: row["count"] for row in c.fetchall()}

        total_points = sum(zone_counts.values()) if zone_counts else 1
        time_in_zones = {
            zone: {"seconds": count, "percentage": round(count / total_points * 100, 1)}
            for zone, count in zone_counts.items()
        }

        return {
            **session,
            "hr_data": hr_data,
            "calorie_data": calorie_data,
            "distance_data": distance_data,
            "time_in_zones": time_in_zones,
        }
