import SwiftUI

// MARK: - Onboarding View

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject var healthKitManager: HealthKitManager

    @State private var isRequestingAuthorization = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: { AnyView(HeartRateOnboardIcon()) },
            title: "Real-Time Heart Rate",
            description: "Stream live heart rate from your Watch during workouts with sub-second latency."
        ),
        OnboardingPage(
            icon: { AnyView(SyncOnboardIcon()) },
            title: "Automatic Sync",
            description: "Data syncs automatically in the background — no app interaction needed."
        ),
        OnboardingPage(
            icon: { AnyView(AnalyticsOnboardIcon()) },
            title: "Recovery Analytics",
            description: "Post-workout sync of sleep, HRV, and readiness scores from Apple Health."
        ),
        OnboardingPage(
            icon: { AnyView(PrivacyOnboardIcon()) },
            title: "Privacy First",
            description: "Health data stays on-device, transmitted only as encrypted aggregates."
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Page content
            TabView(selection: $currentPage) {
                ForEach(0..<pages.count, id: \.self) { index in
                    OnboardingPageView(page: pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: currentPage)

            // Page indicators
            HStack(spacing: 6) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Capsule()
                        .fill(index == currentPage ? Color.primary : Color.gray.opacity(0.3))
                        .frame(width: index == currentPage ? 16 : 6, height: 6)
                        .animation(.easeInOut(duration: 0.2), value: currentPage)
                }
            }
            .padding(.vertical, 24)

            // Action buttons
            VStack(spacing: 12) {
                if currentPage == pages.count - 1 {
                    Button {
                        requestHealthKitAuthorization()
                    } label: {
                        Text("Allow Health Access")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentColor)
                            .cornerRadius(12)
                    }
                    .disabled(isRequestingAuthorization)

                    Button {
                        skipOnboarding()
                    } label: {
                        Text("Skip")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Button {
                        withAnimation {
                            currentPage += 1
                        }
                    } label: {
                        Text("Continue")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentColor)
                            .cornerRadius(12)
                    }

                    Button {
                        skipOnboarding()
                    } label: {
                        Text("Skip")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .alert("Authorization Error", isPresented: $showError) {
            Button("OK") {}
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text(errorMessage)
        }
    }

    private func requestHealthKitAuthorization() {
        isRequestingAuthorization = true
        Task {
            do {
                try await healthKitManager.requestAuthorization()
                await MainActor.run {
                    hasCompletedOnboarding = true
                    isRequestingAuthorization = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isRequestingAuthorization = false
                }
            }
        }
    }

    private func skipOnboarding() {
        hasCompletedOnboarding = true
    }
}

// MARK: - Onboarding Page

struct OnboardingPage {
    let icon: () -> AnyView
    let title: String
    let description: String
}

struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            page.icon()
                .frame(width: 64, height: 64)
                .foregroundColor(.accentColor)

            Text(page.title)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(page.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
    }
}

// MARK: - Onboarding Icons (Custom geometric — no SF Symbols)

struct HeartRateOnboardIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                let cx = w / 2
                let top = h * 0.20
                let bot = h * 0.85
                let mid = h * 0.48

                // Start at bottom center
                path.move(to: CGPoint(x: cx, y: bot))
                // Up to middle
                path.addLine(to: CGPoint(x: cx - w * 0.22, y: mid + h * 0.08))
                // Peak 1
                path.addLine(to: CGPoint(x: cx - w * 0.22, y: mid - h * 0.12))
                // Valley
                path.addLine(to: CGPoint(x: cx - w * 0.04, y: mid))
                // Peak 2 (main)
                path.addLine(to: CGPoint(x: cx, y: mid - h * 0.22))
                // Valley 2
                path.addLine(to: CGPoint(x: cx + w * 0.08, y: mid))
                // Peak 3
                path.addLine(to: CGPoint(x: cx + w * 0.22, y: mid - h * 0.10))
                // End
                path.addLine(to: CGPoint(x: cx + w * 0.22, y: mid + h * 0.08))
                path.addLine(to: CGPoint(x: cx, y: bot))
            }
            .stroke(lineWidth: 2)
        }
    }
}

