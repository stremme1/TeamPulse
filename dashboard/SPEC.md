# Workout System Dashboard — SPEC

## 1. Concept & Vision

A real-time athlete performance dashboard that feels like mission control for elite training. The interface communicates precision, reliability, and focus — zero noise, maximum signal. Inspired by F1 race engineering displays, aerospace telemetry panels, and high-end sports science tools. Every pixel earns its place.

## 2. Design Language

### Aesthetic Direction
**Technical Precision / Dark Instrument Panel** — Think a Bloomberg terminal crossed with a supercar's digital cockpit. Dense but not cluttered. Information is hierarchical: critical data commands attention, context supports it.

### Color Palette
- **Background Deep**: `#080A0D` — near-black with cool undertone
- **Background Surface**: `#0D1117` — card/panel surfaces
- **Background Elevated**: `#161B22` — raised elements, hover states
- **Border Subtle**: `#21262D` — dividers, panel borders
- **Text Primary**: `#E6EDF3` — primary content
- **Text Secondary**: `#7D8590` — labels, secondary info
- **Text Muted**: `#484F58` — disabled, timestamps

- **Zone 1 (Recovery)**: `#3B82F6` — cool blue
- **Zone 2 (Aerobic)**: `#22C55E` — green
- **Zone 3 (Tempo)**: `#EAB308` — yellow
- **Zone 4 (Threshold)**: `#F97316` — orange
- **Zone 5 (VO2 Max)**: `#EF4444` — red
- **Accent / Active**: `#58A6FF` — interactive elements, highlights

### Typography
- **Numeric Display**: `'JetBrains Mono', 'SF Mono', monospace` — for all numbers, metrics, timestamps
- **Labels / UI**: `'Inter', system-ui, sans-serif` — for labels, navigation, body text
- **Scale**: 11px (micro labels) → 13px (body) → 15px (emphasis) → 24px (sub-heading) → 48px (primary metric) → 80px (hero metric)

### Spatial System
- Base unit: 4px
- Panel padding: 16px (4 units)
- Section gaps: 12px
- Card border-radius: 6px
- Micro border-radius: 3px

### Motion Philosophy
- Transitions: 150ms ease-out for state changes
- Data updates: no animation — instant swap (data dashboards should feel real-time, not theatrical)
- Zone color transitions: 300ms ease-in-out (the one exception — communicates shifting intensity)
- Chart line: smooth CSS transition on new data points

### Visual Assets
- All icons: custom inline SVG (no icon library)
- Charts: custom SVG/Canvas rendering (no charting library)
- No photography, no illustrations
- Decorative: subtle grid pattern on background, thin 1px rule dividers

## 3. Layout & Structure

### Overall Architecture
```
┌─────────────────────────────────────────────────────┐
│  HEADER: Logo | Session Status | Athlete ID | Time  │
├─────────────────────────────────────────────────────┤
│  HERO PANEL                                          │
│  ┌───────────────────────────────────────────────┐  │
│  │  148 bpm         ZONE 4: THRESHOLD            │  │
│  │  ████████░░       12:34 elapsed               │  │
│  │  HR TREND CHART                                │  │
│  └───────────────────────────────────────────────┘  │
├──────────────┬──────────────┬───────────────────────┤
│  CALORIES    │  DISTANCE   │   TIME IN ZONES       │
│  847 kcal    │  5.2 km     │   [bar chart]         │
├──────────────┴──────────────┴───────────────────────┤
│  HRV TREND (last 7 days)  |  RECOVERY SCORE PANEL   │
│  [sparkline chart]        |  R: 78  F: 45  R: 92   │
├─────────────────────────────────────────────────────┤
│  SESSION HISTORY (last 5)                          │
│  [compact list with metrics]                        │
└─────────────────────────────────────────────────────┘
```

### Responsive Strategy
- Primary target: desktop (1280px+) — this is the coach/athlete viewing station
- Tablet (768px+): stack hero + metrics vertically, 2-column history
- Mobile (< 768px): single column, hero dominates
- No horizontal scroll at any breakpoint

