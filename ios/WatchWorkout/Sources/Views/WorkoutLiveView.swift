import SwiftUI
import WatchKit

// MARK: - Design System (45mm base: 198×242 pt)

/// Scale factor applied to all sizes for device proportionality.
/// 41mm → 0.88, 44mm → 0.93, 45mm → 1.0, 49mm → 1.06
private var scale: CGFloat {
    let w = WKInterfaceDevice.current().screenBounds.width
    return w / 198.0
}

private func sp(_ pts: CGFloat) -> CGFloat {
    pts * scale
}

// MARK: - Ring Colors

private let ringMove = Color(hex: "FF3B30")
private let ringExercise = Color(hex: "32D74B")
private let ringStand = Color(hex: "0A84FF")

// MARK: - Zone Colors

private let zoneColors: [String: Color] = [
    "zone_1": Color(hex: "5B8DFF"),
    "zone_2": Color(hex: "4ADE80"),
    "zone_3": Color(hex: "FACC15"),
    "zone_4": Color(hex: "FB923C"),
    "zone_5": Color(hex: "F87171"),
]

// MARK: - Workout Live View

struct WorkoutLiveView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    @State private var displayedHeartRate: Int = 0
    @State private var animatedPulse: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Top Padding: 8pt ─────────────────────────────────────────
                Spacer().frame(height: sp(8))

                // ── Primary Metric: Heart Rate ────────────────────────────────
                PrimaryHeartRateView(
                    heartRate: displayedHeartRate,
                    zone: workoutManager.currentZone
                )
                .frame(height: sp(60))

                // ── Spacing: 10pt ──────────────────────────────────────────────
                Spacer().frame(height: sp(10))

                // ── Activity Rings ────────────────────────────────────────────
                ActivityRingsView(
                    moveProgress: moveProgress,
                    exerciseProgress: exerciseProgress,
                    standProgress: standProgress
                )
                .frame(width: sp(120), height: sp(120))

                // ── Spacing: 14pt ─────────────────────────────────────────────
                Spacer().frame(height: sp(14))

                // ── Secondary Metrics ─────────────────────────────────────────
                SecondaryMetricsView(
                    elapsedSeconds: workoutManager.elapsedSeconds,
                    calories: workoutManager.activeCalories,
                    avgHeartRate: workoutManager.averageHeartRate
                )

                Spacer()

                // ── Bottom Padding: 8pt ────────────────────────────────────────
                Spacer().frame(height: sp(8))
            }
        }
        .onAppear {
            displayedHeartRate = workoutManager.currentHeartRate
        }
        .onChange(of: workoutManager.currentHeartRate) { oldValue, newValue in
            animateHeartRate(from: oldValue, to: newValue)
        }
    }

    // MARK: - Animated HR Interpolation

    private func animateHeartRate(from: Int, to: Int) {
        let start = from
        let end = to
        let duration: Double = 0.35
        let startTime = Date()

        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { timer in
            let elapsed = Date().timeIntervalSince(startTime)
            let t = min(elapsed / duration, 1.0)
            let eased = 1.0 - pow(1.0 - t, 3) // easeOut cubic

            displayedHeartRate = Int(Double(start) + Double(end - start) * eased)

            if t >= 1.0 {
                timer.invalidate()
            }
        }
    }

    // MARK: - Ring Progress

    private var moveProgress: CGFloat {
        let goal: Double = 500 // kcal
        return CGFloat(min(1.0, workoutManager.activeCalories / goal))
    }

    private var exerciseProgress: CGFloat {
        let goal: Double = 30 // min
        return CGFloat(min(1.0, Double(workoutManager.elapsedSeconds) / 60.0 / goal))
    }

    private var standProgress: CGFloat {
        CGFloat(min(1.0, Double(workoutManager.elapsedSeconds % 4) / 4.0))
    }
}

// MARK: - Primary Heart Rate View

struct PrimaryHeartRateView: View {
    let heartRate: Int
    let zone: String

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: CGFloat = 1.0

    private var zoneColor: Color {
        zoneColors[zone] ?? .gray
    }

    var body: some View {
        HStack(spacing: 0) {
            // Heart icon with subtle pulse
            Image(systemName: "heart.fill")
                .font(.system(size: sp(20)))
                .foregroundColor(zoneColor)
                .scaleEffect(pulseScale)
                .opacity(pulseOpacity)
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: 1.0)
                        .repeatForever(autoreverses: true)
                    ) {
                        pulseScale = 1.02
                        pulseOpacity = 0.9
                    }
                }

            // HR value — primary metric, 44pt semibold
            Text("\(heartRate)")
                .font(.system(size: sp(44), weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.35), value: heartRate)
        }
    }
}

// MARK: - Activity Rings View

struct ActivityRingsView: View {
    let moveProgress: CGFloat
    let exerciseProgress: CGFloat
    let standProgress: CGFloat

    // 45mm specs: outer=60pt radius, stroke=10pt, gap=5pt
    private let ringStroke: CGFloat = sp(10)
    private let ringGap: CGFloat = sp(5)

    private var outerRadius: CGFloat { sp(58) }
    private var middleRadius: CGFloat { outerRadius - ringStroke / 2 - ringGap / 2 }
    private var innerRadius: CGFloat { middleRadius - ringStroke / 2 - ringGap / 2 }

    var body: some View {
        ZStack {
            // Outer ring — Move (red)
            Circle()
                .trim(from: 0, to: max(0.001, moveProgress))
                .stroke(
                    ringMove,
                    style: StrokeStyle(lineWidth: ringStroke, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: outerRadius * 2, height: outerRadius * 2)
                .animation(.easeOut(duration: 0.8), value: moveProgress)

            // Middle ring — Exercise (green)
            Circle()
                .trim(from: 0, to: max(0.001, exerciseProgress))
                .stroke(
                    ringExercise,
                    style: StrokeStyle(lineWidth: ringStroke, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: middleRadius * 2, height: middleRadius * 2)
                .animation(.easeOut(duration: 0.8), value: exerciseProgress)

            // Inner ring — Stand (blue)
            Circle()
                .trim(from: 0, to: max(0.001, standProgress))
                .stroke(
                    ringStand,
                    style: StrokeStyle(lineWidth: ringStroke, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: innerRadius * 2, height: innerRadius * 2)
                .animation(.easeOut(duration: 0.8), value: standProgress)
        }
    }
}

// MARK: - Secondary Metrics View

struct SecondaryMetricsView: View {
    let elapsedSeconds: Int
    let calories: Double
    let avgHeartRate: Int

    private let rowHeight: CGFloat = sp(22)
    private let valueSize: CGFloat = sp(16)
    private let labelSize: CGFloat = sp(10)
    private let rowSpacing: CGFloat = sp(6)

    var body: some View {
        VStack(spacing: rowSpacing) {
            MetricRow(value: formatElapsed(elapsedSeconds), label: "TIME")
            MetricRow(value: "\(Int(calories))", label: "KCAL")
            MetricRow(value: "\(avgHeartRate)", label: "AVG BPM")
        }
    }

    private func formatElapsed(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

struct MetricRow: View {
    let value: String
    let label: String

    var body: some View {
        HStack {
            Text(value)
                .font(.system(size: sp(16), weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(label)
                .font(.system(size: sp(10), weight: .regular))
                .foregroundColor(Color(hex: "B3B3B3"))
                .frame(width: sp(60), alignment: .trailing)
        }
        .frame(height: sp(20))
    }
}

// MARK: - Preview

#Preview("Live") {
    WorkoutLiveView()
        .environmentObject(WorkoutManager.shared)
}
