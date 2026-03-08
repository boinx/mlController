import Foundation
import Swifter
import CryptoKit

// MARK: - Thread-safe state snapshot pushed from AppState

struct StatusSnapshot {
    var running: Bool = false
    var openDocuments: [[String: Any]] = []
    var localDocuments: [String] = []
    var passwordEnabled: Bool = false
    var passwordHash: String = ""
    var selectedMimoLive: String = "Default"
    /// Array of {name, path} dicts for every found mimoLive installation
    var availableMimoLiveApps: [[String: String]] = []
    /// File path of the selected app, or "" to mean "system default"
    var selectedMimoLivePath: String = ""
}

// MARK: - Web Server

final class WebServer: @unchecked Sendable {

    private let server = HttpServer()
    let port: UInt16

    // Thread-safe snapshot of AppState for API reads
    private let snapshotLock = NSLock()
    private var _snapshot = StatusSnapshot()

    // Thread-safe cached PNG bytes for the mimoLive document icon
    private let iconLock = NSLock()
    private var _docIconData: [UInt8]? = nil

    // Connected WebSocket clients for live status push
    private let sessionsLock = NSLock()
    private var _sessions = Set<WebSocketSession>()

    // Callbacks invoked on the main queue for control commands
    var onStart: (() -> Void)?
    var onStop: (() -> Void)?
    var onRestart: (() -> Void)?
    var onOpenDocument: ((String) -> Void)?
    /// Called with the selected app path, or nil to reset to system default
    var onSelectVersion: ((String?) -> Void)?
    /// Called when state changes externally (e.g. output destination toggled) and AppState should refresh
    var onRefreshNeeded: (() -> Void)?

    init(port: UInt16 = 8990) {
        self.port = port
        setupRoutes()
    }

    // MARK: - Snapshot Update (called from MainActor, stored thread-safely)

    func updateSnapshot(_ snapshot: StatusSnapshot) {
        snapshotLock.withLock { _snapshot = snapshot }
        broadcastSnapshot()
    }

    private var snapshot: StatusSnapshot {
        snapshotLock.withLock { _snapshot }
    }

    // MARK: - Doc Icon Update (called from MainActor, stored thread-safely)

    func setDocIconData(_ data: [UInt8]?) {
        iconLock.withLock { _docIconData = data }
    }

    private var docIconData: [UInt8]? {
        iconLock.withLock { _docIconData }
    }

    // MARK: - Lifecycle

    func start() {
        do {
            try server.start(port, forceIPv4: false, priority: .default)
            print("[mlController] Web server running on http://0.0.0.0:\(port)")
        } catch {
            print("[mlController] Web server failed to start on port \(port): \(error)")
        }
    }

    func stop() {
        server.stop()
    }

    // MARK: - Route Setup

    private func setupRoutes() {
        // Auth middleware runs before every handler
        server.middleware.append(authMiddleware)

        // Static assets
        server.GET["/"] = serveFile("index", ext: "html", mimeType: "text/html; charset=utf-8")
        server.GET["/app.js"] = serveFile("app", ext: "js", mimeType: "application/javascript")
        server.GET["/zoom.js"] = serveFile("zoom", ext: "js", mimeType: "application/javascript")
        server.GET["/tabs.js"] = serveFile("tabs", ext: "js", mimeType: "application/javascript")

        // WebSocket for live status push
        server.GET["/ws"] = websocket(
            connected: { [weak self] session in
                guard let self = self else { return }
                self.sessionsLock.lock()
                self._sessions.insert(session)
                self.sessionsLock.unlock()
                // Send current state immediately on connect
                if let json = self.snapshotJSON() {
                    session.writeText(json)
                }
            },
            disconnected: { [weak self] session in
                guard let self = self else { return }
                self.sessionsLock.lock()
                self._sessions.remove(session)
                self.sessionsLock.unlock()
            }
        )

        // API
        server.GET["/api/status"] = handleStatus
        server.GET["/api/docicon"] = handleDocIcon
        server.POST["/api/start"] = handleStart
        server.POST["/api/stop"] = handleStop
        server.POST["/api/restart"] = handleRestart
        server.POST["/api/open"] = handleOpen
        server.POST["/api/select"] = handleSelect
        server.POST["/api/zoom/join"] = handleZoomJoin
        server.GET["/api/zoom/sources"] = handleZoomSources
        server.GET["/api/zoom/participants"] = handleZoomParticipants
        server.POST["/api/zoom/assign"] = handleZoomAssign
        server.POST["/api/zoom/request-recording"] = handleZoomRequestRecording
        server.POST["/api/zoom/leave"] = handleZoomLeave
        server.POST["/api/zoom/meetingaction"] = handleZoomMeetingAction
        server.POST["/api/output-destination/toggle"] = handleOutputDestinationToggle
    }

