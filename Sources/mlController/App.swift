import SwiftUI
import AppKit

// MARK: - App Delegate (starts server immediately at launch, not on first click)

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await AppState.shared.start() }
        UpdaterService.shared.start()
    }
}

// MARK: - App

@main
struct mlControllerApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
    @StateObject private var updaterService = UpdaterService.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(updaterService)
        } label: {
            Label {
                Text("mlController")
            } icon: {
                Image(systemName: appState.isMimoLiveRunning
                      ? "video.circle.fill"
                      : "video.slash.fill")
            }
        }
        .menuBarExtraStyle(.window)

    }
}
