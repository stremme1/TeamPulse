import SwiftUI

// MARK: - Workout Summary View

struct WorkoutSummaryView: View {
    @EnvironmentObject var workoutManager: WorkoutManager

    var body: some View {
        VStack(spacing: 0) {
            // Workout type
            Text(workoutManager.selectedWorkoutType.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.top, 6)

            Spacer()

            // Duration — dominant
            VStack(spacing: 4) {
                Text(formatElapsed(workoutManager.elapsedSeconds))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.primary)
                Text("DURATION")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Stats row — avg HR, max HR
            HStack(spacing: 0) {
                SummaryStat(value: "\(workoutManager.averageHeartRate)", label: "AVG", unit: "BPM")
                Rectangle().fill(Color.gray.opacity(0.15)).frame(width: 1, height: 32)
                SummaryStat(value: "\(workoutManager.maxHeartRate)", label: "MAX", unit: "BPM")
            }
            .padding(.horizontal, 12)

            Spacer()

            // Secondary stats — kcal, distance
            HStack(spacing: 0) {
                SummaryStat(value: "\(Int(workoutManager.activeCalories))", label: "KCAL", unit: "")
                Rectangle().fill(Color.gray.opacity(0.15)).frame(width: 1, height: 32)
                SummaryStat(
                    value: String(format: "%.1f", workoutManager.distance / 1000),
                    label: "KM",
                    unit: ""
                )
            }
            .padding(.horizontal, 12)

            Spacer()

            // Zone bar — thin, minimal
            VStack(spacing: 4) {
                Text("ZONES")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary)

                ZoneBar()
                    .frame(height: 8)
            }
            .padding(.horizontal, 16)

            Spacer()

            // Done button
            Button {
                // Reset handled by WorkoutManager state change
            } label: {
                Text("Done")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(Color.white)
                    .cornerRadius(18)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
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

// MARK: - Summary Stat

struct SummaryStat: View {
    let value: String
    let label: String
    let unit: String

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.primary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Zone Bar

struct ZoneBar: View {
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                Rectangle().fill(Color(hex: "5B8DFF")).frame(width: geo.size.width * 0.15)
                Rectangle().fill(Color(hex: "4ADE80")).frame(width: geo.size.width * 0.30)
                Rectangle().fill(Color(hex: "FACC15")).frame(width: geo.size.width * 0.30)
                Rectangle().fill(Color(hex: "FB923C")).frame(width: geo.size.width * 0.15)
                Rectangle().fill(Color(hex: "F87171")).frame(width: geo.size.width * 0.10)
            }
            .cornerRadius(4)
        }
    }
}

// MARK: - Preview

#Preview {
    WorkoutSummaryView()
        .environmentObject(WorkoutManager.shared)
}
