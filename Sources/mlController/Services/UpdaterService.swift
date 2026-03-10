import Foundation
import Sparkle

/// Wraps Sparkle's SPUStandardUpdaterController for use in SwiftUI.
@MainActor
final class UpdaterService: ObservableObject {

    static let shared = UpdaterService()

    private var controller: SPUStandardUpdaterController?

    /// Whether the "Check for Updates" action is currently available.
    @Published var canCheckForUpdates = false

    /// Whether automatic update checks are enabled (persisted by Sparkle).
    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    private init() {}

    /// Call after app launch to initialize and start the updater.
    func start() {
        let ctrl = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.controller = ctrl
        ctrl.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
