import Foundation
import Combine

// MARK: - BackendSyncService

/// Handles all communication with the workout backend server.
/// Supports both WebSocket (real-time) and HTTP (batch/retry) for reliability.
final class BackendSyncService: NSObject, ObservableObject {
    static let shared = BackendSyncService()

    // MARK: - Published

    @Published private(set) var isConnected = false
    @Published private(set) var connectionState: ConnectionState = .disconnected

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting(attempt: Int)
    }

    // MARK: - Configuration

    private let backendHost: String
    private let backendPort: Int
    private let httpBaseURL: URL?

    // MARK: - WebSocket

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var pingTimer: Timer?
    private var reconnectTimer: Timer?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 10

    // MARK: - Message Buffer

    private var pendingMessages: [URLSessionWebSocketTask.Message] = []
    private let messageQueue = DispatchQueue(label: "com.workoutsystem.backendqueue", qos: .utility)

    // MARK: - Offline Queue

    private let offlineQueue = OfflineQueueManager.shared

    // MARK: - Initialization

    private override init() {
        // In production, these would come from configuration
        self.backendHost = ProcessInfo.processInfo.environment["BACKEND_HOST"] ?? "localhost"
        self.backendPort = Int(ProcessInfo.processInfo.environment["BACKEND_PORT"] ?? "8000") ?? 8000
        self.httpBaseURL = URL(string: "http://\(backendHost):\(backendPort)")
        super.init()
    }

    // MARK: - WebSocket Connection

    @MainActor
    func connect(athleteId: String) {
        disconnect()

        connectionState = .connecting

        let wsURLString = "ws://\(backendHost):\(backendPort)/ws/\(athleteId)"
        guard let url = URL(string: wsURLString) else {
            print("BackendSync: Invalid WebSocket URL")
            return
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300

        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        webSocketTask = session?.webSocketTask(with: url)
        webSocketTask?.resume()

        isConnected = true
        reconnectAttempts = 0

        receiveWebSocketMessages()

        print("BackendSync: WebSocket connecting to \(wsURLString)")
    }

    func disconnect() {
        stopPingTimer()
        stopReconnectTimer()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil

        Task { @MainActor in
            isConnected = false
            connectionState = .disconnected
        }

        print("BackendSync: Disconnected")
    }

    // MARK: - WebSocket Send

    func subscribe(sessionId: String) {
        let message: [String: Any] = [
            "type": "subscribe",
            "session_id": sessionId
        ]
        sendWebSocketJSON(message)
    }

    func sendHeartRateData(
        athleteId: String,
        sessionId: String,
        heartRate: Int,
        zone: String,
        calories: Double,
        distance: Double
    ) {
        let zoneHR: [String: Bool] = [
            "zone_1": (0..<114).contains(heartRate),
            "zone_2": (114..<133).contains(heartRate),
            "zone_3": (133..<152).contains(heartRate),
            "zone_4": (152..<171).contains(heartRate),
            "zone_5": (171..<250).contains(heartRate),
        ]

        let computedZone = zoneHR.first { $0.value }?.key ?? zone

        let dataPoint: [String: Any] = [
            "athlete_id": athleteId,
            "session_id": sessionId,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "heart_rate": heartRate,
            "zone": computedZone,
            "calories": calories,
            "distance": distance,
            "device_status": "iphone_relay"
        ]

        // Send via WebSocket
        sendWebSocketJSON(dataPoint)
    }

    func endSession(
        athleteId: String,
        sessionId: String,
        durationSeconds: Int,
        totalCalories: Double,
        totalDistance: Double
    ) {
        let message: [String: Any] = [
            "type": "session_end",
            "athlete_id": athleteId,
            "session_id": sessionId,
            "duration_seconds": durationSeconds,
            "total_calories": totalCalories,
            "total_distance": totalDistance
        ]
        sendWebSocketJSON(message)
    }

    private func sendWebSocketJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8) else {
            return
        }
        sendWebSocket(string)
    }

    /// Used by `OfflineQueueManager` to flush queued JSON without exposing `webSocketTask`.
    func sendQueuedWebSocketString(_ jsonString: String, completion: @escaping (Error?) -> Void) {
        guard isConnected, let task = webSocketTask else {
            completion(NSError(domain: "BackendSyncService", code: -1, userInfo: [NSLocalizedDescriptionKey: "WebSocket not connected"]))
            return
        }
        task.send(.string(jsonString), completionHandler: completion)
    }

    private func sendWebSocket(_ message: String) {
        guard isConnected, let task = webSocketTask else {
            // Queue for later
            if let data = message.data(using: .utf8) {
                offlineQueue.enqueue(message: dictFromJSON(data) ?? [:])
            }
            return
        }

        let wsMessage = URLSessionWebSocketTask.Message.string(message)
        task.send(wsMessage) { [weak self] error in
            if let error = error {
                print("WebSocket send error: \(error.localizedDescription)")
                // Queue for retry
                if let dict = self?.dictFromJSON(message.data(using: .utf8) ?? Data()) {
                    self?.offlineQueue.enqueue(message: dict)
                }
                Task { @MainActor in
                    self?.handleDisconnection()
                }
            }
        }
    }

    private func dictFromJSON(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // MARK: - WebSocket Receive

    private func receiveWebSocketMessages() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleWebSocketMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleWebSocketMessage(text)
                    }
                @unknown default:
                    break
                }
                self?.receiveWebSocketMessages()

            case .failure(let error):
                print("WebSocket receive error: \(error.localizedDescription)")
                Task { @MainActor in
                    self?.handleDisconnection()
                }
            }
        }
    }

    private func handleWebSocketMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        print("Backend WS received: \(type)")

        switch type {
        case "connected":
            Task { @MainActor in
                self.connectionState = .connected
            }
            // Flush offline queue
            offlineQueue.flushToBackend()

        case "subscribed":
            print("Subscribed to session")

        case "heartbeat":
            sendWebSocketJSON(["type": "heartbeat", "ts": Date().timeIntervalSince1970])

        case "pong":
            break

        default:
            break
        }
    }

    // MARK: - HTTP Fallback

    func sendHeartRateViaHTTP(_ dataPoint: [String: Any]) async {
        guard let url = httpBaseURL?.appendingPathComponent("api/data/heart-rate") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: dataPoint)
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("HTTP heart rate sent successfully")
            }
        } catch {
            print("HTTP send failed: \(error.localizedDescription)")
            offlineQueue.enqueue(message: dataPoint)
        }
    }

    // MARK: - Recovery Metrics Sync (HTTP)

    func syncRecoveryMetrics(
        athleteId: String,
        sessionId: String?,
        date: Date,
        sleepHours: Double?,
        sleepDeepHours: Double?,
        sleepRemHours: Double?,
        sleepAwakeMinutes: Int?,
        spo2Avg: Double?,
        spo2Min: Double?,
        restingHR: Int?,
        hrvAvg: Int?,
        vo2Max: Double?,
        recoveryScore: Double?,
        fatigueScore: Double?,
        readinessScore: Double?
    ) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var payload: [String: Any] = [
            "athlete_id": athleteId,
            "date": dateFormatter.string(from: date),
            "sleep_hours": sleepHours as Any,
            "sleep_deep_hours": sleepDeepHours as Any,
            "sleep_rem_hours": sleepRemHours as Any,
            "sleep_awake_minutes": sleepAwakeMinutes as Any,
            "spo2_avg": spo2Avg as Any,
            "spo2_min": spo2Min as Any,
            "resting_hr": restingHR as Any,
            "hrv_avg": hrvAvg as Any,
            "vo2_max": vo2Max as Any,
            "recovery_score": recoveryScore as Any,
            "fatigue_score": fatigueScore as Any,
            "readiness_score": readinessScore as Any,
        ]

        if let sessionId = sessionId {
            payload["session_id"] = sessionId
        }

        Task {
            await sendRecoveryMetricsViaHTTP(payload)
        }
    }

    private func sendRecoveryMetricsViaHTTP(_ payload: [String: Any]) async {
        guard let url = httpBaseURL?.appendingPathComponent("api/recovery/sync") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("Recovery metrics synced successfully")
            }
        } catch {
            print("Recovery sync failed: \(error.localizedDescription)")
            offlineQueue.enqueue(message: ["type": "recovery_sync", "payload": payload])
        }
    }

    // MARK: - Ping / Keep-Alive

    private func startPingTimer() {
        stopPingTimer()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.sendWebSocketJSON(["type": "ping"])
        }
    }

    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    // MARK: - Reconnection

    private func handleDisconnection() {
        isConnected = false
        stopPingTimer()

        guard reconnectAttempts < maxReconnectAttempts else {
            connectionState = .disconnected
            print("BackendSync: Max reconnect attempts reached")
            return
        }

        reconnectAttempts += 1
        let delay = min(Double(1 << reconnectAttempts), 60.0)

        Task { @MainActor in
            connectionState = .reconnecting(attempt: reconnectAttempts)
        }

        print("BackendSync: Reconnecting in \(delay)s (attempt \(reconnectAttempts))")

        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                // Reconnect with the last known athlete ID
                self?.connect(athleteId: "athlete-001")
            }
        }
    }

    private func stopReconnectTimer() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
}

// MARK: - URLSessionWebSocketDelegate

extension BackendSyncService: URLSessionWebSocketDelegate {
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        print("WebSocket connected")
        Task { @MainActor in
            isConnected = true
            connectionState = .connected
            reconnectAttempts = 0
        }
        startPingTimer()

        // Flush any queued messages
        offlineQueue.flushToBackend()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        print("WebSocket closed: \(closeCode)")
        Task { @MainActor in
            handleDisconnection()
        }
    }
}
