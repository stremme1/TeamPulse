import SwiftUI

// MARK: - Zone Colors

enum ZoneColor {
    static let zone1 = Color(hex: "5B8DFF")   // Recovery - Blue
    static let zone2 = Color(hex: "4ADE80")   // Aerobic - Green
    static let zone3 = Color(hex: "FACC15")   // Tempo - Yellow
    static let zone4 = Color(hex: "FB923C")   // Threshold - Orange
    static let zone5 = Color(hex: "F87171")   // VO2 Max - Red

    static func color(for zone: String) -> Color {
        switch zone {
        case "zone_1": return zone1
        case "zone_2": return zone2
        case "zone_3": return zone3
        case "zone_4": return zone4
        case "zone_5": return zone5
        default: return zone1
        }
    }

    static func name(for zone: String) -> String {
        switch zone {
        case "zone_1": return "RECOVERY"
        case "zone_2": return "AEROBIC"
        case "zone_3": return "TEMPO"
        case "zone_4": return "THRESHOLD"
        case "zone_5": return "VO2 MAX"
        default: return "RECOVERY"
        }
    }

    static func number(for zone: String) -> Int {
        switch zone {
        case "zone_1": return 1
        case "zone_2": return 2
        case "zone_3": return 3
        case "zone_4": return 4
        case "zone_5": return 5
        default: return 1
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @EnvironmentObject var connectivityReceiver: WatchConnectivityReceiver
    @EnvironmentObject var backendSync: BackendSyncService

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if case .active = connectivityReceiver.sessionState {
                LiveWorkoutView()
            } else {
                IdleView()
            }
        }
    }
}

// MARK: - Live Workout View

struct LiveWorkoutView: View {
    @EnvironmentObject var connectivityReceiver: WatchConnectivityReceiver
    @State private var elapsedSeconds: Int = 0
    @State private var sessionStartDate: Date?

    private var formattedElapsed: String {
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        let s = elapsedSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Elapsed time — the primary metric
            Text(formattedElapsed)
                .font(.system(size: 80, weight: .thin, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
                .padding(.top, 20)

            // Heart rate zones bar
            HeartRateZonesBar(
                currentZone: connectivityReceiver.latestDataPoint?.zone ?? "zone_1"
            )
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Spacer()

            // Zone indicator
            if let dataPoint = connectivityReceiver.latestDataPoint {
                ZoneIndicator(
                    zone: dataPoint.zone,
                    heartRate: dataPoint.heartRate
                )
            }

            Spacer()

            // Bottom stats
            if let dataPoint = connectivityReceiver.latestDataPoint {
                BottomStats(calories: dataPoint.calories, distance: dataPoint.distance)
                    .padding(.bottom, 40)
            }

            // Session ID small label
            if let sessionId = connectivityReceiver.activeSessionId {
                Text(sessionId.prefix(8) + "...")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
                    .padding(.bottom, 16)
            }
        }
        .padding(.horizontal, 16)
        .onAppear {
            sessionStartDate = connectivityReceiver.lastReceivedDate
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard connectivityReceiver.sessionState != .idle else { return }

            if let start = sessionStartDate {
                elapsedSeconds = Int(Date().timeIntervalSince(start))
            } else if let dataPoint = connectivityReceiver.latestDataPoint {
                // Fallback: compute from timestamp
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: dataPoint.timestamp) {
                    sessionStartDate = date
                    elapsedSeconds = Int(Date().timeIntervalSince(date))
                }
            }
        }
        .onChange(of: connectivityReceiver.latestDataPoint?.timestamp) { _, _ in
            // When we get a new data point, ensure session start is set
            if sessionStartDate == nil,
               let dataPoint = connectivityReceiver.latestDataPoint {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: dataPoint.timestamp) {
                    sessionStartDate = date
                }
            }
        }
    }
}

// MARK: - Heart Rate Zones Bar

struct HeartRateZonesBar: View {
    let currentZone: String

    private var currentZoneNumber: Int {
        ZoneColor.number(for: currentZone)
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { zone in
                RoundedRectangle(cornerRadius: 4)
                    .fill(zone <= currentZoneNumber ? ZoneColor.color(for: "zone_\(zone)") : Color.white.opacity(0.12))
                    .frame(height: 6)
            }
        }
    }
}

// MARK: - Zone Indicator

struct ZoneIndicator: View {
    let zone: String
    let heartRate: Int

    var body: some View {
        HStack(spacing: 16) {
            // Zone badge
            VStack(spacing: 4) {
                Text("ZONE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))

                Text("\(ZoneColor.number(for: zone))")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundColor(ZoneColor.color(for: zone))
            }

            VStack(alignment: .leading, spacing: 6) {
                // Zone name
                Text(ZoneColor.name(for: zone))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(ZoneColor.color(for: zone))

                // Heart icon + BPM
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 28))
                        .foregroundColor(ZoneColor.color(for: zone))

                    Text("\(heartRate)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                }

                Text("BPM")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
}

// MARK: - Bottom Stats

struct BottomStats: View {
    let calories: Double
    let distance: Double

    var body: some View {
        HStack(spacing: 0) {
            StatColumn(
                value: "\(Int(calories))",
                unit: "kcal",
                icon: "flame.fill",
                iconColor: .orange
            )

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1, height: 50)

            StatColumn(
                value: String(format: "%.2f", distance / 1000),
                unit: "km",
                icon: "figure.run",
                iconColor: .green
            )
        }
        .padding(.horizontal, 40)
    }
}

struct StatColumn: View {
    let value: String
    let unit: String
    let icon: String
    let iconColor: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(iconColor)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                    Text(unit)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Idle View

struct IdleView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.3))

            VStack(spacing: 8) {
                Text("Ready to Sync")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white)

                Text("Start a workout on your Apple Watch")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }

            // Connection status row
            HStack(spacing: 24) {
                WatchStatusBadge()
                ServerStatusBadge()
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 32)
    }
}

struct WatchStatusBadge: View {
    @EnvironmentObject var connectivityReceiver: WatchConnectivityReceiver

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: connectivityReceiver.isWatchConnected ? "applewatch.checkmark" : "applewatch.slash")
                .font(.system(size: 24))
                .foregroundColor(connectivityReceiver.isWatchConnected ? .green : .white.opacity(0.3))

            Text("Watch")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.5))

            Text(connectivityReceiver.isWatchConnected ? "Connected" : "Disconnected")
                .font(.system(size: 10))
                .foregroundColor(connectivityReceiver.isWatchConnected ? .green : .white.opacity(0.3))
        }
    }
}

struct ServerStatusBadge: View {
    @EnvironmentObject var backendSync: BackendSyncService

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: backendSync.isConnected ? "wifi" : "wifi.slash")
                .font(.system(size: 24))
                .foregroundColor(backendSync.isConnected ? .green : .white.opacity(0.3))

            Text("Server")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.5))

            Text(backendSync.isConnected ? "Online" : "Offline")
                .font(.system(size: 10))
                .foregroundColor(backendSync.isConnected ? .green : .white.opacity(0.3))
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
        .environmentObject(WatchConnectivityReceiver.shared)
        .environmentObject(BackendSyncService.shared)
        .environmentObject(OfflineQueueManager.shared)
}
