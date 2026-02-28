import Foundation

/// Connects to mimoLive's WebSocket at ws://127.0.0.1:8989/api/v1/socket
/// and fires `onChange` when document-level events arrive (added / removed).
/// Handles ping keepalive, auto-reconnect, and clean disconnect.
final class MimoLiveWebSocket: @unchecked Sendable {

    /// Called on a background thread when a document event is received.
    var onChange: (() -> Void)?

    // MARK: - Private State

    private let url = URL(string: "ws://127.0.0.1:8989/api/v1/socket")!
    private let lock = NSLock()
    private var task: URLSessionWebSocketTask?
    private var pingTimer: DispatchSourceTimer?
    private var reconnectWork: DispatchWorkItem?
    private var intentionalDisconnect = false

    /// Whether the WebSocket is currently connected (or connecting).
    var isConnected: Bool {
        lock.withLock { task != nil }
    }

    // MARK: - Public API

    func connect() {
        lock.lock()
        guard task == nil else { lock.unlock(); return }
        intentionalDisconnect = false
        let ws = URLSession.shared.webSocketTask(with: url)
        task = ws
        lock.unlock()

        ws.resume()
        startPing()
        receiveNext()
    }

    func disconnect() {
        lock.lock()
        intentionalDisconnect = true
        let ws = task
        task = nil
        lock.unlock()

        stopPing()
        cancelReconnect()
        ws?.cancel(with: .goingAway, reason: nil)
    }

    // MARK: - Receive Loop

    private func receiveNext() {
        lock.lock()
        guard let ws = task else { lock.unlock(); return }
        lock.unlock()

        ws.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message {
                    self.handleMessage(text)
                }
                self.receiveNext()
            case .failure:
                self.handleDisconnect()
            }
        }
    }

    // MARK: - Message Handling

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // Ignore ping/pong keepalive
        if let event = json["event"] as? String, event == "pong" || event == "ping" {
            return
        }

        // Trigger refresh on document-level lifecycle events.
        // Format 1: {"type":"documents","event":"added"|"removed"} — explicit doc event
        // Format 2: {"event":"added"|"removed",...} with a document relationship — structural change
        if let event = json["event"] as? String,
           event == "added" || event == "removed" {
            onChange?()
        }
    }

    // MARK: - Ping Keepalive

    /// mimoLive expects `{"event":"ping"}` regularly; 15s timeout.
    private func startPing() {
        stopPing()
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in self?.sendPing() }
        timer.resume()
        lock.lock()
        pingTimer = timer
        lock.unlock()
    }

    private func stopPing() {
        lock.lock()
        let timer = pingTimer
        pingTimer = nil
        lock.unlock()
        timer?.cancel()
    }

    private func sendPing() {
        lock.lock()
        let ws = task
        lock.unlock()

        let msg = URLSessionWebSocketTask.Message.string("{\"event\":\"ping\"}")
        ws?.send(msg) { _ in }
    }

    // MARK: - Reconnect

    private func handleDisconnect() {
        lock.lock()
        task = nil
        let shouldReconnect = !intentionalDisconnect
        lock.unlock()

        stopPing()

        // Unexpected disconnect likely means mimoLive state changed (e.g. doc closed, app quit)
        if shouldReconnect {
            onChange?()
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        cancelReconnect()
        let work = DispatchWorkItem { [weak self] in
            self?.connect()
        }
        lock.lock()
        reconnectWork = work
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2, execute: work)
    }

    private func cancelReconnect() {
        lock.lock()
        let work = reconnectWork
        reconnectWork = nil
        lock.unlock()
        work?.cancel()
    }
}
