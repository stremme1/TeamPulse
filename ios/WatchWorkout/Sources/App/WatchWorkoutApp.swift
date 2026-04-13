import SwiftUI

@main
struct WatchWorkoutApp: App {
    @StateObject private var workoutManager = WorkoutManager.shared
    @StateObject private var connectivityManager = WatchConnectivityManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(workoutManager)
                .environmentObject(connectivityManager)
        }
    }
}
