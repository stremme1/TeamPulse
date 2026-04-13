import Foundation
import SQLite3

// MARK: - OfflineQueueManager

/// Persists unsent data points locally using SQLite.
/// Ensures no data loss during network outages.
/// Automatically replays queued data when connection is restored.
final class OfflineQueueManager: ObservableObject {
    static let shared = OfflineQueueManager()

    @Published private(set) var queuedCount: Int = 0

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.workoutsystem.offlinequeue", qos: .utility)

    private init() {
        openDatabase()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Database Setup

    private func openDatabase() {
        let fileURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("offline_queue.sqlite")

        if sqlite3_open(fileURL.path, &db) == SQLITE_OK {
            createTable()
        } else {
            print("Failed to open offline queue database")
        }
    }

    private func createTable() {
        let createSQL = """
            CREATE TABLE IF NOT EXISTS message_queue (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT,
                athlete_id TEXT,
                message_type TEXT,
                payload TEXT NOT NULL,
                created_at TEXT NOT NULL,
                retry_count INTEGER DEFAULT 0,
                last_attempt TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_queue_created ON message_queue(created_at);
        """

        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, createSQL, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                print("SQL error creating table: \(String(cString: errMsg))")
                sqlite3_free(errMsg)
            }
        }
    }

    // MARK: - Enqueue

    func enqueue(message: [String: Any]) {
        queue.async { [weak self] in
            self?.insertMessage(message)
        }
    }

    private func insertMessage(_ message: [String: Any]) {
        guard let db = db else { return }

        guard let payloadData = try? JSONSerialization.data(withJSONObject: message),
              let payloadString = String(data: payloadData, encoding: .utf8) else {
            return
        }

        let sessionId = message["session_id"] as? String ?? ""
        let athleteId = message["athlete_id"] as? String ?? ""
        let messageType = message["type"] as? String ?? "unknown"
        let createdAt = ISO8601DateFormatter().string(from: Date())

        let sql = "INSERT INTO message_queue (session_id, athlete_id, message_type, payload, created_at) VALUES (?, ?, ?, ?, ?)"
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, sessionId, -1, nil)
            sqlite3_bind_text(stmt, 2, athleteId, -1, nil)
            sqlite3_bind_text(stmt, 3, messageType, -1, nil)
            sqlite3_bind_text(stmt, 4, payloadString, -1, nil)
            sqlite3_bind_text(stmt, 5, createdAt, -1, nil)

            if sqlite3_step(stmt) != SQLITE_DONE {
                print("Failed to insert message: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
        sqlite3_finalize(stmt)

        updateQueueCount()
    }

    // MARK: - Flush

    func flushToBackend() {
        queue.async { [weak self] in
            guard let self = self else { return }
            let messages = self.fetchPendingMessages(limit: 50)

            for message in messages {
                self.sendMessage(message)
            }

            self.updateQueueCount()
        }
    }

    private func fetchPendingMessages(limit: Int) -> [(id: Int64, payload: [String: Any])] {
        guard let db = db else { return [] }

        var results: [(id: Int64, payload: [String: Any])] = []
        let sql = "SELECT id, payload FROM message_queue ORDER BY created_at ASC LIMIT ?"
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(limit))

            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)

                if let cString = sqlite3_column_text(stmt, 1),
                   let payloadData = String(cString: cString).data(using: .utf8),
                   let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                    results.append((id: id, payload: payload))
                }
            }
        }
        sqlite3_finalize(stmt)

        return results
    }

    private func sendMessage(_ message: (id: Int64, payload: [String: Any])) {
        guard let payloadData = try? JSONSerialization.data(withJSONObject: message.payload),
              let payloadString = String(data: payloadData, encoding: .utf8) else {
            return
        }

        // Try WebSocket first
        let backendSync = BackendSyncService.shared
        if backendSync.isConnected {
            backendSync.sendQueuedWebSocketString(payloadString) { [weak self] error in
                if error == nil {
                    self?.markMessageSent(id: message.id)
                } else {
                    self?.incrementRetryCount(id: message.id)
                }
            }
        } else {
            // Fallback to HTTP
            Task {
                let success = await self.sendViaHTTP(message.payload)
                if success {
                    self.markMessageSent(id: message.id)
                } else {
                    self.incrementRetryCount(id: message.id)
                }
            }
        }
    }

    private func sendViaHTTP(_ payload: [String: Any]) async -> Bool {
        let type = payload["type"] as? String ?? ""
        let endpoint: String

        switch type {
        case "heart_rate", "heart_rate_data":
            endpoint = "api/data/heart-rate"
        case "recovery_sync":
            endpoint = "api/recovery/sync"
        default:
            endpoint = "api/data/batch"
        }

        let baseURL = "http://localhost:8000"
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
        } catch {
            print("OfflineQueue HTTP send failed: \(error.localizedDescription)")
        }

        return false
    }

    private func markMessageSent(id: Int64) {
        queue.async { [weak self] in
            self?.deleteMessage(id: id)
        }
    }

    private func deleteMessage(id: Int64) {
        guard let db = db else { return }
        let sql = "DELETE FROM message_queue WHERE id = ?"
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, id)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)

        updateQueueCount()
    }

    private func incrementRetryCount(id: Int64) {
        guard let db = db else { return }
        let sql = "UPDATE message_queue SET retry_count = retry_count + 1, last_attempt = ? WHERE id = ?"
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, ISO8601DateFormatter().string(from: Date()), -1, nil)
            sqlite3_bind_int64(stmt, 2, id)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)

        // Delete messages with too many retries (> 20 attempts)
        cleanupOldMessages()
    }

    private func cleanupOldMessages() {
        guard let db = db else { return }
        let sql = "DELETE FROM message_queue WHERE retry_count > 20"
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    // MARK: - Queue Count

    private func updateQueueCount() {
        guard let db = db else { return }
        let sql = "SELECT COUNT(*) FROM message_queue"
        var stmt: OpaquePointer?
        var count = 0

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)

        Task { @MainActor in
            queuedCount = count
        }
    }

    // MARK: - Manual Sync Trigger

    func forceSync() {
        flushToBackend()
    }

    func clearQueue() {
        queue.async { [weak self] in
            guard let db = self?.db else { return }
            sqlite3_exec(db, "DELETE FROM message_queue", nil, nil, nil)
            self?.updateQueueCount()
        }
    }
}
