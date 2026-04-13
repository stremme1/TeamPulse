"""Application configuration."""

import os
from pathlib import Path

BASE_DIR = Path(__file__).parent
DB_PATH = os.getenv("DB_PATH", str(BASE_DIR / "workout.db"))

# Backend server settings
HOST = os.getenv("HOST", "0.0.0.0")
PORT = int(os.getenv("PORT", "8000"))

# WebSocket settings
WS_HEARTBEAT_INTERVAL = 30  # seconds
WS_MESSAGE_QUEUE_SIZE = 100

# Session settings
SESSION_TIMEOUT_SECONDS = 3600 * 4  # 4 hours

# Heart rate zones (beats per minute)
HR_ZONES = {
    "zone_1": {"name": "Recovery", "min": 0, "max": 114},
    "zone_2": {"name": "Aerobic", "min": 114, "max": 133},
    "zone_3": {"name": "Tempo", "min": 133, "max": 152},
    "zone_4": {"name": "Threshold", "min": 152, "max": 171},
    "zone_5": {"name": "VO2 Max", "min": 171, "max": 999},
}


def get_hr_zone(hr: int) -> str:
    """Return the heart rate zone for a given BPM."""
    for zone_key, zone in HR_ZONES.items():
        if zone["min"] <= hr < zone["max"]:
            return zone_key
    return "zone_5"
