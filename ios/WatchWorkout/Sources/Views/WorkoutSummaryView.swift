import SwiftUI
import WatchKit

// MARK: - Design System

private var scale: CGFloat {
    let w = WKInterfaceDevice.current().screenBounds.width
    return w / 198.0
}

private func sp(_ pts: CGFloat) -> CGFloat { pts * scale }

// MARK: - Ring Colors

private let ringMove = Color(hex: "FF3B30")
private let ringExercise = Color(hex: "32D74B")
private let ringStand = Color(hex: "0A84FF")

// MARK: - Workout Summary View

struct WorkoutSummaryView: View {
    @EnvironmentObject var workoutManager: WorkoutManager

    var body: some View {
        VStack(spacing: 0) {
            // Top padding
            Spacer().frame(height: sp(8))

            // Workout type label
            Text(workoutManager.selectedWorkoutType.displayName.uppercased())
                .font(.system(size: sp(10), weight: .medium))
                .foregroundColor(Color(hex: "B3B3B3"))
                .tracking(1.0)

            // Spacer
            Spacer().frame(height: sp(4))

            // Duration — primary metric (large)
            VStack(spacing: 2) {
                Text(formatElapsed(workoutManager.elapsedSeconds))
                    .font(.system(size: sp(42), weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)

                Text("DURATION")
                    .font(.system(size: sp(9), weight: .medium))
                    .foregroundColor(Color(hex: "B3B3B3"))
            }

            Spacer().frame(height: sp(10))

            // Activity Rings — centered, filled
            SummaryRingsView(
                moveProgress: 0.85,
                exerciseProgress: 0.6,
                standProgress: 0.45
            )
            .frame(width: sp(130), height: sp(130))

            Spacer().frame(height: sp(12))

            // Secondary stats
            SummaryStatsGrid(
                avgHeartRate: workoutManager.averageHeartRate,
                maxHeartRate: workoutManager.maxHeartRate,
                calories: workoutManager.activeCalories,
                distance: workoutManager.distance
            )

            Spacer()

            // Zone bar
            ZoneBar()
                .frame(height: sp(8))
                .padding(.horizontal, sp(16))

            Spacer().frame(height: sp(8))

            // Done button
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
            .padding(.horizontal, sp(16))
            .padding(.bottom, sp(8))
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

// MARK: - Summary Rings

struct SummaryRingsView: View {
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
                .trim(from: 0, to: moveProgress)
                .stroke(ringMove, style: StrokeStyle(lineWidth: ringStroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: outerRadius * 2, height: outerRadius * 2)

            Circle()
                .trim(from: 0, to: exerciseProgress)
                .stroke(ringExercise, style: StrokeStyle(lineWidth: ringStroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: middleRadius * 2, height: middleRadius * 2)

            Circle()
                .trim(from: 0, to: standProgress)
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
                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: sp(24))
                SummaryStat(value: "\(maxHeartRate)", label: "MAX", unit: "BPM")
            }
            .padding(.horizontal, sp(16))

            HStack(spacing: 0) {
                SummaryStat(value: "\(Int(calories))", label: "KCAL", unit: "")
                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: sp(24))
                SummaryStat(
                    value: String(format: "%.1f", distance / 1000),
                    label: "KM",
                    unit: ""
                )
            }
            .padding(.horizontal, sp(16))
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
                .font(.system(size: sp(17), weight: .semibold, design: .rounded))
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
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Zone Bar

struct ZoneBar: View {
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                Rectangle().fill(Color(hex: "5B8DFF")).cornerRadius(3)
                Rectangle().fill(Color(hex: "4ADE80")).cornerRadius(3)
                Rectangle().fill(Color(hex: "FACC15")).cornerRadius(3)
                Rectangle().fill(Color(hex: "FB923C")).cornerRadius(3)
                Rectangle().fill(Color(hex: "F87171")).cornerRadius(3)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    WorkoutSummaryView()
        .environmentObject(WorkoutManager.shared)
}