## 4. Features & Interactions

### Connection Management
- Auto-connect to WebSocket on page load
- Connection status indicator in header (dot: green=connected, amber=reconnecting, red=disconnected)
- Auto-reconnect with exponential backoff (1s, 2s, 4s, max 30s)
- Manual reconnect button when disconnected

### Session Control
- "Connect to Session" — input field for session ID + athlete ID
- Demo mode button — simulates data locally for UI testing
- "Start Demo" auto-generates realistic workout data

### Live Data Display
- Heart rate: updates in real-time, hero number in large mono font
- Zone indicator: colored bar + zone name text, color matches zone
- HR trend chart: last 60 seconds as a line chart, color-coded by zone
- Calories: cumulative, updates with each data point
- Distance: cumulative meters/km, updates with each data point
- Elapsed time: computed from session start, MM:SS format

### Time in Zones
- Horizontal bar chart showing percentage distribution
- Each zone has its designated color
- Shows seconds spent and percentage
- Updates live as workout progresses

### Post-Workout Data
- Recovery metrics panel shows latest available data
- HRV sparkline for last 7 days
- Recovery / Fatigue / Readiness scores with circular indicators

### Session History
- Last 5 completed sessions
- Compact row format: date, type, duration, avg HR, calories
- Click to expand (shows full zone breakdown)

### Error States
- Connection lost: subtle banner at top, amber colored
- Session not found: inline error message
- Empty data: muted placeholder text, no loading spinners

## 5. Component Inventory

### ConnectionStatusDot
- States: connected (green pulse), reconnecting (amber blink), disconnected (red static)
- 8px circle, subtle glow effect when connected

### MetricCard
- Label (text-secondary, 11px uppercase, letter-spaced)
- Value (text-primary, 24px mono)
- Unit (text-secondary, 13px)
- Subtle border, surface background
- No hover effect (passive display)

### HeartRateHero
- Large BPM number (80px mono, zone-colored)
- Zone name and description
- Mini trend line (last 30 readings)
- Zone progress bar (current zone intensity as fill)

### ZoneBarChart
- Horizontal stacked bar
- Each zone colored per palette
- Percentage labels at right
- Time (seconds) labels at left

### HRTrendChart
- Canvas-based line chart
- X-axis: last 60 seconds (rolling window)
- Y-axis: HR range (auto-scaling with padding)
- Line colored per zone of each point
- Subtle grid lines
- Current HR dot at end of line

### RecoveryScoreRing
- SVG circular progress indicator
- Score number centered
- Color: green (>75), yellow (50-75), red (<50)
- Label below: "Recovery", "Fatigue", "Readiness"

### Sparkline
- Simple inline SVG polyline
- 7 data points for weekly trend
- Color: accent blue
- No axes, no labels (context comes from surrounding UI)

### SessionHistoryRow
- Date (text-secondary, 13px)
- Workout type icon (custom SVG)
- Duration | Avg HR | Calories (text-primary, 13px mono)
- Expandable with zone breakdown

### Header
- Left: wordmark "WORKOUT" in caps, letter-spaced, text-primary
- Center: connection status + session ID
- Right: current time (updates every second), athlete ID

## 6. Technical Approach

### Stack
- Single HTML file with embedded CSS and JavaScript
- No frameworks, no build step, no external JS dependencies
- WebSocket connection to backend for live data
- REST API calls for historical data (sessions, recovery metrics)
- Canvas API for trend charts, SVG for decorative/indicator elements

### WebSocket Protocol
- Connect: `ws://host:port/ws/{dashboard_athlete_id}`
- Subscribe: `{"type": "subscribe", "session_id": "..."}`
- Receive: `{type, athlete_id, session_id, timestamp, heart_rate, zone, calories, distance}`

### Data Flow
1. Dashboard loads → connects WebSocket
2. User enters session ID → subscribes
3. Backend broadcasts HR data → dashboard updates
4. REST API called for recovery metrics, session history

### Demo Mode
- Generates synthetic data locally when no backend is available
- Simulates realistic HR progression, zone changes
- Same data format as real backend
