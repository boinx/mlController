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
        var docs = decoded.data.map(MimoDocument.init)

        // Fetch visible source counts and output destinations per document (concurrent)
        await withTaskGroup(of: (Int, Int, [OutputDestination]).self) { group in
            for (index, doc) in docs.enumerated() {
                group.addTask {
                    async let count = self.fetchVisibleSourceCount(documentId: doc.id)
                    async let dests = self.fetchOutputDestinations(documentId: doc.id)
                    return (index, await count, await dests)
                }
            }
            for await (index, count, dests) in group {
                docs[index].sourceCount = count
                docs[index].outputDestinations = dests
            }
        }

        return docs
    }

    // MARK: - API: Output Destinations

    /// Fetches output destinations for a document with full detail.
    private func fetchOutputDestinations(documentId: String) async -> [OutputDestination] {
        guard let url = URL(string: "\(apiBase)/documents/\(documentId)/output-destinations") else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 3.0
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else {
            return []
        }

        return items.compactMap { item in
            guard let id = item["id"] as? String,
                  let attrs = item["attributes"] as? [String: Any],
                  let title = attrs["title"] as? String else { return nil }
            return OutputDestination(
                id: id,
                title: title,
                type: attrs["type"] as? String ?? title,
                summary: attrs["summary"] as? String ?? "",
                liveState: attrs["live-state"] as? String ?? "off",
                readyToGoLive: attrs["ready-to-go-live"] as? Bool ?? false,
                startsWithShow: attrs["starts-with-show"] as? Bool ?? false,
                stopsWithShow: attrs["stops-with-show"] as? Bool ?? false
            )
        }
    }

    // MARK: - API: Visible Source Count

    /// Fetches sources for a document and returns the count of non-hidden sources.
    private func fetchVisibleSourceCount(documentId: String) async -> Int {
        guard let url = URL(string: "\(apiBase)/documents/\(documentId)/sources") else { return 0 }

        var request = URLRequest(url: url)
        request.timeoutInterval = 3.0
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else {
            return 0
        }

        return items.filter { item in
            guard let attrs = item["attributes"] as? [String: Any] else { return false }
            let isHidden = attrs["is-hidden"] as? Bool ?? false
            return !isHidden
        }.count
    }
}
