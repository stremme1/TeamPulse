import SwiftUI

// MARK: - Content View

struct ContentView: View {
    @EnvironmentObject var workoutManager: WorkoutManager

    var body: some View {
        Group {
            switch workoutManager.workoutState {
            case .idle:
                WorkoutSelectionView()
            case .running, .paused:
                WorkoutLiveView()
            case .ended:
                WorkoutSummaryView()
            }
        }
    }
}

// MARK: - Workout Selection

struct WorkoutSelectionView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    @State private var isRequestingAuth = false
    @State private var showAuthError = false
    @State private var authErrorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: true) {
                // Header
                Text("Workout")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.top, 6)

                Spacer().frame(height: 8)

                // Workout type grid — 2 columns, minimal
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: 6) {
                    ForEach(WorkoutType.allCases) { type in
                        WorkoutTypeCell(
                            type: type,
                            isSelected: workoutManager.selectedWorkoutType == type,
                            action: {
                                workoutManager.selectWorkoutType(type)
                            }
                        )
                    }
                }
                .padding(.horizontal, 10)

                // Selected workout name
                Text(workoutManager.selectedWorkoutType.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.top, 6)
            }

            // Start button — fixed at bottom
            Button {
                startWorkout()
            } label: {
                HStack(spacing: 4) {
                    PlayIcon()
                        .frame(width: 10, height: 10)
                        .foregroundColor(.black)
                    Text("Start")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(Color.white)
                .cornerRadius(18)
            }
            .buttonStyle(.plain)
            .disabled(isRequestingAuth)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .alert("Authorization", isPresented: $showAuthError) {
            Button("OK") {}
        } message: {
            Text(authErrorMessage)
        }
    }

    private func startWorkout() {
        isRequestingAuth = true
        Task {
            do {
                try await workoutManager.requestAuthorization()
                try await workoutManager.startWorkout(athleteId: "athlete-001")
            } catch {
                await MainActor.run {
                    authErrorMessage = error.localizedDescription
                    showAuthError = true
                }
            }
            await MainActor.run {
                isRequestingAuth = false
            }
        }
    }
}

// MARK: - Play Icon (geometric — no SF Symbols)

struct PlayIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                let size = min(w, h)
                let tx = size * 0.15
                let ty = size * 0.10
                path.move(to: CGPoint(x: tx, y: ty))
                path.addLine(to: CGPoint(x: tx + size * 0.75, y: h / 2))
                path.addLine(to: CGPoint(x: tx, y: ty + size * 0.80))
                path.closeSubpath()
            }
        }
    }
}

// MARK: - Workout Type Cell

struct WorkoutTypeCell: View {
    let type: WorkoutType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                WorkoutIcon(type: type)
                    .frame(width: 24, height: 24)
                    .foregroundColor(isSelected ? .white : .secondary)
                Text(type.displayName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(isSelected ? .white : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.white.opacity(0.2) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.white.opacity(0.4) : Color.gray.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Workout Icon (Custom geometric shapes — no SF Symbols)

struct WorkoutIcon: View {
    let type: WorkoutType

    var body: some View {
        switch type {
        case .running:
            RunningIcon()
        case .cycling:
            CyclingIcon()
        case .functionalStrengthTraining:
            StrengthIcon()
        case .highIntensityIntervalTraining:
            HIITIcon()
        case .yoga:
            YogaIcon()
        default:
            GenericIcon()
        }
    }
}

// MARK: - Custom Icon Shapes

struct RunningIcon: View {
    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            let cy = geo.size.height / 2
            Path { path in
                // Head
                path.addEllipse(in: CGRect(x: cx + 4, y: cy - 8, width: 4, height: 4))
                // Body line
                path.move(to: CGPoint(x: cx + 6, y: cy - 4))
                path.addLine(to: CGPoint(x: cx + 2, y: cy + 2))
                // Arms
                path.move(to: CGPoint(x: cx + 6, y: cy - 2))
                path.addLine(to: CGPoint(x: cx + 10, y: cy + 1))
                // Legs
                path.move(to: CGPoint(x: cx + 2, y: cy + 2))
                path.addLine(to: CGPoint(x: cx, y: cy + 8))
                path.move(to: CGPoint(x: cx + 2, y: cy + 2))
                path.addLine(to: CGPoint(x: cx + 6, y: cy + 8))
            }
            .stroke(lineWidth: 1.2)
        }
    }
}

struct CyclingIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                // Rear wheel
                path.addEllipse(in: CGRect(x: 2, y: h - 10, width: 8, height: 8))
                // Front wheel
                path.addEllipse(in: CGRect(x: w - 10, y: h - 10, width: 8, height: 8))
                // Frame
                path.move(to: CGPoint(x: 6, y: h - 6))
                path.addLine(to: CGPoint(x: w / 2, y: cy(h)))
                path.addLine(to: CGPoint(x: w - 6, y: h - 6))
                path.move(to: CGPoint(x: w / 2, y: cy(h)))
                path.addLine(to: CGPoint(x: w / 2 - 2, y: cy(h) - 6))
                path.addLine(to: CGPoint(x: w - 6, y: h - 6))
            }
            .stroke(lineWidth: 1.2)
        }
    }

    private func cy(_ h: CGFloat) -> CGFloat { h / 2 - 2 }
}

