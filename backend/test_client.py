#!/usr/bin/env python3
"""Simple WebSocket test client for the workout backend."""

import asyncio
import json
import random
import time
import uuid

try:
    import websockets
except ImportError:
    print("Install websockets: pip install websockets")
    websockets = None


ATHLETE_ID = "test-athlete-001"
WORKOUT_TYPE = "running"
BACKEND_URL = "http://localhost:8000"


async def simulate_workout(ws_url: str):
    """Simulate a workout session with heart rate data."""
    session_id = str(uuid.uuid4())
    print(f"Starting simulated workout: {session_id}")

    async with websockets.connect(ws_url) as ws:
        # Receive connection ack
        msg = await ws.recv()
        print(f"Connected: {msg}")

        # Subscribe to session
        await ws.send(json.dumps({"type": "subscribe", "session_id": session_id}))
        resp = await ws.recv()
        print(f"Subscribe response: {resp}")

        # Simulate 30 seconds of workout data at ~1 Hz
        start = time.time()
        cumulative_cal = 0

        for i in range(30):
            elapsed = time.time() - start
            # Simulate a realistic HR curve
            base_hr = 140 + int(20 * (i / 30))
            hr = base_hr + random.randint(-5, 5)
            hr = max(90, min(190, hr))

            cumulative_cal += random.uniform(8, 15)
            distance = (i + 1) * 12  # ~12m per second running

            data = {
                "type": "heart_rate",
                "athlete_id": ATHLETE_ID,
                "session_id": session_id,
                "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "heart_rate": hr,
                "calories": round(cumulative_cal, 1),
                "distance": round(distance, 1),
                "device_status": "watch",
            }

            await ws.send(json.dumps(data))
            print(f"  [{i+1:02d}s] HR: {hr} bpm | Cal: {cumulative_cal:.0f} | Dist: {distance:.0f}m")

            # Receive broadcast (echoed back)
            try:
                resp = await asyncio.wait_for(ws.recv(), timeout=2)
                resp_data = json.loads(resp)
                if resp_data.get("type") == "heart_rate":
                    print(f"  → Dashboard received HR: {resp_data['heart_rate']} (zone: {resp_data['zone']})")
            except asyncio.TimeoutError:
                pass

            await asyncio.sleep(1)

        print(f"\nWorkout simulation complete. Session: {session_id}")


async def main():
    ws_url = "ws://localhost:8000/ws/test-dashboard-001"
    print(f"Connecting to {ws_url}")
    await simulate_workout(ws_url)


if __name__ == "__main__" and websockets:
    asyncio.run(main())
else:
    print("WebSocket library not available. Run: pip install websockets")
