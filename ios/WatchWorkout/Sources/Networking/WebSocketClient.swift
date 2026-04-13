import Foundation

// MARK: - WebSocketClient

/// Handles WebSocket connection to the backend for real-time data streaming.
/// Primary path: Watch → Backend directly for minimal latency.
/// Backup path: Watch → iPhone via WatchConnectivity for guaranteed delivery.
final class WebSocketClient: ObservableObject {
    static let shared = WebSocketClient()

    @Published private(set) var isConnected = false

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var pingTimer: Timer?
    private var reconnectTimer: Timer?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5

    private var currentAthleteId: String?
    private var currentSessionId: String?

    private let backendHost = "localhost"
    private let backendPort = 8000

    private init() {}

    // MARK: - Connection

    @MainActor
    func connect(athleteId: String) {
        disconnect()

        currentAthleteId = athleteId

        let urlString = "ws://\(backendHost):\(backendPort)/ws/\(athleteId)"
        guard let url = URL(string: urlString) else {
            print("WebSocket: Invalid URL")
            return
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300

        session = URLSession(configuration: config)
        webSocketTask = session?.webSocketTask(with: url)
        webSocketTask?.resume()

        isConnected = true
        reconnectAttempts = 0

        // Start receiving messages
        receiveMessages()
        startPingTimer()

        print("WebSocket: Connected to \(urlString)")
    }

    func disconnect() {
        stopPingTimer()
        stopReconnectTimer()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        session = nil

        Task { @MainActor in
            isConnected = false
        }

        print("WebSocket: Disconnected")
    }

    // MARK: - Session Subscription

    func subscribe(sessionId: String) {
        currentSessionId = sessionId

        let message: [String: Any] = [
            "type": "subscribe",
            "session_id": sessionId
        ]
        sendJSON(message)
    }

    // MARK: - Data Sending

    func sendHeartRateData(athleteId: String, sessionId: String, dataPoint: WorkoutDataPoint) {
        let message: [String: Any] = [
            "type": "heart_rate",
            "athlete_id": athleteId,
            "session_id": sessionId,
            "timestamp": dataPoint.timestamp,
            "heart_rate": dataPoint.heartRate,
            "zone": dataPoint.zone,
            "calories": dataPoint.calories,
            "distance": dataPoint.distance,
            "device_status": dataPoint.deviceStatus
        ]
        sendJSON(message)
    }

    // MARK: - JSON Sending

    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8) else {
            return
        }
        send(string)
    }

    private func send(_ message: String) {
        guard isConnected else { return }

        let wsMessage = URLSessionWebSocketTask.Message.string(message)
        webSocketTask?.send(wsMessage) { [weak self] error in
            if let error = error {
                print("WebSocket send error: \(error.localizedDescription)")
                Task { @MainActor in
                    self?.handleDisconnection()
                }
            }
        }
    }

    // MARK: - Message Receiving

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                // Continue receiving
                self?.receiveMessages()

            case .failure(let error):
                print("WebSocket receive error: \(error.localizedDescription)")
                Task { @MainActor in
                    self?.handleDisconnection()
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        print("WebSocket received: \(type)")

        switch type {
        case "connected", "subscribed", "pong":
            // Acknowledgments — no action needed
            break

        case "heartbeat":
            // Server heartbeat — respond with heartbeat
            sendJSON(["type": "heartbeat", "ts": Date().timeIntervalSince1970])

        case "error":
            if let message = json["message"] as? String {
                print("WebSocket server error: \(message)")
            }

        default:
            print("WebSocket unknown message type: \(type)")
        }
    }

    // MARK: - Ping / Keep-Alive

    private func startPingTimer() {
        stopPingTimer()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }

    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    private func sendPing() {
        sendJSON(["type": "ping"])
    }

    // MARK: - Reconnection

    private func handleDisconnection() {
        isConnected = false
        stopPingTimer()

        guard reconnectAttempts < maxReconnectAttempts,
              let athleteId = currentAthleteId else {
            print("WebSocket: Max reconnect attempts reached or no athlete ID")
            return
        }

        reconnectAttempts += 1
        let delay = min(Double(1 << reconnectAttempts), 30.0) // Exponential backoff, max 30s

        print("WebSocket: Reconnecting in \(delay)s (attempt \(reconnectAttempts))")

        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.connect(athleteId: athleteId)
                if let sessionId = self?.currentSessionId {
                    self?.subscribe(sessionId: sessionId)
                }
            }
        }
    }

    private func stopReconnectTimer() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
}