    // MARK: - Static File Serving (reads from Bundle.module)

    private func serveFile(_ name: String, ext: String, mimeType: String) -> ((HttpRequest) -> HttpResponse) {
        return { [weak self] _ in
            guard self != nil else { return .internalServerError }
            guard let path = Bundle.main.path(forResource: name, ofType: ext, inDirectory: "web"),
                  let data = FileManager.default.contents(atPath: path),
                  let content = String(data: data, encoding: .utf8) else {
                return .notFound
            }
            return .raw(200, "OK", ["Content-Type": mimeType, "Cache-Control": "no-cache"]) { writer in
                try writer.write([UInt8](content.utf8))
            }
        }
    }

    // MARK: - Auth Middleware

    private lazy var authMiddleware: ((HttpRequest) -> HttpResponse?) = { [weak self] request in
        guard let self = self else { return nil }
        let snap = self.snapshot
        guard snap.passwordEnabled, !snap.passwordHash.isEmpty else { return nil }

        // Accept via Basic Auth header or custom header
        let provided = self.extractBasicAuthPassword(from: request)
            ?? request.headers["x-mlcontroller-password"]

        guard let pwd = provided, self.sha256(pwd) == snap.passwordHash else {
            return .raw(401, "Unauthorized", ["WWW-Authenticate": "Basic realm=\"mlController\""]) { w in
                try w.write([UInt8]("Unauthorized".utf8))
            }
        }
        return nil
    }

    // MARK: - API Handlers

    private var handleStatus: ((HttpRequest) -> HttpResponse) {
        return { [weak self] _ in
            guard let self = self, let json = self.snapshotJSON() else {
                return .internalServerError
            }
            return .raw(200, "OK", ["Content-Type": "application/json"]) { writer in
                try writer.write([UInt8](json.utf8))
            }
        }
    }

    // MARK: - Snapshot JSON & WebSocket Broadcast

