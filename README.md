# Workout System — Real-Time Athlete Performance Platform

A production-feasible MVP replicating Apple Workout–like behavior:
- Apple Watch runs foreground workouts with HKWorkoutSession + HKLiveWorkoutBuilder
- Real-time heart rate streams to iPhone via WatchConnectivity (works even when app is closed)
- iPhone relays live data to backend via WebSocket (< 2s latency)
- Live web dashboard updates in real-time
- Post-workout recovery metrics (sleep, SpO₂, HRV, resting HR) sync from HealthKit

## Architecture

```
┌─────────────────┐      WatchConnectivity       ┌─────────────────┐
│  Apple Watch    │────────────────────────────▶│    iPhone       │
│  (WatchWorkout) │  sendMessage / transferUserInfo │(WorkoutSync)  │
│                 │                             │                 │
│  HKWorkoutSession│                            │ HealthKit       │
│  HKLiveWorkoutBuilder │                       │ (background del.)│
│  WebSocket ─────┼─── WebSocket ─────────────▶│ WebSocket ──────┼──┐
└─────────────────┘                             └─────────────────┘  │
                                                                       │
                                              ┌─────────────────┐      │
                                              │  Backend Server  │◀─────┘
                                              │  (Python/FastAPI)│
                                              │                  │
                                              │  WebSocket       │
                                              │  REST API        │
                                              │  SQLite          │
                                              └────────┬─────────┘
                                                       │
                                              ┌────────▼─────────┐
                                              │  Web Dashboard  │
                                              │  (HTML/CSS/JS)  │
                                              │  WebSocket      │
                                              └─────────────────┘
```

## Project Structure

```
workout-system/
├── backend/
│   ├── main.py              # FastAPI app (WebSocket + REST)
│   ├── models.py            # SQLite database operations
│   ├── websocket_manager.py # WebSocket connection manager
│   ├── config.py            # Heart rate zones, settings
│   ├── requirements.txt     # Python dependencies
│   └── test_client.py        # WebSocket test client
│
├── ios/
│   ├── project.yml          # XcodeGen configuration
│   ├── Podfile              # CocoaPods (optional)
│   │
│   ├── WorkoutSync/         # iPhone companion app
│   │   ├── Info.plist
│   │   ├── WorkoutSync.entitlements
│   │   ├── Assets.xcassets/
│   │   └── Sources/
│   │       ├── App/WorkoutSyncApp.swift
│   │       ├── HealthKit/HealthKitManager.swift
│   │       ├── Connectivity/WatchConnectivityReceiver.swift
│   │       ├── Networking/BackendSyncService.swift
│   │       ├── Networking/OfflineQueueManager.swift
│   │       └── Views/
│   │           ├── ContentView.swift
│   │           └── OnboardingView.swift
│   │
│   └── WatchWorkout/         # Apple Watch app
│       ├── Info.plist
│       ├── WatchWorkout.entitlements
│       ├── Assets.xcassets/
│       └── Sources/
│           ├── App/WatchWorkoutApp.swift
│           ├── Workout/WorkoutManager.swift
│           ├── Connectivity/WatchConnectivityManager.swift
│           ├── Networking/WebSocketClient.swift
│           └── Views/
│               ├── ContentView.swift
│               ├── WorkoutLiveView.swift
│               └── WorkoutSummaryView.swift
│
└── dashboard/
    ├── index.html           # Live dashboard (single file, no build)
    └── SPEC.md              # Design specification
```

## Prerequisites

- **macOS** with Xcode 15+
- **Python 3.10+** with pip (for backend)
- **Apple Developer Account** (for device deployment, code signing)
- **Physical devices** (Watch + iPhone) — simulators don't support HealthKit/WorkoutSession

## Setup & Build

### 1. Backend Server

```bash
cd workout-system/backend
pip install -r requirements.txt
python3 -m uvicorn main:app --host 0.0.0.0 --port 8000
```

Or use the run script:
```bash
chmod +x backend/run.sh
./backend/run.sh
```

Test with the WebSocket client:
```bash
python3 test_client.py
```

### 2. iOS Apps

**Step 1:** Generate the Xcode project
```bash
cd ios

# Install XcodeGen if not already installed
brew install xcodegen

# Generate project
xcodegen generate
```

**Step 2:** Configure signing
- Open `WorkoutSystem.xcodeproj` in Xcode
- Select each target (WorkoutSync, WatchWorkout)
- Set your Development Team in Signing & Capabilities
- Update Bundle Identifiers if needed