struct StrengthIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                // Left dumbbell end
                path.addRect(CGRect(x: 2, y: h / 2 - 3, width: 3, height: 6))
                // Bar
                path.move(to: CGPoint(x: 5, y: h / 2))
                path.addLine(to: CGPoint(x: w - 5, y: h / 2))
                // Right dumbbell end
                path.addRect(CGRect(x: w - 5, y: h / 2 - 3, width: 3, height: 6))
            }
            .stroke(lineWidth: 1.2)
        }
    }
}

struct SwimmingIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                // Head
                path.addEllipse(in: CGRect(x: 2, y: h / 2 - 3, width: 6, height: 6))
                // Body
                path.move(to: CGPoint(x: 8, y: h / 2))
                path.addLine(to: CGPoint(x: w - 2, y: h / 2))
                // Arms (one up, one down)
                path.move(to: CGPoint(x: 14, y: h / 2))
                path.addLine(to: CGPoint(x: 18, y: h / 2 - 6))
                path.move(to: CGPoint(x: 14, y: h / 2))
                path.addLine(to: CGPoint(x: 18, y: h / 2 + 6))
                // Legs
                path.move(to: CGPoint(x: w - 2, y: h / 2))
                path.addLine(to: CGPoint(x: w - 2, y: h / 2 - 5))
                path.move(to: CGPoint(x: w - 2, y: h / 2))
                path.addLine(to: CGPoint(x: w - 2, y: h / 2 + 5))
            }
            .stroke(lineWidth: 1.2)
        }
    }
}

struct HIITIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                // Arrow up
                path.move(to: CGPoint(x: w / 2, y: h - 2))
                path.addLine(to: CGPoint(x: w / 2, y: 2))
                path.move(to: CGPoint(x: w / 2 - 4, y: 6))
                path.addLine(to: CGPoint(x: w / 2, y: 2))
                path.addLine(to: CGPoint(x: w / 2 + 4, y: 6))
                // Arrow down
                path.move(to: CGPoint(x: 4, y: 4))
                path.addLine(to: CGPoint(x: 4, y: h - 4))
                path.move(to: CGPoint(x: 1, y: h - 8))
                path.addLine(to: CGPoint(x: 4, y: h - 4))
                path.addLine(to: CGPoint(x: 7, y: h - 8))
            }
            .stroke(lineWidth: 1.2)
        }
    }
}

struct YogaIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                // Head
                path.addEllipse(in: CGRect(x: w / 2 - 2, y: 2, width: 4, height: 4))
                // Arms spread wide
                path.move(to: CGPoint(x: 2, y: cy(h) - 2))
                path.addLine(to: CGPoint(x: w - 2, y: cy(h) - 2))
                // Body
                path.move(to: CGPoint(x: w / 2, y: 6))
                path.addLine(to: CGPoint(x: w / 2, y: cy(h) + 4))
                // Legs spread
                path.move(to: CGPoint(x: w / 2, y: cy(h) + 4))
                path.addLine(to: CGPoint(x: 4, y: h - 2))
                path.move(to: CGPoint(x: w / 2, y: cy(h) + 4))
                path.addLine(to: CGPoint(x: w - 4, y: h - 2))
            }
            .stroke(lineWidth: 1.2)
        }
    }

    private func cy(_ h: CGFloat) -> CGFloat { h / 2 - 2 }
}

struct GenericIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                path.addEllipse(in: CGRect(x: 2, y: 2, width: w - 4, height: h - 4))
                path.move(to: CGPoint(x: 6, y: h / 2))
                path.addLine(to: CGPoint(x: w - 6, y: h / 2))
            }
            .stroke(lineWidth: 1.2)
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(WorkoutManager.shared)
}