    /// Serialize current snapshot to JSON string (reused by HTTP handler and WebSocket broadcast).
    private func snapshotJSON() -> String? {
        let snap = snapshot
        let body: [String: Any] = [
            "running": snap.running,
            "openDocuments": snap.openDocuments,
            "localDocuments": snap.localDocuments,
            "selectedMimoLive": snap.selectedMimoLive,
            "availableMimoLiveApps": snap.availableMimoLiveApps,
            "selectedMimoLivePath": snap.selectedMimoLivePath
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    /// Push current snapshot to all connected WebSocket clients.
    private func broadcastSnapshot() {
        guard let json = snapshotJSON() else { return }
        let sessions = sessionsLock.withLock { Array(_sessions) }
        for session in sessions {
            session.writeText(json)
        }
    }

    private var handleSelect: ((HttpRequest) -> HttpResponse) {
        return { [weak self] request in
            let bodyData = Data(request.body)
            guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
                return .badRequest(.text("Invalid JSON"))
            }
            let path = json["path"] as? String  // nil or "" → system default
            let resolved: String? = (path?.isEmpty == false) ? path : nil
            DispatchQueue.main.async { self?.onSelectVersion?(resolved) }
            return jsonResponse(["status": "ok"])
        }
    }

    private var handleDocIcon: ((HttpRequest) -> HttpResponse) {
        return { [weak self] _ in
            guard let self = self, let data = self.docIconData else {
                return .notFound
            }
            return .raw(200, "OK", ["Content-Type": "image/png", "Cache-Control": "max-age=3600"]) { writer in
                try writer.write(data)
            }
        }
    }

    private var handleStart: ((HttpRequest) -> HttpResponse) {
        return { [weak self] _ in
            DispatchQueue.main.async { self?.onStart?() }
            return jsonResponse(["status": "starting"])
        }
    }

    private var handleStop: ((HttpRequest) -> HttpResponse) {
        return { [weak self] _ in
            DispatchQueue.main.async { self?.onStop?() }
            return jsonResponse(["status": "stopping"])
        }
    }

    private var handleRestart: ((HttpRequest) -> HttpResponse) {
        return { [weak self] _ in
            DispatchQueue.main.async { self?.onRestart?() }
            return jsonResponse(["status": "restarting"])
        }
    }

    private var handleOpen: ((HttpRequest) -> HttpResponse) {
        return { [weak self] request in
            let bodyData = Data(request.body)
            guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                  let path = json["path"] as? String, !path.isEmpty else {
                return .badRequest(.text("Missing or empty 'path' field"))
            }
            DispatchQueue.main.async { self?.onOpenDocument?(path) }
            return jsonResponse(["status": "opening"])
        }
    }

    // MARK: - Zoom Join (proxy to mimoLive API)

    private var handleZoomJoin: ((HttpRequest) -> HttpResponse) {
        return { request in
            let bodyData = Data(request.body)
            guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                  let meetingId = json["meetingId"] as? String, !meetingId.isEmpty else {
                return .badRequest(.text("Missing or empty 'meetingId' field"))
            }

            let displayName = (json["displayName"] as? String) ?? "mimoLive"
            let passcode = json["passcode"] as? String
            let zoomAccountName = json["zoomAccountName"] as? String
            let virtualCamera = (json["virtualCamera"] as? Bool) ?? true

            // Build query for mimoLive Zoom join endpoint
            var components = URLComponents(string: "http://localhost:8989/api/v1/zoom/join")!
            var queryItems = [
                URLQueryItem(name: "meetingid", value: meetingId),
                URLQueryItem(name: "displayname", value: displayName),
                URLQueryItem(name: "virtualcamera", value: virtualCamera ? "true" : "false"),
            ]
            if let pc = passcode, !pc.isEmpty {
                queryItems.append(URLQueryItem(name: "passcode", value: pc))
            }
            if let acct = zoomAccountName, !acct.isEmpty {
                queryItems.append(URLQueryItem(name: "zoomaccountname", value: acct))
            }
            components.queryItems = queryItems

            guard let url = components.url else {
                return jsonResponse(["error": "Failed to build mimoLive URL"])
            }

            // Synchronous request to mimoLive (Swifter handlers run on background threads)
            let sem = DispatchSemaphore(value: 0)
            var result: [String: Any] = ["status": "sent"]
            var httpError: String?

            let task = URLSession.shared.dataTask(with: url) { data, response, error in
                if let error = error {
                    httpError = error.localizedDescription
                } else if let httpResp = response as? HTTPURLResponse, httpResp.statusCode >= 400 {
                    httpError = "mimoLive returned HTTP \(httpResp.statusCode)"
                } else if let data = data,
                          let respJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    result = respJson
                }
                sem.signal()
            }
            task.resume()
            _ = sem.wait(timeout: .now() + 10)

            if let err = httpError {
                return jsonResponse(["error": err])
            }
            return jsonResponse(result)
        }
    }

    // MARK: - Zoom Source Management (proxy to mimoLive API)

    /// Fetch Zoom participant sources for the first open document.
    private var handleZoomSources: ((HttpRequest) -> HttpResponse) {
        return { [weak self] _ in
            guard let self = self else { return .internalServerError }
            let snap = self.snapshot
            guard snap.running, let firstDoc = snap.openDocuments.first,
                  let docId = firstDoc["id"] else {
                return jsonResponse(["error": "No document open", "sources": [] as [Any]])
            }
            guard let url = URL(string: "http://localhost:8989/api/v1/documents/\(docId)/sources") else {
                return jsonResponse(["error": "Bad URL"])
            }
            let (data, error) = syncGET(url)
            if let error = error { return jsonResponse(["error": error]) }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["data"] as? [[String: Any]] else {
                return jsonResponse(["error": "Failed to parse sources", "sources": [] as [Any]])
            }
            // Filter to Zoom participant sources only
            let zoomSources: [[String: Any]] = items.compactMap { item in
                guard let attrs = item["attributes"] as? [String: Any],
                      let sourceType = attrs["source-type"] as? String,
                      sourceType == "com.boinx.mimoLive.sources.zoomparticipant",
                      let id = item["id"] as? String else { return nil }
                var source: [String: Any] = ["id": id]
                source["name"] = attrs["name"] ?? ""
                source["summary"] = attrs["summary"] ?? ""
                source["zoom-username"] = attrs["zoom-username"] ?? ""
                source["zoom-userselectiontype"] = attrs["zoom-userselectiontype"] ?? 0
                if let uid = attrs["zoom-userid"] { source["zoom-userid"] = uid }
                return source
            }
            return jsonResponse(["sources": zoomSources])
        }
    }

