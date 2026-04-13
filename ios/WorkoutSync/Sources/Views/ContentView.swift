import SwiftUI

// MARK: - Content View

struct ContentView: View {
    @EnvironmentObject var connectivityReceiver: WatchConnectivityReceiver
    @EnvironmentObject var backendSync: BackendSyncService
    @EnvironmentObject var offlineQueue: OfflineQueueManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Connection row
                    ConnectionRow()
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                    // Active session
                    if connectivityReceiver.sessionState != .idle {
                        ActiveSessionSection()
                    }

                    // Offline queue
                    if offlineQueue.queuedCount > 0 {
                        OfflineQueueRow(count: offlineQueue.queuedCount)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                    }

                    // Actions row
                    ActionsRow()
                        .padding(.horizontal, 16)
                        .padding(.top, 20)

                    // Recent sessions
                    RecentSessionsSection()
                        .padding(.top, 24)
                }
                .padding(.bottom, 32)
            }
            .background(Color(.systemBackground))
            .navigationTitle("WorkoutSync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ConnectionDot(state: backendSync.connectionState)
                }
            }
        }
    }
}

// MARK: - Connection Row

struct ConnectionRow: View {
    @EnvironmentObject var connectivityReceiver: WatchConnectivityReceiver
    @EnvironmentObject var backendSync: BackendSyncService

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Watch")
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Text(connectivityReceiver.isWatchConnected ? "Connected" : "Disconnected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Server")
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Text(backendSync.isConnected ? "Connected" : "Offline")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Last HR
            if let hr = connectivityReceiver.lastReceivedHeartRate {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(hr)")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(HRColor.color(for: hr))
                    Text("BPM")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Connection Dot

struct ConnectionDot: View {
    let state: BackendSyncService.ConnectionState

    private var color: Color {
        switch state {
        case .connected: return .green
        case .connecting, .reconnecting: return .orange
        case .disconnected: return .gray
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }
}

// MARK: - HR Color

struct HRColor {
    static func color(for hr: Int) -> Color {
        if hr < 114 { return Color(hex: "5B8DFF") }
        if hr < 133 { return Color(hex: "4ADE80") }
        if hr < 152 { return Color(hex: "FACC15") }
        if hr < 171 { return Color(hex: "FB923C") }
        return Color(hex: "F87171")
    }
}

// MARK: - Active Session Section

struct ActiveSessionSection: View {
    @EnvironmentObject var connectivityReceiver: WatchConnectivityReceiver

    var body: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Text("LIVE WORKOUT")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                Spacer()

                // Live indicator
                LiveDot()
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 8)

            // Metrics row
            if let dataPoint = connectivityReceiver.latestDataPoint {
                HStack(spacing: 0) {
                    LiveMetric(value: "\(dataPoint.heartRate)", unit: "BPM", label: "Heart Rate")
                    Divider().frame(height: 32)
                    LiveMetric(value: "\(Int(dataPoint.calories))", unit: "kcal", label: "Calories")
                    Divider().frame(height: 32)
                    LiveMetric(
                        value: String(format: "%.1f", dataPoint.distance / 1000),
                        unit: "km",
                        label: "Distance"
                    )
                }
                .padding(.horizontal, 16)
            }

            // Session ID
            if let sessionId = connectivityReceiver.activeSessionId {
                HStack {
                    Text("Session")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(sessionId.prefix(12) + "...")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Live Dot

struct LiveDot: View {
    @State private var opacity: Double = 1

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
                .opacity(opacity)
            Text("LIVE")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.red)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1).repeatForever()) {
                opacity = 0.3
            }
        }
    }
}

// MARK: - Live Metric

struct LiveMetric: View {
    let value: String
    let unit: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.primary)
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Offline Queue Row

struct OfflineQueueRow: View {
    let count: Int

    var body: some View {
        HStack {
            SyncQueueIcon()
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(count) queued")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                Text("Will sync when connected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Sync") {
                OfflineQueueManager.shared.forceSync()
            }
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.blue)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(8)
    }
}

// MARK: - Actions Row

struct ActionsRow: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ActionChip(label: "Sync Health", icon: {
                    AnyView(HealthIcon())
                }) {
                    Task {
                        await HealthKitManager.shared.syncRecoveryMetrics(
                            athleteId: "athlete-001",
                            sessionId: nil,
                            for: Date()
                        )
                    }
                }

                ActionChip(label: "Reconnect", icon: {
                    AnyView(ReconnectIcon())
                }) {
                    Task {
                        await BackendSyncService.shared.connect(athleteId: "athlete-001")
                    }
                }

                ActionChip(label: "Flush Queue", icon: {
                    AnyView(FlushIcon())
                }) {
                    OfflineQueueManager.shared.forceSync()
                }

                ActionChip(label: "Clear", icon: {
                    AnyView(ClearIcon())
                }) {
                    OfflineQueueManager.shared.clearQueue()
                }
            }
        }
    }
}

