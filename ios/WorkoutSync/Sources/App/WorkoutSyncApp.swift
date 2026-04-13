import SwiftUI

@main
struct WorkoutSyncApp: App {
    @StateObject private var healthKitManager = HealthKitManager.shared
    @StateObject private var connectivityReceiver = WatchConnectivityReceiver.shared
    @StateObject private var backendSync = BackendSyncService.shared
    @StateObject private var offlineQueue = OfflineQueueManager.shared

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            if !hasCompletedOnboarding {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .environmentObject(healthKitManager)
            } else {
                ContentView()
                    .environmentObject(healthKitManager)
                    .environmentObject(connectivityReceiver)
                    .environmentObject(backendSync)
                    .environmentObject(offlineQueue)
            }
        }
    }
}
