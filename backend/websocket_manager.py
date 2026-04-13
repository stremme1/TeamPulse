"""WebSocket connection and broadcast management."""

import json
import asyncio
import logging
from typing import Dict, Set
from datetime import datetime

from fastapi import WebSocket

logger = logging.getLogger(__name__)


class ConnectionManager:
    """Manages WebSocket connections for live workout streaming."""

    def __init__(self):
        # athlete_id -> set of websocket connections
        self._connections: Dict[str, Set[WebSocket]] = {}
        # session_id -> set of subscribed athlete_ids (for broadcast)
        self._session_subscribers: Dict[str, Set[str]] = {}
        # Lock for thread-safe operations
        self._lock = asyncio.Lock()

    async def connect(self, websocket: WebSocket, athlete_id: str):
        """Accept a new WebSocket connection."""
        await websocket.accept()
        async with self._lock:
            if athlete_id not in self._connections:
                self._connections[athlete_id] = set()
            self._connections[athlete_id].add(websocket)
        logger.info(f"WebSocket connected: athlete_id={athlete_id}, total={len(self._connections[athlete_id])}")

    async def disconnect(self, websocket: WebSocket, athlete_id: str):
        """Remove a WebSocket connection."""
        async with self._lock:
            if athlete_id in self._connections:
                self._connections[athlete_id].discard(websocket)
                if not self._connections[athlete_id]:
                    del self._connections[athlete_id]
        logger.info(f"WebSocket disconnected: athlete_id={athlete_id}")

    async def subscribe_session(self, athlete_id: str, session_id: str):
        """Subscribe an athlete to a session's broadcast channel."""
        async with self._lock:
            if session_id not in self._session_subscribers:
                self._session_subscribers[session_id] = set()
            self._session_subscribers[session_id].add(athlete_id)
        logger.info(f"Athlete {athlete_id} subscribed to session {session_id}")

    async def unsubscribe_session(self, athlete_id: str, session_id: str):
        """Unsubscribe an athlete from a session."""
        async with self._lock:
            if session_id in self._session_subscribers:
                self._session_subscribers[session_id].discard(athlete_id)

    async def send_to_athlete(self, athlete_id: str, data: dict):
        """Send data to all connections for a specific athlete."""
        async with self._lock:
            connections = list(self._connections.get(athlete_id, set()))

        if not connections:
            return

        message = json.dumps(data, default=str)
        dead_connections = []

        for ws in connections:
            try:
                await ws.send_text(message)
            except Exception as e:
                logger.warning(f"Failed to send to websocket: {e}")
                dead_connections.append(ws)

        # Clean up dead connections
        if dead_connections:
            async with self._lock:
                for ws in dead_connections:
                    for aid, conns in list(self._connections.items()):
                        conns.discard(ws)
                        if not conns:
                            del self._connections[aid]

    async def broadcast_session(self, session_id: str, data: dict):
        """Broadcast data to all athletes subscribed to a session."""
        async with self._lock:
            athlete_ids = list(self._session_subscribers.get(session_id, set()))

        message = json.dumps(data, default=str)
        for athlete_id in athlete_ids:
            await self.send_to_athlete(athlete_id, data)

    async def broadcast_heart_rate(self, session_id: str, athlete_id: str, data: dict):
        """Broadcast heart rate data to all dashboard viewers and the athlete."""
        # Send to the athlete's own connections
        await self.send_to_athlete(athlete_id, {**data, "type": "heart_rate"})

        # Also broadcast to session subscribers (e.g., coach dashboards)
        async with self._lock:
            subscribers = list(self._session_subscribers.get(session_id, set()))

        for sub_id in subscribers:
            if sub_id != athlete_id:
                await self.send_to_athlete(sub_id, {**data, "type": "session_update"})

    @property
    def active_connections(self) -> int:
        return sum(len(conns) for conns in self._connections.values())

    @property
    def active_sessions(self) -> int:
        return len(self._session_subscribers)

    def get_stats(self) -> dict:
        return {
            "total_connections": self.active_connections,
            "total_sessions": self.active_sessions,
            "athletes": len(self._connections),
        }


# Global instance
manager = ConnectionManager()