struct ActionChip: View {
    let label: String
    let icon: () -> AnyView
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                icon()
                    .frame(width: 14, height: 14)
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Custom Icons

struct HealthIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                let cx = w / 2
                let top = h * 0.25
                let bot = h * 0.80
                let mid = h / 2
                path.move(to: CGPoint(x: cx, y: top))
                path.addLine(to: CGPoint(x: cx - 1, y: mid))
                path.addLine(to: CGPoint(x: cx - 3, y: mid - 1))
                path.addLine(to: CGPoint(x: cx - 1, y: mid))
                path.addLine(to: CGPoint(x: cx + 1, y: mid + 2))
                path.addLine(to: CGPoint(x: cx + 3, y: mid))
                path.addLine(to: CGPoint(x: cx + 1, y: mid))
                path.addLine(to: CGPoint(x: cx, y: top))
                path.addLine(to: CGPoint(x: cx, y: bot))
            }
            .stroke(lineWidth: 1.2)
        }
    }
}

struct ReconnectIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let r = min(w, h) / 2 - 1
            let cx = w / 2
            let cy = h / 2
            Path { path in
                path.addArc(
                    center: CGPoint(x: cx, y: cy),
                    radius: r,
                    startAngle: .degrees(45),
                    endAngle: .degrees(315),
                    clockwise: false
                )
                // Arrow
                path.move(to: CGPoint(x: cx, y: cy - r + 2))
                path.addLine(to: CGPoint(x: cx + 2, y: cy - r + 5))
                path.addLine(to: CGPoint(x: cx - 2, y: cy - r + 5))
                path.closeSubpath()
            }
            .stroke(lineWidth: 1.2)
        }
    }
}

struct FlushIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                // Down arrow
                path.move(to: CGPoint(x: w / 2, y: 1))
                path.addLine(to: CGPoint(x: w / 2, y: h - 1))
                path.move(to: CGPoint(x: w / 2 - 2, y: h - 4))
                path.addLine(to: CGPoint(x: w / 2, y: h - 1))
                path.addLine(to: CGPoint(x: w / 2 + 2, y: h - 4))
                // Up arrow
                path.move(to: CGPoint(x: 1, y: h / 2))
                path.addLine(to: CGPoint(x: w - 1, y: h / 2))
                path.move(to: CGPoint(x: w - 4, y: h / 2 - 2))
                path.addLine(to: CGPoint(x: w - 1, y: h / 2))
                path.addLine(to: CGPoint(x: w - 4, y: h / 2 + 2))
            }
            .stroke(lineWidth: 1.2)
        }
    }
}

struct ClearIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                path.move(to: CGPoint(x: 2, y: 2))
                path.addLine(to: CGPoint(x: w - 2, y: h - 2))
                path.move(to: CGPoint(x: w - 2, y: 2))
                path.addLine(to: CGPoint(x: 2, y: h - 2))
            }
            .stroke(lineWidth: 1.2)
        }
    }
}

struct SyncQueueIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                path.addEllipse(in: CGRect(x: 2, y: 2, width: w - 4, height: h - 4))
                path.move(to: CGPoint(x: w / 2, y: 2))
                path.addLine(to: CGPoint(x: w / 2, y: h / 2))
            }
            .stroke(lineWidth: 1.2)
        }
    }
}

// MARK: - Recent Sessions Section

struct RecentSessionsSection: View {
    @State private var sessions: [SessionSummary] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RECENT")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(0.5)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            if sessions.isEmpty {
                VStack(spacing: 6) {
                    EmptyIcon()
                        .frame(width: 32, height: 32)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No sessions yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                ForEach(sessions.prefix(5)) { session in
                    SessionRow(session: session)
                    if session.id != sessions.prefix(5).last?.id {
                        Divider()
                            .padding(.horizontal, 16)
                    }
                }
            }
        }
        .onAppear {
            loadSessions()
        }
    }

    private func loadSessions() {
        sessions = [
            SessionSummary(id: "1", type: "running", date: Date().addingTimeInterval(-86400), duration: 3600, calories: 620, avgHR: 148, distance: 8200),
            SessionSummary(id: "2", type: "strength", date: Date().addingTimeInterval(-2*86400), duration: 2700, calories: 380, avgHR: 112, distance: 0),
            SessionSummary(id: "3", type: "running", date: Date().addingTimeInterval(-3*86400), duration: 4200, calories: 780, avgHR: 155, distance: 9500),
        ]
    }
}

struct SessionRow: View {
    let session: SessionSummary

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(session.type.capitalized)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(session.date, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 16) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(formatDuration(session.duration))
                        .font(.subheadline)
                        .monospacedDigit()
                    Text("duration")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(session.avgHR)")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundColor(HRColor.color(for: session.avgHR))
                    Text("avg bpm")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(session.calories)")
                        .font(.subheadline)
                        .monospacedDigit()
                    Text("kcal")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

struct SessionSummary: Identifiable {
    let id: String
    let type: String
    let date: Date
    let duration: Int
    let calories: Int
    let avgHR: Int
    let distance: Double
}

struct EmptyIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                path.addEllipse(in: CGRect(x: w * 0.25, y: h * 0.15, width: w * 0.5, height: w * 0.5))
                path.addEllipse(in: CGRect(x: w * 0.15, y: h * 0.25, width: w * 0.7, height: w * 0.5))
            }
            .stroke(lineWidth: 1)
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(HealthKitManager.shared)
        .environmentObject(WatchConnectivityReceiver.shared)
        .environmentObject(BackendSyncService.shared)
        .environmentObject(OfflineQueueManager.shared)
}
