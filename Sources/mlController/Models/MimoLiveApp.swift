import Foundation

struct MimoLiveApp: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let version: String

    /// Display name: "mimoLive 6.15" or "mimoLive beta 6.17b3" etc.
    var displayName: String {
        let base = url.deletingPathExtension().lastPathComponent
        return "\(base) (\(version))"
    }

    /// Short label for Picker rows
    var shortName: String {
        url.deletingPathExtension().lastPathComponent
    }
}

// MARK: - Scanner

extension MimoLiveApp {
    static func findAll(bundleID: String = "com.boinx.mimoLive") -> [MimoLiveApp] {
        let fm = FileManager.default
        var seen = Set<String>()
        var results: [MimoLiveApp] = []

        let searchDirs: [URL] = ([
            URL(fileURLWithPath: "/Applications"),
            fm.urls(for: .applicationDirectory, in: .userDomainMask).first,
            fm.urls(for: .downloadsDirectory, in: .userDomainMask).first,
        ] as [URL?]).compactMap { $0 }

        for dir in searchDirs {
            guard let entries = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for appURL in entries where appURL.pathExtension == "app" {
                let canonical = appURL.standardizedFileURL.path
                guard !seen.contains(canonical) else { continue }

                guard let bundle = Bundle(url: appURL),
                      bundle.bundleIdentifier == bundleID else { continue }

                seen.insert(canonical)
                let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                results.append(MimoLiveApp(url: appURL, version: version))
            }
        }

        // Sort: newest version first (lexicographic is good enough for semver-ish strings)
        return results.sorted { $0.version > $1.version }
    }
}
