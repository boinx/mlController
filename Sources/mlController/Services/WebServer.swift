import Foundation
import Swifter
import CryptoKit

// MARK: - Thread-safe state snapshot pushed from AppState

struct StatusSnapshot {
    var running: Bool = false
    var openDocuments: [[String: String]] = []
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

    // Callbacks invoked on the main queue for control commands
    var onStart: (() -> Void)?
    var onStop: (() -> Void)?
    var onRestart: (() -> Void)?
    var onOpenDocument: ((String) -> Void)?
    /// Called with the selected app path, or nil to reset to system default
    var onSelectVersion: ((String?) -> Void)?

    init(port: UInt16 = 8990) {
        self.port = port
        setupRoutes()
    }

    // MARK: - Snapshot Update (called from MainActor, stored thread-safely)

    func updateSnapshot(_ snapshot: StatusSnapshot) {
        snapshotLock.withLock { _snapshot = snapshot }
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

        // API
        server.GET["/api/status"] = handleStatus
        server.GET["/api/docicon"] = handleDocIcon
        server.POST["/api/start"] = handleStart
        server.POST["/api/stop"] = handleStop
        server.POST["/api/restart"] = handleRestart
        server.POST["/api/open"] = handleOpen
        server.POST["/api/select"] = handleSelect
        server.POST["/api/zoom/join"] = handleZoomJoin
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
            return .raw(200, "OK", ["Content-Type": mimeType]) { writer in
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
            guard let self = self else { return .internalServerError }
            let snap = self.snapshot
            let body: [String: Any] = [
                "running": snap.running,
                "openDocuments": snap.openDocuments,
                "localDocuments": snap.localDocuments,
                "selectedMimoLive": snap.selectedMimoLive,
                "availableMimoLiveApps": snap.availableMimoLiveApps,
                "selectedMimoLivePath": snap.selectedMimoLivePath
            ]
            return jsonResponse(body)
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
