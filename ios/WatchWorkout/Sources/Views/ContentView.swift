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

// MARK: - Content View

struct ContentView: View {
    @EnvironmentObject var workoutManager: WorkoutManager

    var body: some View {
        ZStack {
            switch workoutManager.workoutState {
            case .idle:
                WorkoutIdleView()

            case .countdown:
                CountdownOverlay {
                    Task {
                        try? await workoutManager.startWorkout(athleteId: "athlete-001")
                    }
                }

            case .running, .paused:
                WorkoutActiveContainer()

            case .ended:
                WorkoutSummaryView()
            }
        }
    }
}

// MARK: - Idle / Workout Selection View

struct WorkoutIdleView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    @State private var isRequestingAuth = false
    @State private var showAuthError = false
    @State private var authErrorMessage = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Top: Workout icon + name ────────────────────────────────
                VStack(spacing: sp(4)) {
                    // Workout type icon in a circle
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: sp(48), height: sp(48))
                        .overlay(
                            WorkoutIcon(type: workoutManager.selectedWorkoutType)
                                .frame(width: sp(28), height: sp(28))
                                .foregroundColor(.white)
                        )

                    // Workout name below icon
                    Text(workoutManager.selectedWorkoutType.displayName.uppercased())
                        .font(.system(size: sp(11), weight: .semibold))
                        .foregroundColor(.white)
                        .tracking(0.5)
                }
                .padding(.top, sp(10))

                Spacer()

                // ── Scrollable workout type grid ────────────────────────────
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                    ], spacing: sp(4)) {
                        ForEach(WorkoutType.allCases) { type in
                            WorkoutTypeCellSmall(
                                type: type,
                                isSelected: workoutManager.selectedWorkoutType == type,
                                action: {
                                    workoutManager.selectWorkoutType(type)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, sp(8))
                    .padding(.top, sp(6))
                }
                .frame(maxHeight: sp(100))

                Spacer()

                // ── Bottom bar ─────────────────────────────────────────────
                HStack {
                    // Music icon (left)
                    Image(systemName: "music.note")
                        .font(.system(size: sp(14)))
                        .foregroundColor(Color(hex: "B3B3B3"))
                        .frame(width: sp(30))

                    Spacer()

                    // Start button (center)
                    Button {
                        startWorkout()
                    } label: {
                        HStack(spacing: sp(4)) {
                            PlayIcon()
                                .frame(width: sp(10), height: sp(10))
                                .foregroundColor(.black)
                            Text("Start")
                                .font(.system(size: sp(13), weight: .semibold))
                                .foregroundColor(.black)
                        }
                        .frame(width: sp(80), height: sp(32))
                        .background(Color.white)
                        .cornerRadius(sp(16))
                    }
                    .buttonStyle(.plain)
                    .disabled(isRequestingAuth)

                    Spacer()

                    // Notifications icon (right)
                    Image(systemName: "bell.fill")
                        .font(.system(size: sp(14)))
                        .foregroundColor(Color(hex: "B3B3B3"))
                        .frame(width: sp(30))
                }
                .padding(.horizontal, sp(12))
                .padding(.bottom, sp(8))
            }
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
                await MainActor.run {
                    workoutManager.startCountdown(athleteId: "athlete-001")
                }
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

// MARK: - Small Workout Type Cell

struct WorkoutTypeCellSmall: View {
    let type: WorkoutType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                WorkoutIcon(type: type)
                    .frame(width: sp(20), height: sp(20))
                    .foregroundColor(isSelected ? .white : Color(hex: "B3B3B3"))

                Text(type.displayName)
                    .font(.system(size: sp(7), weight: .medium))
                    .foregroundColor(isSelected ? .white : Color(hex: "B3B3B3"))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: sp(36))
            .background(
                RoundedRectangle(cornerRadius: sp(6))
                    .fill(isSelected ? Color.white.opacity(0.18) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: sp(6))
                    .stroke(
                        isSelected ? Color.white.opacity(0.35) : Color.gray.opacity(0.12),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Countdown Overlay

struct CountdownOverlay: View {
    let onComplete: () -> Void

    @State private var countdownValue: Int = 3
    @State private var ringProgress: CGFloat = 0.0
    @State private var numberOpacity: CGFloat = 1.0
    @State private var scale: CGFloat = 0.8

    private let ringRadius: CGFloat = 52
    private let ringStroke: CGFloat = 6

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Ring background
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: ringStroke)
                .frame(width: ringRadius * 2, height: ringRadius * 2)

            // Animated ring progress
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: ringStroke, lineCap: .round)
                )
                .frame(width: ringRadius * 2, height: ringRadius * 2)
                .rotationEffect(.degrees(-90))

            // Countdown number
            Text("\(countdownValue)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .opacity(numberOpacity)
                .scaleEffect(scale)
        }
        .onAppear {
            startCountdown()
        }
        .onChange(of: countdownValue) { _, newValue in
            if newValue > 0 {
                animateNumber()
            }
        }
    }

    private func startCountdown() {
        // Use a timer to drive the countdown
        var elapsed: Double = 0
        let startTime = Date()

        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { timer in
            elapsed = Date().timeIntervalSince(startTime)

            // Ring progress: 0 → 1 over 1 second per count
            let countSeconds = 3 - countdownValue
            let fraction = elapsed - Double(countSeconds)
            ringProgress = CGFloat(min(1.0, fraction))

            if elapsed >= Double(4 - countdownValue) {
                if countdownValue > 1 {
                    countdownValue -= 1
                    ringProgress = 0
                } else {
                    timer.invalidate()
                    // Brief flash then complete
                    withAnimation(.easeOut(duration: 0.15)) {
                        numberOpacity = 0
                        scale = 1.2
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        onComplete()
                    }
                }
            }
        }
    }

    private func animateNumber() {
        withAnimation(.easeOut(duration: 0.15)) {
            numberOpacity = 0
            scale = 1.15
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.15)) {
                numberOpacity = 1
                scale = 1.0
            }
        }
    }
}

