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

// MARK: - Active Workout Container (Swipeable Pages)

struct WorkoutActiveContainer: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    @State private var currentPage: Int = 0

    var body: some View {
        TabView(selection: $currentPage) {
            WorkoutSimpleView()
                .tag(0)

            WorkoutDetailView()
                .tag(1)

            WorkoutControlsView(onReturnToPage0: {
                withAnimation {
                    currentPage = 0
                }
            })
            .tag(2)
        }
        .tabViewStyle(.verticalPage)
        // `.pageBackgroundView` is not available on watchOS `IndexViewStyle`; dots still show with default page index style.
        .indexViewStyle(.page)
    }
}

// MARK: - Page 0: Simple View (Home)

struct WorkoutSimpleView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    @State private var displayedHeartRate: Int = 0

    private var zoneColor: Color {
        zoneColors[workoutManager.currentZone] ?? .gray
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top-right: workout type icon
                HStack {
                    Spacer()
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: sp(28), height: sp(28))
                        .overlay(
                            WorkoutIcon(type: workoutManager.selectedWorkoutType)
                                .frame(width: sp(18), height: sp(18))
                                .foregroundColor(.white)
                        )
                }
                .padding(.top, sp(8))
                .padding(.trailing, sp(10))

                Spacer()

                // ── Elapsed Timer ───────────────────────────────────────────
                Text(formatElapsed(workoutManager.elapsedSeconds))
                    .font(.system(size: sp(38), weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)

                Spacer().frame(height: sp(10))

                // ── Active Cal | Total Cal ──────────────────────────────────
                VStack(spacing: sp(4)) {
                    CalorieRow(label: "ACTIVE", value: Int(workoutManager.activeCalories))
                    CalorieRow(label: "TOTAL CAL", value: Int(workoutManager.activeCalories))
                }

                Spacer().frame(height: sp(12))

                // ── Heart Rate ─────────────────────────────────────────────
                HStack(spacing: sp(6)) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: sp(22)))
                        .foregroundColor(zoneColor)

                    Text("\(displayedHeartRate)")
                        .font(.system(size: sp(44), weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .contentTransition(.numericText())
                }

                Spacer()
            }
        }
        .onAppear {
            displayedHeartRate = workoutManager.currentHeartRate
        }
        .onChange(of: workoutManager.currentHeartRate) { oldValue, newValue in
            animateHeartRate(from: oldValue, to: newValue)
        }
    }

    private func animateHeartRate(from: Int, to: Int) {
        let start = from
        let end = to
        let duration: Double = 0.35
        let startTime = Date()

        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { timer in
            let elapsed = Date().timeIntervalSince(startTime)
            let t = min(elapsed / duration, 1.0)
            let eased = 1.0 - pow(1.0 - t, 3)

            displayedHeartRate = Int(Double(start) + Double(end - start) * eased)

            if t >= 1.0 {
                timer.invalidate()
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

struct CalorieRow: View {
    let label: String
    let value: Int

    var body: some View {
        HStack(spacing: sp(4)) {
            Text("\(value)")
                .font(.system(size: sp(18), weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)

            Text(label)
                .font(.system(size: sp(9), weight: .regular))
                .foregroundColor(Color(hex: "B3B3B3"))
        }
    }
}

// MARK: - Page 1: Detail View (Swipe Up)

struct WorkoutDetailView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    @State private var displayedHeartRate: Int = 0

    private var zoneColor: Color {
        zoneColors[workoutManager.currentZone] ?? .gray
    }

    private var moveProgress: CGFloat {
        CGFloat(workoutManager.activityRings?.moveProgress ?? 0)
    }

    private var exerciseProgress: CGFloat {
        CGFloat(workoutManager.activityRings?.exerciseProgress ?? 0)
    }

    private var standProgress: CGFloat {
        CGFloat(workoutManager.activityRings?.standProgress ?? 0)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            HStack(spacing: 0) {
                // ── Left: Activity Rings ───────────────────────────────────
                VStack(spacing: sp(8)) {
                    Spacer()

                    // Move ring
                    RingWithLabel(
                        progress: moveProgress,
                        color: ringMove,
                        label: "MOVE",
                        value: Int(workoutManager.activityRings?.moveCalories ?? workoutManager.activeCalories),
                        unit: "kcal"
                    )

                    // Exercise ring
                    RingWithLabel(
                        progress: exerciseProgress,
                        color: ringExercise,
                        label: "EXERCISE",
                        value: workoutManager.activityRings?.exerciseMinutes ?? (workoutManager.elapsedSeconds / 60),
                        unit: "min"
                    )

                    // Stand ring
                    RingWithLabel(
                        progress: standProgress,
                        color: ringStand,
                        label: "STAND",
                        value: workoutManager.activityRings?.standHours ?? (workoutManager.elapsedSeconds % 4),
                        unit: "hr"
                    )

                    Spacer()
                }
                .frame(width: sp(80))

                Spacer()

                // ── Right: Timer + HR ──────────────────────────────────────
                VStack(spacing: 0) {
                    // Large timer
                    Text(formatElapsed(workoutManager.elapsedSeconds))
                        .font(.system(size: sp(44), weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)

                    Spacer().frame(height: sp(16))

                    // HR + zone
                    VStack(spacing: sp(4)) {
                        HStack(spacing: sp(4)) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: sp(16)))
                                .foregroundColor(zoneColor)

                            Text("\(displayedHeartRate)")
                                .font(.system(size: sp(28), weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.white)
                        }

                        Text(zoneName)
                            .font(.system(size: sp(9), weight: .medium))
                            .foregroundColor(zoneColor)
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.trailing, sp(12))
            }
        }
        .onAppear {
            displayedHeartRate = workoutManager.currentHeartRate
        }
        .onChange(of: workoutManager.currentHeartRate) { oldValue, newValue in
            animateHeartRate(from: oldValue, to: newValue)
        }
    }

    private func animateHeartRate(from: Int, to: Int) {
        let start = from
        let end = to
        let duration: Double = 0.35
        let startTime = Date()

        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { timer in
            let elapsed = Date().timeIntervalSince(startTime)
            let t = min(elapsed / duration, 1.0)
            let eased = 1.0 - pow(1.0 - t, 3)
            displayedHeartRate = Int(Double(start) + Double(end - start) * eased)
            if t >= 1.0 { timer.invalidate() }
        }
    }

    private var zoneName: String {
        switch workoutManager.currentZone {
        case "zone_1": return "RECOVERY"
        case "zone_2": return "AEROBIC"
        case "zone_3": return "TEMPO"
        case "zone_4": return "THRESHOLD"
        case "zone_5": return "VO2 MAX"
        default: return "RECOVERY"
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

// MARK: - Ring With Label (Detail View)

struct RingWithLabel: View {
    let progress: CGFloat
    let color: Color
    let label: String
    let value: Int
    let unit: String

    private var radius: CGFloat { sp(20) }
    private var stroke: CGFloat { sp(5) }

    var body: some View {
        VStack(spacing: sp(2)) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: stroke)
                    .frame(width: radius * 2, height: radius * 2)

                Circle()
                    .trim(from: 0, to: max(0.001, progress))
                    .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .frame(width: radius * 2, height: radius * 2)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.8), value: progress)

                Text("\(value)")
                    .font(.system(size: sp(9), weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }

            Text(label)
                .font(.system(size: sp(7), weight: .medium))
                .foregroundColor(Color(hex: "B3B3B3"))
        }
    }
}

// MARK: - Page 2: Controls Panel (Swipe Left)

struct WorkoutControlsView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    let onReturnToPage0: () -> Void

    @State private var autoReturnTimer: Timer?
    @State private var lastInteractionDate: Date = Date()
    @State private var showConfirmation: Bool = false
    @State private var confirmationMessage: String = ""

    private let controls: [(id: String, icon: String, label: String)] = [
        ("end", "xmark", "End"),
        ("pause", "pause.fill", "Pause"),
        ("new", "plus", "New"),
        ("segment", "flag.fill", "Segment"),
        ("phone", "phone.badge.checkmark", "Stop Phone"),
        ("checkin", "hand.wave.fill", "Check-in"),
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Top: Workout type name ────────────────────────────────
                Text(workoutManager.selectedWorkoutType.displayName.uppercased())
                    .font(.system(size: sp(12), weight: .semibold))
                    .foregroundColor(.white)
                    .tracking(0.5)
                    .padding(.top, sp(8))

                // ── 2×3 Control Grid ──────────────────────────────────────
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                    ], spacing: sp(8)) {
                        ForEach(controls, id: \.id) { control in
                            ControlButton(
                                icon: control.icon,
                                label: control.label,
                                action: {
                                    handleControl(control.id)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, sp(8))
                    .padding(.top, sp(8))
                }

                Spacer()
            }
        }
        .onAppear {
            resetAutoReturnTimer()
        }
        .onDisappear {
            autoReturnTimer?.invalidate()
        }
        .alert(confirmationMessage, isPresented: $showConfirmation) {
            Button("OK") {}
        }
    }

    private func handleControl(_ id: String) {
        resetAutoReturnTimer()

        switch id {
        case "end":
            Task {
                try? await workoutManager.endWorkout()
            }
        case "pause":
            if workoutManager.workoutState == .running {
                workoutManager.pauseWorkout()
            } else {
                workoutManager.resumeWorkout()
            }
            onReturnToPage0()
        case "new", "segment":
            confirmationMessage = id == "new" ? "New workout started" : "Segment marked"
            showConfirmation = true
        case "phone":
            confirmationMessage = "Phone call notification sent"
            showConfirmation = true
        case "checkin":
            confirmationMessage = "Check-in sent"
            showConfirmation = true
        default:
            break
        }
    }

    private func resetAutoReturnTimer() {
        lastInteractionDate = Date()
        autoReturnTimer?.invalidate()
        autoReturnTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { _ in
            onReturnToPage0()
        }
    }
}

// MARK: - Control Button

struct ControlButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: sp(3)) {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: sp(36), height: sp(36))
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: sp(14)))
                            .foregroundColor(.white)
                    )

                Text(label)
                    .font(.system(size: sp(7), weight: .medium))
                    .foregroundColor(Color(hex: "B3B3B3"))
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Active Container") {
    WorkoutActiveContainer()
        .environmentObject(WorkoutManager.shared)
}
