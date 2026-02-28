import AppKit
import Foundation

final class MimoLiveMonitor {

    let bundleID = "com.boinx.mimoLive"
    private let apiBase = "http://localhost:8989/api/v1"

    // MARK: - Process Detection

    func isMimoLiveRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    // MARK: - API: Open Documents

    func fetchOpenDocuments() async throws -> [MimoDocument] {
        guard let url = URL(string: "\(apiBase)/documents") else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 3.0
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            return []
        }

        let decoded = try JSONDecoder().decode(MimoAPIResponse.self, from: data)
        return decoded.data.map(MimoDocument.init)
    }
}
