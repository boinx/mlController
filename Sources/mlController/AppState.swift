import Foundation
import Combine
import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class AppState: ObservableObject {

    static let shared = AppState()

    // MARK: - Published State

    @Published var isMimoLiveRunning: Bool = false
    @Published var openDocuments: [MimoDocument] = []
    @Published var localDocuments: [URL] = []
    @Published var webServerPort: UInt16 = 8990

    /// All mimoLive installations found on this machine
    @Published var availableMimoLiveApps: [MimoLiveApp] = []

    /// The installation the user wants to use; nil = system default
    @Published var selectedMimoLiveURL: URL? {
        didSet {
            if let url = selectedMimoLiveURL {
                UserDefaults.standard.set(url.path, forKey: "selectedMimoLiveURL")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedMimoLiveURL")
            }
            pushSnapshotToServer()
            loadDocIcon()
        }
    }

    @Published var passwordEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(passwordEnabled, forKey: "passwordEnabled")
            pushSnapshotToServer()
        }
    }

    @Published var webPassword: String = "" {
        didSet {
            UserDefaults.standard.set(webPassword, forKey: "webPassword")
            pushSnapshotToServer()
        }
    }

    /// Whether the app is registered to launch at login (reads live from SMAppService)
    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        objectWillChange.send()
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("[mlController] Failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
        }
    }

    // MARK: - Services

    private let monitor = MimoLiveMonitor()
    private let controller = MimoLiveController()
    private let scanner = LocalDocumentScanner()
    private let mimoWebSocket = MimoLiveWebSocket()
    private(set) var webServer: WebServer?
    private var settingsWindowController: NSWindowController?

    // MARK: - Lifecycle

    private var isStarted = false
    private var pollingTask: Task<Void, Never>?

    init() {
        passwordEnabled = UserDefaults.standard.bool(forKey: "passwordEnabled")
        webPassword = UserDefaults.standard.string(forKey: "webPassword") ?? ""
    }

    func start() async {
        guard !isStarted else { return }
        isStarted = true

        // Discover mimoLive installations and restore saved selection
        availableMimoLiveApps = MimoLiveApp.findAll()
        if let savedPath = UserDefaults.standard.string(forKey: "selectedMimoLiveURL") {
            let savedURL = URL(fileURLWithPath: savedPath)
            if availableMimoLiveApps.contains(where: { $0.url.standardizedFileURL == savedURL.standardizedFileURL }) {
                selectedMimoLiveURL = savedURL
            }
        }

        // WebSocket triggers instant refresh on document open/close.
        // Short delay lets mimoLive's REST API catch up to its WebSocket events.
        mimoWebSocket.onChange = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Task { @MainActor in
                    await self?.refresh()
                }
            }
        }

        startWebServer()
        loadDocIcon()
        await refresh()
        startPolling()
    }

    // MARK: - Web Server

    private func startWebServer() {
        let server = WebServer(port: webServerPort)
        server.onStart   = { [weak self] in Task { await self?.startMimoLive() } }
        server.onStop    = { [weak self] in self?.stopMimoLive() }
        server.onRestart = { [weak self] in Task { await self?.restartMimoLive() } }
        server.onOpenDocument = { [weak self] path in
            Task { await self?.openDocument(at: URL(fileURLWithPath: path)) }
        }
        server.onSelectVersion = { [weak self] path in
            guard let self = self else { return }
            if let path = path {
                self.selectedMimoLiveURL = URL(fileURLWithPath: path)
            } else {
                self.selectedMimoLiveURL = nil
            }
        }
        server.start()
        self.webServer = server
        pushSnapshotToServer()
    }

    private func pushSnapshotToServer() {
        guard let server = webServer else { return }
        let selectedName = selectedMimoLiveURL.flatMap { url in
            availableMimoLiveApps.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL })?.displayName
        }
        let snap = StatusSnapshot(
            running: isMimoLiveRunning,
            openDocuments: openDocuments.map { ["id": $0.id, "name": $0.displayName, "path": $0.filePath] },
            localDocuments: localDocuments.map { $0.path },
            passwordEnabled: passwordEnabled,
            passwordHash: passwordEnabled ? server.sha256(webPassword) : "",
            selectedMimoLive: selectedName ?? "Default",
            availableMimoLiveApps: availableMimoLiveApps.map { ["name": $0.displayName, "path": $0.url.path] },
            selectedMimoLivePath: selectedMimoLiveURL?.path ?? ""
        )
        server.updateSnapshot(snap)
    }

    // MARK: - Doc Icon

    private func loadDocIcon() {
        // Get the icon registered for .tvshow files (mimoLive registers this at install time)
        let image = NSWorkspace.shared.icon(forFileType: "tvshow")

        let size = NSSize(width: 32, height: 32)
        let rendered = NSImage(size: size)
        rendered.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: .zero, operation: .copy, fraction: 1)
        rendered.unlockFocus()

        guard let tiff = rendered.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        webServer?.setDocIconData([UInt8](png))
    }

    // MARK: - Polling

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { break }
                await refresh()
            }
        }
    }

    func refresh() async {
        let running = monitor.isMimoLiveRunning()
        let docs: [MimoDocument] = running ? ((try? await monitor.fetchOpenDocuments()) ?? []) : []
        let local = scanner.scanLocalDocuments()

        // Manage WebSocket lifecycle based on mimoLive running state
        if running && !mimoWebSocket.isConnected {
            mimoWebSocket.connect()
        } else if !running && mimoWebSocket.isConnected {
            mimoWebSocket.disconnect()
        }

        isMimoLiveRunning = running
        openDocuments = docs
        localDocuments = local
        pushSnapshotToServer()
    }

    // MARK: - mimoLive Control

    func startMimoLive() async {
        await controller.start(at: selectedMimoLiveURL)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        await refresh()
    }

    func stopMimoLive() {
        controller.stop()
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await refresh()
        }
    }

    func restartMimoLive() async {
        await controller.restart(at: selectedMimoLiveURL)
        await refresh()
    }

    func openDocument(at url: URL) async {
        controller.openDocument(at: url, using: selectedMimoLiveURL)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        await refresh()
    }

    // MARK: - Settings Window

    func openSettings() {
        if settingsWindowController == nil {
            let view = SettingsView().environmentObject(self)
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "mlController Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 480, height: 360))
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindowController = NSWindowController(window: window)
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