// MARK: - Play Icon (geometric)

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

// MARK: - Workout Icon (Custom geometric shapes)

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
                path.addEllipse(in: CGRect(x: cx + 4, y: cy - 8, width: 4, height: 4))
                path.move(to: CGPoint(x: cx + 6, y: cy - 4))
                path.addLine(to: CGPoint(x: cx + 2, y: cy + 2))
                path.move(to: CGPoint(x: cx + 6, y: cy - 2))
                path.addLine(to: CGPoint(x: cx + 10, y: cy + 1))
                path.move(to: CGPoint(x: cx + 2, y: cy + 2))
                path.addLine(to: CGPoint(x: cx, y: cy + 8))
                path.move(to: CGPoint(x: cx + 2, y: cy + 2))
                path.addLine(to: CGPoint(x: cx + 6, y: cy + 8))
            }
            .stroke(lineWidth: 1.5)
        }
    }
}

struct CyclingIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                path.addEllipse(in: CGRect(x: 2, y: h - 10, width: 8, height: 8))
                path.addEllipse(in: CGRect(x: w - 10, y: h - 10, width: 8, height: 8))
                path.move(to: CGPoint(x: 6, y: h - 6))
                path.addLine(to: CGPoint(x: w / 2, y: h / 2 - 2))
                path.addLine(to: CGPoint(x: w - 6, y: h - 6))
                path.move(to: CGPoint(x: w / 2, y: h / 2 - 2))
                path.addLine(to: CGPoint(x: w / 2 - 2, y: h / 2 - 8))
                path.addLine(to: CGPoint(x: w - 6, y: h - 6))
            }
            .stroke(lineWidth: 1.5)
        }
    }
}

struct StrengthIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                path.addRect(CGRect(x: 2, y: h / 2 - 3, width: 3, height: 6))
                path.move(to: CGPoint(x: 5, y: h / 2))
                path.addLine(to: CGPoint(x: w - 5, y: h / 2))
                path.addRect(CGRect(x: w - 5, y: h / 2 - 3, width: 3, height: 6))
            }
            .stroke(lineWidth: 1.5)
        }
    }
}

struct HIITIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                path.move(to: CGPoint(x: w / 2, y: h - 2))
                path.addLine(to: CGPoint(x: w / 2, y: 2))
                path.move(to: CGPoint(x: w / 2 - 4, y: 6))
                path.addLine(to: CGPoint(x: w / 2, y: 2))
                path.addLine(to: CGPoint(x: w / 2 + 4, y: 6))
                path.move(to: CGPoint(x: 4, y: 4))
                path.addLine(to: CGPoint(x: 4, y: h - 4))
                path.move(to: CGPoint(x: 1, y: h - 8))
                path.addLine(to: CGPoint(x: 4, y: h - 4))
                path.addLine(to: CGPoint(x: 7, y: h - 8))
            }
            .stroke(lineWidth: 1.5)
        }
    }
}

struct YogaIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                path.addEllipse(in: CGRect(x: w / 2 - 2, y: 2, width: 4, height: 4))
                path.move(to: CGPoint(x: 2, y: h / 2 - 2))
                path.addLine(to: CGPoint(x: w - 2, y: h / 2 - 2))
                path.move(to: CGPoint(x: w / 2, y: 6))
                path.addLine(to: CGPoint(x: w / 2, y: h / 2 + 4))
                path.move(to: CGPoint(x: w / 2, y: h / 2 + 4))
                path.addLine(to: CGPoint(x: 4, y: h - 2))
                path.move(to: CGPoint(x: w / 2, y: h / 2 + 4))
                path.addLine(to: CGPoint(x: w - 4, y: h - 2))
            }
            .stroke(lineWidth: 1.5)
        }
    }
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
            .stroke(lineWidth: 1.5)
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(WorkoutManager.shared)
}
