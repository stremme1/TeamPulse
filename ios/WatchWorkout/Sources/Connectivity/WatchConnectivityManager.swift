import Foundation
import WatchConnectivity

// MARK: - WatchConnectivityManager

final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published private(set) var isReachable = false
    @Published private(set) var isPaired = false
    @Published private(set) var lastSyncDate: Date?

    private var session: WCSession?
    private var pendingMessages: [String: Any] = [:]
    private var messageQueue: [(key: String, message: [String: Any])] = []

    private override init() {
        super.init()
        setupSession()
    }

    // MARK: - Session Setup

    private func setupSession() {
        guard WCSession.isSupported() else {
            print("WCSession is not supported on this device")
            return
        }

        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }

    // MARK: - Session Started

    func sendSessionStarted(sessionId: String, athleteId: String, workoutType: String, startDate: Date) {
        let message: [String: Any] = [
            "type": "session_started",
            "session_id": sessionId,
            "athlete_id": athleteId,
            "workout_type": workoutType,
            "start_date": startDate.ISO8601Format(),
            "timestamp": Date().timeIntervalSince1970
        ]
        send(message)

        // Also update application context so iPhone gets it even when not reachable
        updateApplicationContext(sessionId: sessionId, athleteId: athleteId, workoutType: workoutType)
    }

    // MARK: - Heart Rate Data

    func sendHeartRateData(sessionId: String, dataPoint: WorkoutDataPoint) {
        let message: [String: Any] = [
            "type": "heart_rate_data",
            "session_id": sessionId,
            "timestamp": dataPoint.timestamp,
            "heart_rate": dataPoint.heartRate,
            "zone": dataPoint.zone,
            "calories": dataPoint.calories,
            "distance": dataPoint.distance,
            "device_status": dataPoint.deviceStatus
        ]
        send(message)
    }

    // MARK: - Workout Control

    func sendWorkoutPaused(sessionId: String) {
        let message: [String: Any] = [
            "type": "workout_paused",
            "session_id": sessionId,
            "timestamp": Date().timeIntervalSince1970
        ]
        send(message)
    }

    func sendWorkoutResumed(sessionId: String) {
        let message: [String: Any] = [
            "type": "workout_resumed",
            "session_id": sessionId,
            "timestamp": Date().timeIntervalSince1970
        ]
        send(message)
    }

    func sendWorkoutEnded(sessionId: String, athleteId: String, endDate: Date, duration: Int, totalCalories: Double, totalDistance: Double) {
        let message: [String: Any] = [
            "type": "workout_ended",
            "session_id": sessionId,
            "athlete_id": athleteId,
            "end_date": endDate.ISO8601Format(),
            "duration_seconds": duration,
            "total_calories": totalCalories,
            "total_distance": totalDistance,
            "timestamp": Date().timeIntervalSince1970
        ]
        send(message)
    }

    // MARK: - Message Sending

    private func send(_ message: [String: Any]) {
        guard let session = session, session.activationState == .activated else {
            queueMessage(message)
            return
        }

        if session.isReachable {
            // Use sendMessage for immediate delivery (when iPhone app is open)
            session.sendMessage(message, replyHandler: { [weak self] reply in
                self?.lastSyncDate = Date()
                print("WC sendMessage reply: \(reply)")
            }, errorHandler: { error in
                print("WC sendMessage error: \(error.localizedDescription)")
                self.queueMessage(message)
            })
        } else {
            // Use transferUserInfo for guaranteed delivery (works even when iPhone app is closed)
            session.transferUserInfo(message)
            print("WC: Using transferUserInfo (iPhone not reachable)")
        }
    }

    // MARK: - Message Queueing

    private func queueMessage(_ message: [String: Any]) {
        let key = message["type"] as? String ?? "unknown"
        messageQueue.append((key: key, message: message))

        // Also store for later replay
        pendingMessages[key] = message

        // If it's heart rate data, just keep the latest one
        if key == "heart_rate_data" {
            pendingMessages["latest_heart_rate"] = message
        }
    }

    // MARK: - Flush Queue

    func flushQueue() {
        guard let session = session, session.activationState == .activated else { return }

        for (_, message) in messageQueue {
            if session.isReachable {
                session.sendMessage(message, replyHandler: nil) { error in
                    print("WC flush error: \(error.localizedDescription)")
                }
            }
        }
        messageQueue.removeAll()
        pendingMessages.removeAll()
    }

    // MARK: - Context Update (for complications / glance)

    func updateApplicationContext(sessionId: String, athleteId: String, workoutType: String) {
        guard let session = session, session.activationState == .activated else { return }

        let context: [String: Any] = [
            "type": "session_started",
            "session_id": sessionId,
            "athlete_id": athleteId,
            "workout_type": workoutType,
            "timestamp": Date().timeIntervalSince1970
        ]
        do {
            try session.updateApplicationContext(context)
            print("WC: Updated applicationContext with session_id=\(sessionId)")
        } catch {
            print("WC updateApplicationContext error: \(error.localizedDescription)")
        }
    }

    func updateComplicationContext(sessionId: String, athleteId: String, workoutType: String, heartRate: Int, elapsed: Int) {
        guard let session = session, session.activationState == .activated else { return }

        let context: [String: Any] = [
            "type": "live_workout",
            "session_id": sessionId,
            "athlete_id": athleteId,
            "workout_type": workoutType,
            "heart_rate": heartRate,
            "elapsed_seconds": elapsed,
            "timestamp": Date().timeIntervalSince1970
        ]
        do {
            try session.updateApplicationContext(context)
        } catch {
            print("WC updateComplicationContext error: \(error.localizedDescription)")
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            isReachable = session.isReachable
            // isPaired is unavailable on watchOS; treat as paired when session activates.
            isPaired = true
        }

        if let error = error {
            print("WCSession activation error: \(error.localizedDescription)")
            return
        }

        print("WCSession activated: state=\(activationState.rawValue), reachable=\(session.isReachable)")

        // Flush any queued messages after activation
        if activationState == .activated {
            flushQueue()
        }
    }

    // Note: sessionDidBecomeInactive / sessionDidDeactivate are iOS-only; omit on watchOS.

    // Receive messages from iPhone
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        print("WC received message: \(message)")
        handleReceivedMessage(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        print("WC received message with reply: \(message)")
        handleReceivedMessage(message)
        replyHandler(["status": "received"])
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        print("WC received userInfo: \(userInfo)")
        handleReceivedMessage(userInfo)
    }

    private func handleReceivedMessage(_ message: [String: Any]) {
        Task { @MainActor in
            guard let type = message["type"] as? String else { return }

            switch type {
            case "ping":
                // Respond with pong
                send(["type": "pong", "timestamp": Date().timeIntervalSince1970])

            case "request_sync":
                // iPhone is requesting a full sync — replay pending data
                flushQueue()

            case "workout_command":
                // Handle commands from iPhone (e.g., end workout)
                if let command = message["command"] as? String {
                    await handleWorkoutCommand(command, payload: message)
                }

            default:
                break
            }
        }
    }

    @MainActor
    private func handleWorkoutCommand(_ command: String, payload: [String: Any]) async {
        switch command {
        case "end_workout":
            try? await WorkoutManager.shared.endWorkout()
        case "pause_workout":
            WorkoutManager.shared.pauseWorkout()
        case "resume_workout":
            WorkoutManager.shared.resumeWorkout()
        default:
            break
        }
    }

    // Reachability
    func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isReachable = session.isReachable
        }

        if session.isReachable {
            print("iPhone is now reachable — flushing queue")
            flushQueue()
        }
    }
}
