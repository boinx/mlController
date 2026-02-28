import Foundation

final class LocalDocumentScanner {

    /// Recursively scans ~/Documents for mimoLive documents (.tvshow files),
    /// sorted by modification date descending (most recent first).
    func scanLocalDocuments() -> [URL] {
        let fm = FileManager.default
        guard let docsDir = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return []
        }

        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = fm.enumerator(
            at: docsDir,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var results: [URL] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "tvshow" else { continue }
            results.append(fileURL)
        }

        // Sort newest first
        return results.sorted { a, b in
            let aDate = modDate(a)
            let bDate = modDate(b)
            return aDate > bDate
        }
    }

    private func modDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