struct SyncOnboardIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let r = min(w, h) / 2 - 4
            let cx = w / 2
            let cy = h / 2

            Path { path in
                // Outer circle
                path.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
                // Inner arc
                path.addArc(
                    center: CGPoint(x: cx, y: cy),
                    radius: r * 0.45,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(180),
                    clockwise: false
                )
                // Arrows
                path.move(to: CGPoint(x: cx - r, y: cy - r * 0.1))
                path.addLine(to: CGPoint(x: cx - r, y: cy - r * 0.35))
                path.addLine(to: CGPoint(x: cx - r - 3, y: cy - r * 0.25))
                path.addLine(to: CGPoint(x: cx - r + 3, y: cy - r * 0.25))
                path.addLine(to: CGPoint(x: cx - r, y: cy - r * 0.35))
                path.closeSubpath()

                path.move(to: CGPoint(x: cx + r, y: cy + r * 0.1))
                path.addLine(to: CGPoint(x: cx + r, y: cy + r * 0.35))
                path.addLine(to: CGPoint(x: cx + r + 3, y: cy + r * 0.25))
                path.addLine(to: CGPoint(x: cx + r - 3, y: cy + r * 0.25))
                path.addLine(to: CGPoint(x: cx + r, y: cy + r * 0.35))
                path.closeSubpath()
            }
            .stroke(lineWidth: 2)
        }
    }
}

struct AnalyticsOnboardIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let pad = 6.0

            Path { path in
                // Baseline
                path.move(to: CGPoint(x: pad, y: h - pad))
                path.addLine(to: CGPoint(x: w - pad, y: h - pad))
                // Bar 1
                path.move(to: CGPoint(x: pad + 4, y: h - pad))
                path.addLine(to: CGPoint(x: pad + 4, y: h * 0.55))
                // Bar 2
                path.move(to: CGPoint(x: w / 2, y: h - pad))
                path.addLine(to: CGPoint(x: w / 2, y: h * 0.35))
                // Bar 3
                path.move(to: CGPoint(x: w - pad - 4, y: h - pad))
                path.addLine(to: CGPoint(x: w - pad - 4, y: h * 0.65))
                // Trend line
                path.move(to: CGPoint(x: pad + 4, y: h * 0.55))
                path.addLine(to: CGPoint(x: w / 2, y: h * 0.35))
                path.addLine(to: CGPoint(x: w - pad - 4, y: h * 0.65))
            }
            .stroke(lineWidth: 2)
        }
    }
}

struct PrivacyOnboardIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cx = w / 2
            let top = h * 0.20
            let bot = h * 0.85

            Path { path in
                // Shield shape
                path.move(to: CGPoint(x: cx, y: top))
                path.addLine(to: CGPoint(x: w - 8, y: h * 0.30))
                path.addLine(to: CGPoint(x: w - 8, y: h * 0.55))
                path.addQuadCurve(
                    to: CGPoint(x: cx, y: bot),
                    control: CGPoint(x: w * 0.70, y: h * 0.75)
                )
                path.addQuadCurve(
                    to: CGPoint(x: 8, y: h * 0.55),
                    control: CGPoint(x: w * 0.30, y: h * 0.75)
                )
                path.addLine(to: CGPoint(x: 8, y: h * 0.30))
                path.closeSubpath()

                // Checkmark inside
                path.move(to: CGPoint(x: cx - 8, y: h * 0.52))
                path.addLine(to: CGPoint(x: cx - 2, y: h * 0.62))
                path.addLine(to: CGPoint(x: cx + 10, y: h * 0.38))
            }
            .stroke(lineWidth: 2)
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
        .environmentObject(HealthKitManager.shared)
}
