import SwiftUI

// MARK: - Workout Live View

struct WorkoutLiveView: View {
    @EnvironmentObject var workoutManager: WorkoutManager

    var body: some View {
        VStack(spacing: 0) {
            // Header: workout type + elapsed
            HStack {
                Text(workoutManager.selectedWorkoutType.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatElapsed(workoutManager.elapsedSeconds))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)

            Spacer()

            // Zone ring + HR
            ZStack {
                // Zone ring
                Circle()
                    .trim(from: 0, to: zoneProgress)
                    .stroke(zoneColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 100, height: 100)

                // HR readout
                VStack(spacing: 0) {
                    Text("\(workoutManager.currentHeartRate)")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(zoneColor)
                    Text("BPM")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            // Zone badge
            HStack(spacing: 4) {
                Circle()
                    .fill(zoneColor)
                    .frame(width: 5, height: 5)
                Text(zoneName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(zoneColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(zoneColor.opacity(0.12))
            .cornerRadius(8)
            .padding(.top, 6)

            Spacer()

            // Stats row
            HStack(spacing: 0) {
                MetricPill(value: formatCalories(workoutManager.activeCalories), label: "KCAL", color: .orange)
                Rectangle().fill(Color.gray.opacity(0.15)).frame(width: 1, height: 28)
                MetricPill(value: formatDistance(workoutManager.distance), label: "KM", color: .green)
                Rectangle().fill(Color.gray.opacity(0.15)).frame(width: 1, height: 28)
                MetricPill(value: "\(workoutManager.averageHeartRate)", label: "AVG", color: .pink)
            }
            .padding(.horizontal, 10)

            Spacer()

            // Controls
            HStack(spacing: 10) {
                // Pause / Resume — custom geometric
                Button {
                    if workoutManager.workoutState == .running {
                        workoutManager.pauseWorkout()
                    } else {
                        workoutManager.resumeWorkout()
                    }
                } label: {
                    PausePlayIcon(isPlaying: workoutManager.workoutState == .running)
                        .frame(width: 56, height: 56)
                        .foregroundColor(.white)
                        .background(Color.gray.opacity(0.3))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // End — custom X
                Button {
                    Task {
                        try? await workoutManager.endWorkout()
                    }
                } label: {
                    EndWorkoutIcon()
                        .frame(width: 56, height: 56)
                        .foregroundColor(.white)
                        .background(Color.red)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Zone

    private var zoneColor: Color {
        switch workoutManager.currentZone {
        case "zone_1": return Color(hex: "5B8DFF")
        case "zone_2": return Color(hex: "4ADE80")
        case "zone_3": return Color(hex: "FACC15")
        case "zone_4": return Color(hex: "FB923C")
        case "zone_5": return Color(hex: "F87171")
        default: return .gray
        }
    }

    private var zoneName: String {
        switch workoutManager.currentZone {
        case "zone_1": return "RECOVERY"
        case "zone_2": return "AEROBIC"
        case "zone_3": return "TEMPO"
        case "zone_4": return "THRESHOLD"
        case "zone_5": return "VO2 MAX"
        default: return "—"
        }
    }

    private var zoneProgress: CGFloat {
        let hr = workoutManager.currentHeartRate
        // Map 60–200 bpm to 0–1
        return CGFloat(max(0, min(1, Double(hr - 60) / 140.0)))
    }

    // MARK: - Formatting

    private func formatElapsed(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    private func formatCalories(_ calories: Double) -> String {
        if calories >= 1000 {
            return String(format: "%.1fk", calories / 1000)
        }
        return "\(Int(calories))"
    }

    private func formatDistance(_ meters: Double) -> String {
        String(format: "%.2f", meters / 1000)
    }
}

// MARK: - Metric Pill

struct MetricPill: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.primary)
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Custom Control Icons (geometric — no SF Symbols)

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
                    // Two vertical bars (pause)
                    let bw: CGFloat = w * 0.12
                    let bh: CGFloat = h * 0.38
                    let gap: CGFloat = w * 0.10
                    path.addRect(CGRect(x: cx - gap - bw, y: cy - bh / 2, width: bw, height: bh))
                    path.addRect(CGRect(x: cx + gap, y: cy - bh / 2, width: bw, height: bh))
                } else {
                    // Play triangle
                    let size: CGFloat = min(w, h) * 0.36
                    let tx = cx - size * 0.15
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
            let s = min(w, h) * 0.30

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
