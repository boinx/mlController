import AppKit
import Foundation

@MainActor
final class MimoLiveController {

    private let bundleID = "com.boinx.mimoLive"

    // MARK: - App Location

    /// Returns the URL of the preferred (system default) mimoLive installation.
    private func defaultMimoLiveURL() -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// Resolves the app URL: explicit selection first, then system default.
    private func resolveAppURL(_ preferred: URL?) -> URL? {
        preferred ?? defaultMimoLiveURL()
    }

    // MARK: - Start

    func start(at appURL: URL? = nil) async {
        guard let url = resolveAppURL(appURL) else {
            NSLog("[mlController] mimoLive not found (bundle: %@)", bundleID)
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        } catch {
            NSLog("[mlController] Failed to start mimoLive: %@", error.localizedDescription)
        }
    }

    // MARK: - Stop

    func stop() {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .forEach { $0.terminate() }
    }

    // MARK: - Restart

    func restart(at appURL: URL? = nil) async {
        stop()
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty { break }
        }
        await start(at: appURL)
    }

    // MARK: - Open Document

    /// Opens a .tvshow document using /usr/bin/open, which reliably routes
    /// to the running mimoLive instance (or launches the preferred version).
    func openDocument(at fileURL: URL, using appURL: URL? = nil) {
        let isRunning = !NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID).isEmpty

        let arguments: [String]
        if isRunning {
            arguments = ["-b", bundleID, fileURL.path]
        } else if let url = resolveAppURL(appURL) {
            arguments = ["-a", url.path, fileURL.path]
        } else {
            arguments = [fileURL.path]
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = arguments
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    NSLog("[mlController] open exited with status %d", process.terminationStatus)
                }
            } catch {
                NSLog("[mlController] Failed to open document: %@", error.localizedDescription)
            }
        }
    }
}
