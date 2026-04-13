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

private let zoneNames: [String: String] = [
    "zone_1": "RECOVERY",
    "zone_2": "AEROBIC",
    "zone_3": "TEMPO",
    "zone_4": "THRESHOLD",
    "zone_5": "VO2 MAX",
]

// MARK: - Workout Live View

struct WorkoutLiveView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    @State private var displayedHeartRate: Int = 0
    @State private var animatedPulse: CGFloat = 1.0

    var body: some View {
        GeometryReader { geo in
            let contentW = geo.size.width

            VStack(spacing: 0) {
                // Top padding
                Spacer().frame(height: sp(8))

                // ── Primary Metric: Heart Rate ──────────────────────────────────
                HeartRateDisplay(heartRate: displayedHeartRate, zone: workoutManager.currentZone)
                    .frame(height: sp(60))

                // Spacing after HR
                Spacer().frame(height: sp(10))

                // ── Activity Rings ─────────────────────────────────────────────
                ActivityRingsView(
                    moveProgress: moveProgress,
                    exerciseProgress: exerciseProgress,
                    standProgress: standProgress
                )
                .frame(width: contentW, height: sp(130))

                // Spacing after rings
                Spacer().frame(height: sp(12))

                // ── Secondary Metrics ───────────────────────────────────────────
                SecondaryMetricsView(
                    elapsedSeconds: workoutManager.elapsedSeconds,
                    calories: workoutManager.activeCalories,
                    avgHeartRate: workoutManager.averageHeartRate
                )

                Spacer()

                // ── Controls ───────────────────────────────────────────────────
                HStack(spacing: sp(10)) {
                    PausePlayButton(isPlaying: workoutManager.workoutState == .running) {
                        if workoutManager.workoutState == .running {
                            workoutManager.pauseWorkout()
                        } else {
                            workoutManager.resumeWorkout()
                        }
                    }

                    EndWorkoutButton {
                        Task {
                            try? await workoutManager.endWorkout()
                        }
                    }
                }
                .padding(.horizontal, sp(16))
                .padding(.bottom, sp(8))
            }
        }
        .background(Color.black)
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

    // MARK: - Ring Progress (static for now — scaled by session data)

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

// MARK: - Heart Rate Display

struct HeartRateDisplay: View {
    let heartRate: Int
    let zone: String

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: CGFloat = 1.0

    private var zoneColor: Color {
        zoneColors[zone] ?? .gray
    }

    var body: some View {
        HStack(spacing: 0) {
            Spacer()

            // Heart icon with pulse
            Image(systemName: "heart.fill")
                .font(.system(size: sp(22)))
                .foregroundColor(zoneColor)
                .scaleEffect(pulseScale)
                .opacity(pulseOpacity)
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: 1.0)
                        .repeatForever(autoreverses: true)
                    ) {
                        pulseScale = 1.03
                        pulseOpacity = 0.85
                    }
                }

            // HR value — primary metric
            Text("\(heartRate)")
                .font(.system(size: sp(46), weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
                .contentTransition(.numericText())

            Spacer()
        }
    }
}

// MARK: - Activity Rings View

struct ActivityRingsView: View {
    let moveProgress: CGFloat
    let exerciseProgress: CGFloat
    let standProgress: CGFloat

    private let ringStroke: CGFloat = sp(10)
    private let ringGap: CGFloat = sp(5)

    private var outerRadius: CGFloat { sp(58) }
    private var middleRadius: CGFloat { outerRadius - ringStroke / 2 - ringGap / 2 }
    private var innerRadius: CGFloat { middleRadius - ringStroke / 2 - ringGap / 2 }

    var body: some View {
        ZStack {
            // Outer ring — Move (red)
            Circle()
                .trim(from: 0, to: moveProgress)
                .stroke(
                    ringMove,
                    style: StrokeStyle(lineWidth: ringStroke, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: outerRadius * 2, height: outerRadius * 2)

            // Middle ring — Exercise (green)
            Circle()
                .trim(from: 0, to: exerciseProgress)
                .stroke(
                    ringExercise,
                    style: StrokeStyle(lineWidth: ringStroke, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: middleRadius * 2, height: middleRadius * 2)

            // Inner ring — Stand (blue)
            Circle()
                .trim(from: 0, to: standProgress)
                .stroke(
                    ringStand,
                    style: StrokeStyle(lineWidth: ringStroke, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: innerRadius * 2, height: innerRadius * 2)
        }
        .animation(.linear(duration: 0.8), value: moveProgress)
        .animation(.linear(duration: 0.8), value: exerciseProgress)
        .animation(.linear(duration: 0.8), value: standProgress)
    }
}

// MARK: - Secondary Metrics View

struct SecondaryMetricsView: View {
    let elapsedSeconds: Int
    let calories: Double
    let avgHeartRate: Int

    private let rowHeight: CGFloat = sp(22)
    private let valueSize: CGFloat = sp(17)
    private let labelSize: CGFloat = sp(10)
    private let rowSpacing: CGFloat = sp(7)

    var body: some View {
        VStack(spacing: rowSpacing) {
            MetricRow(value: formatElapsed(elapsedSeconds), label: "TIME")
            MetricRow(value: "\(Int(calories))", label: "KCAL")
            MetricRow(value: "\(avgHeartRate)", label: "AVG BPM")
        }
        .padding(.horizontal, sp(12))
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
                .font(.system(size: sp(17), weight: .semibold, design: .rounded))
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

// MARK: - Control Buttons

struct PausePlayButton: View {
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: sp(56), height: sp(56))

                PausePlayIcon(isPlaying: isPlaying)
                    .frame(width: sp(24), height: sp(24))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
        .frame(width: sp(56), height: sp(56))
    }
}

struct EndWorkoutButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(ringMove)
                    .frame(width: sp(56), height: sp(56))

                EndWorkoutIcon()
                    .frame(width: sp(18), height: sp(18))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
        .frame(width: sp(56), height: sp(56))
    }
}

// MARK: - Custom Geometric Icons (no SF Symbols on watch controls)

struct PausePlayIcon: View {
    let isPlaying: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cx = w / 2
            let cy = h / 2

            Path { path in
                if isPlaying {
                    let bw: CGFloat = w * 0.13
                    let bh: CGFloat = h * 0.40
                    let gap: CGFloat = w * 0.10
                    path.addRect(CGRect(x: cx - gap - bw, y: cy - bh / 2, width: bw, height: bh))
                    path.addRect(CGRect(x: cx + gap, y: cy - bh / 2, width: bw, height: bh))
                } else {
                    let size: CGFloat = min(w, h) * 0.38
                    let tx = cx - size * 0.18
                    let ty = cy - size / 2
                    path.move(to: CGPoint(x: tx, y: ty))
                    path.addLine(to: CGPoint(x: tx + size, y: cy))
                    path.addLine(to: CGPoint(x: tx, y: ty + size))
                    path.closeSubpath()
                }
            }
            .fill(Color.white)
        }
    }
}

struct EndWorkoutIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let s = min(w, h) * 0.32

            Path { path in
                path.addRect(CGRect(x: (w - s) / 2, y: (h - s) / 2, width: s, height: s))
            }
            .fill(Color.white)
        }
    }
}

// MARK: - Preview

#Preview("Live") {
    WorkoutLiveView()
        .environmentObject(WorkoutManager.shared)
}