    /// Fetch all Zoom meeting participants.
    private var handleZoomParticipants: ((HttpRequest) -> HttpResponse) {
        return { [weak self] _ in
            guard let self = self else { return .internalServerError }
            guard let url = URL(string: "http://localhost:8989/api/v1/zoom/participants") else {
                return jsonResponse(["error": "Bad URL"])
            }
            let (data, error) = self.syncGET(url)
            if let error = error { return jsonResponse(["error": error, "participants": [] as [Any]]) }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["data"] as? [Any] else {
                return jsonResponse(["error": "Failed to parse participants", "participants": [] as [Any]])
            }
            return jsonResponse(["participants": items])
        }
    }

    /// Assign a Zoom attendee to a source via mimoLive PATCH.
    private var handleZoomAssign: ((HttpRequest) -> HttpResponse) {
        return { request in
            let bodyData = Data(request.body)
            guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                  let sourceId = json["sourceId"] as? String, !sourceId.isEmpty else {
                return .badRequest(.text("Missing 'sourceId'"))
            }
            let selectionType = json["selectionType"] as? Int
            let userId = json["userId"] as? Int

            // Build the PATCH body for mimoLive.
            // For specific participant (type 1): only send zoom-userid — mimoLive infers the type.
            // For Automatic (type 2) or Screen Share (type 6): only send zoom-userselectiontype.
            var patchBody: [String: Any] = [:]
            if let uid = userId, selectionType == 1 {
                patchBody["zoom-userid"] = uid
            } else if let selType = selectionType {
                patchBody["zoom-userselectiontype"] = selType
            }

            // Extract docId from sourceId (format: "docId-UUID")
            let parts = sourceId.split(separator: "-", maxSplits: 1)
            guard parts.count == 2 else { return .badRequest(.text("Invalid sourceId format")) }
            let docId = String(parts[0])

            guard let url = URL(string: "http://localhost:8989/api/v1/documents/\(docId)/sources/\(sourceId)"),
                  let patchData = try? JSONSerialization.data(withJSONObject: patchBody) else {
                return jsonResponse(["error": "Failed to build request"])
            }

            var req = URLRequest(url: url)
            req.httpMethod = "PATCH"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = patchData

            let sem = DispatchSemaphore(value: 0)
            let result: [String: Any] = ["status": "ok"]
            var httpError: String?

            let task = URLSession.shared.dataTask(with: req) { data, response, error in
                if let error = error {
                    httpError = error.localizedDescription
                } else if let httpResp = response as? HTTPURLResponse, httpResp.statusCode >= 400 {
                    httpError = "mimoLive returned HTTP \(httpResp.statusCode)"
                }
                sem.signal()
            }
            task.resume()
            _ = sem.wait(timeout: .now() + 10)

            if let err = httpError { return jsonResponse(["error": err]) }
            return jsonResponse(result)
        }
    }

