import Foundation

final class LocalDocumentScanner: @unchecked Sendable {

    /// Recursively scans ~/Documents for mimoLive documents (.tvshow files),
    /// sorted by modification date descending (most recent first).
    func scanLocalDocuments() async -> [URL] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: self._scanSync())
            }
        }
    }

    private func _scanSync() -> [URL] {
        let fm = FileManager.default
        guard let docsDir = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return []
        }

        // Check readability first — ~/Documents may be inaccessible without TCC permission,
        // and FileManager.enumerator can block indefinitely in that case.
        guard fm.isReadableFile(atPath: docsDir.path) else {
            return []
        }

        var results: [URL] = []
        scanDirectory(docsDir, into: &results, fm: fm)

        // Sort newest first
        return results.sorted { a, b in
            let aDate = modDate(a)
            let bDate = modDate(b)
            return aDate > bDate
        }
    }

    private func scanDirectory(_ dir: URL, into results: inout [URL], fm: FileManager) {
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        for name in names where !name.hasPrefix(".") {
            let url = dir.appendingPathComponent(name)
            if name.hasSuffix(".tvshow") {
                results.append(url)
            } else {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue,
                   !name.hasSuffix(".app") {
                    scanDirectory(url, into: &results, fm: fm)
                }
            }
        }
    }

    private func modDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
