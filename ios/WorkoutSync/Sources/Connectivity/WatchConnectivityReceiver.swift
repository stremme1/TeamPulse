import Foundation
import WatchConnectivity
import Combine

// MARK: - WatchConnectivityReceiver

/// Receives real-time workout data from Apple Watch via WatchConnectivity.
/// Works even when the iPhone app is not open (via background modes).
final class WatchConnectivityReceiver: NSObject, ObservableObject {
    static let shared = WatchConnectivityReceiver()

    // MARK: - Published

    @Published private(set) var isWatchConnected = false
    @Published private(set) var isWatchPaired = false
    @Published private(set) var activeSessionId: String?
    @Published private(set) var lastReceivedHeartRate: Int?
    @Published private(set) var lastReceivedDate: Date?

    // Latest data point
    @Published var latestDataPoint: ReceivedDataPoint?

    // Session state
    @Published var sessionState: SessionState = .idle {
        didSet {
            handleSessionStateChange()
        }
    }

    enum SessionState: Equatable {
        case idle
        case active(sessionId: String, athleteId: String)
        case paused
    }

    // MARK: - Private

    private var session: WCSession?
    private let offlineQueue = OfflineQueueManager.shared
    private let backendSync = BackendSyncService.shared
    private var debounceTimer: Timer?

    private override init() {
        super.init()
        setupSession()
    }

    // MARK: - Session Setup

    private func setupSession() {
        guard WCSession.isSupported() else {
            print("WCSession not supported on iPhone")
            return
        }

        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }

    // MARK: - Data Handling

    private func handleDataPoint(_ dataPoint: ReceivedDataPoint) {
        latestDataPoint = dataPoint
        lastReceivedHeartRate = dataPoint.heartRate
        lastReceivedDate = Date()

        // Debounce backend sends (batch rapid updates)
        debounceBackendSend(dataPoint)
    }

    private func debounceBackendSend(_ dataPoint: ReceivedDataPoint) {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.sendToBackend(dataPoint)
        }
    }

    private func sendToBackend(_ dataPoint: ReceivedDataPoint) {
        // Send via WebSocket (primary) or HTTP (fallback)
        backendSync.sendHeartRateData(
            athleteId: dataPoint.athleteId,
            sessionId: dataPoint.sessionId,
            heartRate: dataPoint.heartRate,
            zone: dataPoint.zone,
            calories: dataPoint.calories,
            distance: dataPoint.distance
        )
    }

    private func handleSessionStateChange() {
        switch sessionState {
        case .idle:
            activeSessionId = nil
        case .active(let sessionId, _):
            activeSessionId = sessionId
        case .paused:
            break
        }
    }

    // MARK: - Send Commands to Watch

    func sendCommandToWatch(_ command: String) {
        guard let session = session, session.activationState == .activated else { return }

        let message: [String: Any] = [
            "type": "workout_command",
            "command": command,
            "timestamp": Date().timeIntervalSince1970
        ]

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                print("Failed to send command to Watch: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityReceiver: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            isWatchConnected = session.isReachable
            isWatchPaired = session.isPaired
        }

        if let error = error {
            print("WCSession activation error: \(error.localizedDescription)")
        } else {
            print("WCSession activated: \(activationState.rawValue), paired=\(session.isPaired), reachable=\(session.isReachable)")

            // Check if Watch already has an active session in application context
            if !session.applicationContext.isEmpty {
                print("WC: Found existing applicationContext from Watch: \(session.applicationContext)")
                handleMessage(session.applicationContext, isUserInfo: false)
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        print("WCSession did become inactive")
    }

    func sessionDidDeactivate(_ session: WCSession) {
        print("WCSession did deactivate")
        session.activate()
    }

    // ── Receive Data ────────────────────────────────────────────────────────

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleMessage(message, isUserInfo: false)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handleMessage(message, isUserInfo: false)

        // Handle specific message types
        if let type = message["type"] as? String, type == "ping" {
            replyHandler(["status": "pong", "timestamp": Date().timeIntervalSince1970])
        } else {
            replyHandler(["status": "ok"])
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handleMessage(userInfo, isUserInfo: true)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        print("WC: Received applicationContext update: \(applicationContext)")
        handleMessage(applicationContext, isUserInfo: false)
    }

    private func handleMessage(_ message: [String: Any], isUserInfo: Bool) {
        guard let type = message["type"] as? String else {
            print("Received message without type: \(message)")
            return
        }

        print("WC iPhone received: \(type)")

        Task { @MainActor in
            switch type {
            case "session_started":
                let sessionId = message["session_id"] as? String ?? ""
                let athleteId = message["athlete_id"] as? String ?? ""
                let workoutType = message["workout_type"] as? String ?? "running"

                self.sessionState = .active(sessionId: sessionId, athleteId: athleteId)
                self.activeSessionId = sessionId

                print("Session started from Watch: \(sessionId), type: \(workoutType)")

            case "heart_rate_data":
                let dataPoint = ReceivedDataPoint(
                    athleteId: message["athlete_id"] as? String ?? "",
                    sessionId: message["session_id"] as? String ?? "",
                    timestamp: message["timestamp"] as? String ?? "",
                    heartRate: message["heart_rate"] as? Int ?? 0,
                    zone: message["zone"] as? String ?? "zone_1",
                    calories: message["calories"] as? Double ?? 0,
                    distance: message["distance"] as? Double ?? 0,
                    deviceStatus: message["device_status"] as? String ?? "watch"
                )
                self.handleDataPoint(dataPoint)

            case "workout_paused":
                self.sessionState = .paused

            case "workout_resumed":
                if let sessionId = self.activeSessionId,
                   let athleteId = message["athlete_id"] as? String {
                    self.sessionState = .active(sessionId: sessionId, athleteId: athleteId)
                }

            case "workout_ended":
                let sessionId = message["session_id"] as? String ?? ""
                let athleteId = message["athlete_id"] as? String ?? ""
                let duration = message["duration_seconds"] as? Int ?? 0
                let calories = message["total_calories"] as? Double ?? 0
                let distance = message["total_distance"] as? Double ?? 0

                print("Workout ended from Watch: \(sessionId), duration: \(duration)s")

                // Sync to backend
                self.backendSync.endSession(
                    athleteId: athleteId,
                    sessionId: sessionId,
                    durationSeconds: duration,
                    totalCalories: calories,
                    totalDistance: distance
                )

                // Sync recovery metrics
                await self.syncRecoveryMetrics(athleteId: athleteId, sessionId: sessionId)

                self.sessionState = .idle

            default:
                print("Unknown message type: \(type)")
            }
        }
    }

    // MARK: - Reachability

    func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isWatchConnected = session.isReachable
        }

        if session.isReachable {
            print("Watch is now reachable")
            // Flush any pending data
            offlineQueue.flushToBackend()
        }
    }

    // MARK: - Recovery Sync

    private func syncRecoveryMetrics(athleteId: String, sessionId: String) async {
        let hkManager = HealthKitManager.shared
        await hkManager.syncRecoveryMetrics(
            athleteId: athleteId,
            sessionId: sessionId,
            for: Date()
        )
    }
}

// MARK: - Received Data Point

struct ReceivedDataPoint: Codable {
    let athleteId: String
    let sessionId: String
    let timestamp: String
    let heartRate: Int
    let zone: String
    let calories: Double
    let distance: Double
    let deviceStatus: String
}