    /// Leave the current Zoom meeting.
    private var handleZoomLeave: ((HttpRequest) -> HttpResponse) {
        return { [weak self] _ in
            guard let self = self else { return .internalServerError }
            guard let url = URL(string: "http://localhost:8989/api/v1/zoom/leave") else {
                return jsonResponse(["error": "Bad URL"])
            }
            let (data, error) = self.syncGET(url)
            if let error = error { return jsonResponse(["error": error]) }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return jsonResponse(["error": "Failed to parse response"])
            }
            return jsonResponse(json)
        }
    }

    /// Request recording permission from the Zoom meeting host.
    private var handleZoomRequestRecording: ((HttpRequest) -> HttpResponse) {
        return { [weak self] _ in
            guard let self = self else { return .internalServerError }
            guard let url = URL(string: "http://localhost:8989/api/v1/zoom/meetingaction?command=requestRecordingPermission") else {
                return jsonResponse(["error": "Bad URL"])
            }
            let (data, error) = self.syncGET(url)
            if let error = error { return jsonResponse(["error": error]) }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return jsonResponse(["error": "Failed to parse response"])
            }
            return jsonResponse(json)
        }
    }

    /// Execute a Zoom meeting action command via mimoLive API.
    private var handleZoomMeetingAction: ((HttpRequest) -> HttpResponse) {
        return { [weak self] request in
            guard let self = self else { return .internalServerError }
            let bodyData = Data(request.body)
            guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                  let command = json["command"] as? String, !command.isEmpty else {
                return .badRequest(.text("Missing or empty 'command' field"))
            }
            var urlString = "http://localhost:8989/api/v1/zoom/meetingaction?command=\(command)"
            if let userId = json["userId"] as? Int {
                urlString += "&userid=\(userId)"
            }
            guard let url = URL(string: urlString) else {
                return jsonResponse(["error": "Bad URL"])
            }
            let (data, error) = self.syncGET(url)
            if let error = error { return jsonResponse(["error": error]) }
            guard let data = data,
                  let respJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return jsonResponse(["error": "Failed to parse response"])
            }
            return jsonResponse(respJson)
        }
    }

    // MARK: - Output Destination Toggle

    /// Toggle an output destination's live state via mimoLive dedicated endpoints.
    /// Uses GET /api/v1/documents/{docId}/output-destinations/{outputId}/setLive or /setOff.
    private var handleOutputDestinationToggle: ((HttpRequest) -> HttpResponse) {
        return { [weak self] request in
            guard let self = self else { return .internalServerError }
            let bodyData = Data(request.body)
            guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                  let docId = json["docId"] as? String, !docId.isEmpty,
                  let outputId = json["outputId"] as? String, !outputId.isEmpty,
                  let action = json["action"] as? String, !action.isEmpty else {
                return .badRequest(.text("Missing 'docId', 'outputId', or 'action'"))
            }

            // mimoLive provides dedicated setLive / setOff endpoints for output destinations
            let endpoint = action == "setLive" ? "setLive" : "setOff"
            guard let url = URL(string: "http://localhost:8989/api/v1/documents/\(docId)/output-destinations/\(outputId)/\(endpoint)") else {
                return jsonResponse(["error": "Failed to build URL"])
            }

            let (data, error) = self.syncGET(url)
            if let error = error { return jsonResponse(["error": error]) }

            // Trigger AppState refresh so the snapshot (and WebSocket broadcast) updates promptly
            DispatchQueue.main.async { self.onRefreshNeeded?() }

            if let data = data,
               let respJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return jsonResponse(respJson)
            }
            return jsonResponse(["status": "ok"])
        }
    }

    // MARK: - mimoLive Proxy Helper

    /// Synchronous GET request to mimoLive (safe to call from Swifter handler threads).
    private func syncGET(_ url: URL) -> (Data?, String?) {
        let sem = DispatchSemaphore(value: 0)
        var resultData: Data?
        var resultError: String?

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                resultError = error.localizedDescription
            } else if let httpResp = response as? HTTPURLResponse, httpResp.statusCode >= 400 {
                resultError = "mimoLive returned HTTP \(httpResp.statusCode)"
            } else {
                resultData = data
            }
            sem.signal()
        }
        task.resume()
        _ = sem.wait(timeout: .now() + 10)
        return (resultData, resultError)
    }

    // MARK: - Helpers

    private func extractBasicAuthPassword(from request: HttpRequest) -> String? {
        guard let auth = request.headers["authorization"],
              auth.hasPrefix("Basic "),
              let data = Data(base64Encoded: String(auth.dropFirst(6))),
              let decoded = String(data: data, encoding: .utf8) else { return nil }
        // Format: "username:password" — take everything after first colon
        let parts = decoded.components(separatedBy: ":")
        guard parts.count >= 2 else { return nil }
        return parts.dropFirst().joined(separator: ":")
    }

    func sha256(_ string: String) -> String {
        let hash = SHA256.hash(data: Data(string.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - JSON Response Helper

private func jsonResponse(_ body: [String: Any]) -> HttpResponse {
    guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]),
          let str = String(data: data, encoding: .utf8) else {
        return .internalServerError
    }
    return .raw(200, "OK", ["Content-Type": "application/json"]) { writer in
        try writer.write([UInt8](str.utf8))
    }
}