**Step 3:** Build and run
```bash
# Open in Xcode
open WorkoutSystem.xcodeproj

# Or build from command line
xcodebuild -project WorkoutSystem.xcodeproj \
  -scheme WorkoutSync \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  build
```

**Step 4:** Run on devices
- Deploy to physical iPhone + Apple Watch
- The Watch app embeds in the iPhone app bundle

### 3. Web Dashboard

Open directly in a browser:
```bash
# From the dashboard directory
open dashboard/index.html

# Or serve with Python
cd dashboard && python3 -m http.server 3000
```

For live data, ensure the backend is running and update the `CONFIG.backendUrl` in `index.html` to point to your backend host.

## Key Technical Decisions

### Watch → iPhone Sync (WatchConnectivity)
- **sendMessage** — real-time when iPhone app is open (~immediate)
- **transferUserInfo** — guaranteed delivery when iPhone app is closed (queued by system)
- **updateApplicationContext** — for complications / glance data

### iPhone → Backend
- **WebSocket** — primary path for live data (< 1s latency)
- **HTTP POST** — fallback for reliability
- **OfflineQueue** — SQLite-backed queue ensures no data loss

### Backend → Dashboard
- **WebSocket broadcast** — all subscribed dashboard clients receive live HR updates
- **Session-based subscriptions** — dashboards subscribe to specific session IDs

### Post-Workout Recovery Sync
- **HKObserverQuery** — fires when new HealthKit data is available
- **BGTaskScheduler** — periodic refresh for recovery metrics
- **Scores computed client-side** using HRV, sleep, and resting HR

## Heart Rate Zones

| Zone | Name       | BPM Range  |
|------|------------|-----------|
| Z1   | Recovery   | < 114     |
| Z2   | Aerobic    | 114–133   |
| Z3   | Tempo      | 133–152   |
| Z4   | Threshold  | 152–171   |
| Z5   | VO2 Max    | ≥ 171     |

## API Reference

### WebSocket
```
ws://localhost:8000/ws/{athlete_id}
```

**Subscribe:**
```json
{"type": "subscribe", "session_id": "..."}
```

**Send heart rate:**
```json
{
  "type": "heart_rate",
  "athlete_id": "...",
  "session_id": "...",
  "timestamp": "2024-01-01T00:00:00Z",
  "heart_rate": 148,
  "zone": "zone_3",
  "calories": 420,
  "distance": 3200,
  "device_status": "watch"
}
```

### REST Endpoints
- `POST /api/sessions/start` — Start a new session
- `POST /api/sessions/{id}/end` — End a session
- `POST /api/data/heart-rate` — Ingest heart rate data point
- `POST /api/data/batch` — Batch ingest for offline replay
- `POST /api/recovery/sync` — Sync recovery metrics
- `GET /api/recovery/{athlete_id}` — Get recovery history
- `GET /api/dashboard/{athlete_id}/live` — Get current session data
- `GET /api/health` — Health check

## Configuration

### Backend
Environment variables (`.env` or shell):
- `BACKEND_HOST` — default `0.0.0.0`
- `PORT` — default `8000`
- `DB_PATH` — SQLite database path

### iPhone App
In `BackendSyncService.swift`, update `backendHost` and `backendPort` to point to your server IP (not `localhost` — devices can't reach macOS localhost).

### Watch App
Same in `WebSocketClient.swift`.

## Security & Privacy

- All traffic should use HTTPS/WSS in production (currently HTTP for MVP convenience)
- Use anonymized athlete IDs (not real names)
- HealthKit data stays on-device except for workout metrics
- No persistent raw health data on the server (only aggregates)
- Production deployment requires App Transport Security configuration

## Demo Mode

The web dashboard includes a built-in demo mode that simulates realistic workout data locally — useful for UI development and demos without running the full system.

## Troubleshooting

**Watch app doesn't connect to iPhone:**
- Ensure both devices are paired with the same iCloud account
- Check that the Watch app is installed on the Watch
- Verify the Bundle ID matches between targets and provisioning profiles

**HealthKit data not syncing:**
- Check HealthKit authorization in Settings → Privacy → Health
- Ensure the HealthKit entitlement is configured in your provisioning profile
- HealthKit background delivery requires a physical device

**WebSocket connection refused on device:**
- Devices can't reach `localhost` — use your machine's local IP address
- Update `backendHost` in both `BackendSyncService.swift` and `WebSocketClient.swift`
- Ensure the backend server is binding to `0.0.0.0` not `127.0.0.1`

**No data appearing on dashboard:**
- Check browser console for WebSocket errors
- Verify the backend is running: `curl http://localhost:8000/api/health`
- Use demo mode to verify the dashboard works independently
