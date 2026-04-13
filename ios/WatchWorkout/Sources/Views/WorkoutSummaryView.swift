import SwiftUI
import WatchKit

// MARK: - Design System (45mm base: 198×242 pt)

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

private let zoneColorDefault = Color(hex: "5B8DFF")

// MARK: - Workout Summary View

struct WorkoutSummaryView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    @State private var animatedMove: CGFloat = 0
    @State private var animatedExercise: CGFloat = 0
    @State private var animatedStand: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Top Padding: 8pt ─────────────────────────────────────────
                Spacer().frame(height: sp(8))

                // ── Workout Type Label ───────────────────────────────────────
                Text(workoutManager.selectedWorkoutType.displayName.uppercased())
                    .font(.system(size: sp(10), weight: .medium))
                    .foregroundColor(Color(hex: "B3B3B3"))
                    .tracking(1.0)

                // ── Spacing: 4pt ─────────────────────────────────────────────
                Spacer().frame(height: sp(4))

                // ── Primary Metric: Duration ──────────────────────────────────
                VStack(spacing: 2) {
                    Text(formatElapsed(workoutManager.elapsedSeconds))
                        .font(.system(size: sp(42), weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)

                    Text("DURATION")
                        .font(.system(size: sp(9), weight: .regular))
                        .foregroundColor(Color(hex: "B3B3B3"))
                }

                // ── Spacing: 10pt ────────────────────────────────────────────
                Spacer().frame(height: sp(10))

                // ── Activity Rings ─────────────────────────────────────────────
                SummaryActivityRings(
                    moveProgress: animatedMove,
                    exerciseProgress: animatedExercise,
                    standProgress: animatedStand
                )
                .frame(width: sp(120), height: sp(120))

                // ── Spacing: 12pt ────────────────────────────────────────────
                Spacer().frame(height: sp(12))

                // ── Secondary Stats ───────────────────────────────────────────
                SummaryStatsGrid(
                    avgHeartRate: workoutManager.averageHeartRate,
                    maxHeartRate: workoutManager.maxHeartRate,
                    calories: workoutManager.activeCalories,
                    distance: workoutManager.distance
                )

                Spacer()

                // ── Zone Bar ─────────────────────────────────────────────────
                ZoneBar(avgZone: workoutManager.currentZone)
                    .frame(height: sp(6))
                    .padding(.horizontal, sp(12))

                // ── Spacing: 8pt ─────────────────────────────────────────────
                Spacer().frame(height: sp(8))

                // ── Done Button ──────────────────────────────────────────────
                Button {
                    // Reset handled by WorkoutManager state change
                } label: {
                    Text("Done")
                        .font(.system(size: sp(14), weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: sp(38))
                        .background(Color.white)
                        .cornerRadius(sp(19))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, sp(12))

                // ── Bottom Padding: 8pt ────────────────────────────────────────
                Spacer().frame(height: sp(8))
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                animatedMove = 0.85
            }
            withAnimation(.easeOut(duration: 0.8).delay(0.15)) {
                animatedExercise = 0.60
            }
            withAnimation(.easeOut(duration: 0.8).delay(0.30)) {
                animatedStand = 0.45
            }
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

// MARK: - Summary Activity Rings

struct SummaryActivityRings: View {
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
            Circle()
                .trim(from: 0, to: max(0.001, moveProgress))
                .stroke(ringMove, style: StrokeStyle(lineWidth: ringStroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: outerRadius * 2, height: outerRadius * 2)

            Circle()
                .trim(from: 0, to: max(0.001, exerciseProgress))
                .stroke(ringExercise, style: StrokeStyle(lineWidth: ringStroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: middleRadius * 2, height: middleRadius * 2)

            Circle()
                .trim(from: 0, to: max(0.001, standProgress))
                .stroke(ringStand, style: StrokeStyle(lineWidth: ringStroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: innerRadius * 2, height: innerRadius * 2)
        }
    }
}

// MARK: - Summary Stats Grid

struct SummaryStatsGrid: View {
    let avgHeartRate: Int
    let maxHeartRate: Int
    let calories: Double
    let distance: Double

    var body: some View {
        VStack(spacing: sp(6)) {
            HStack(spacing: 0) {
                SummaryStat(value: "\(avgHeartRate)", label: "AVG", unit: "BPM")
                    .frame(maxWidth: .infinity)
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1, height: sp(22))
                SummaryStat(value: "\(maxHeartRate)", label: "MAX", unit: "BPM")
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, sp(12))

            HStack(spacing: 0) {
                SummaryStat(value: "\(Int(calories))", label: "KCAL", unit: "")
                    .frame(maxWidth: .infinity)
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1, height: sp(22))
                SummaryStat(
                    value: String(format: "%.1f", distance / 1000),
                    label: "KM",
                    unit: ""
                )
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, sp(12))
        }
    }
}

struct SummaryStat: View {
    let value: String
    let label: String
    let unit: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value)
                .font(.system(size: sp(16), weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)

            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: sp(9), weight: .medium))
                    .foregroundColor(Color(hex: "B3B3B3"))
            }

            Spacer()

            Text(label)
                .font(.system(size: sp(10), weight: .regular))
                .foregroundColor(Color(hex: "B3B3B3"))
        }
    }
}

// MARK: - Zone Bar

struct ZoneBar: View {
    let avgZone: String

    private var zoneNumber: Int {
        switch avgZone {
        case "zone_1": return 1
        case "zone_2": return 2
        case "zone_3": return 3
        case "zone_4": return 4
        case "zone_5": return 5
        default: return 1
        }
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { zone in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(zone <= zoneNumber ? zoneColors["zone_\(zone)"] ?? zoneColorDefault : Color.white.opacity(0.12))
                }
            }
        }
        .frame(height: sp(6))
    }
}

// MARK: - Preview

#Preview {
    WorkoutSummaryView()
        .environmentObject(WorkoutManager.shared)
}
