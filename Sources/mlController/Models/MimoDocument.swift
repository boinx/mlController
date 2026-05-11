import Foundation

// MARK: - Domain Model

struct MimoDocument: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let filePath: String
    let liveState: String          // "off", "live"
    let width: Int
    let height: Int
    let framerate: Int
    let samplerate: Int            // audio sample rate in Hz (0 = unknown)
    let duration: Int              // seconds since show started (0 = not live)
    let formattedDuration: String  // "HH:MM:SS"
    let showStart: String?         // ISO date when show went live, nil when off
    let title: String?             // document title from metadata
    let show: String?              // show name from metadata
    let author: String?            // author from metadata
    let description: String?       // description / comments from metadata
    let kioskMode: Bool?           // true if document opens in kiosk mode (read from .tvshow plist)
    let outputs: [MimoOutput]
    var sourceCount: Int           // visible sources only (excludes is-hidden)
    let layerCount: Int
    var outputDestinations: [OutputDestination]  // populated by MimoLiveMonitor
}

// MARK: - Output Destination (full detail from /output-destinations endpoint)

struct OutputDestination: Codable, Hashable {
    let id: String
    let title: String
    let type: String           // "File Recording", "NDI®", "Fullscreen", "Live Streaming"
    let summary: String
    let liveState: String      // "off", "preview", "live"
    let readyToGoLive: Bool
    let startsWithShow: Bool
    let stopsWithShow: Bool
}

// MARK: - Output State

struct MimoOutput: Codable, Hashable {
    let id: String
    let type: String       // "record", "stream", "playout", "fullscreen"
    let liveState: String  // "off", "live"

    enum CodingKeys: String, CodingKey {
        case id, type
        case liveState = "live-state"
    }
}

// MARK: - JSON:API Response Wrappers

struct MimoAPIResponse: Codable {
    let data: [MimoDocumentData]
}

struct MimoDocumentData: Codable {
    let id: String
    let type: String
    let attributes: MimoDocumentAttributes
    let relationships: MimoDocumentRelationships?
}

struct MimoDocumentAttributes: Codable {
    let name: String
    let filepath: String?
    let liveState: String?
    let duration: Double?
    let formattedDuration: String?
    let showStart: Double?          // Core Foundation timestamp (seconds since 2001-01-01)
    let metadata: MimoDocumentMetadata?
    let outputs: [[String: String]]?

    enum CodingKeys: String, CodingKey {
        case name
        case filepath
        case liveState = "live-state"
        case duration
        case formattedDuration = "formatted-duration"
        case showStart = "show-start"
        case metadata
        case outputs
    }
}

struct MimoDocumentMetadata: Codable {
    let framerate: Int?
    let width: Int?
    let height: Int?
    let samplerate: Int?
    let title: String?
    let show: String?
    let author: String?
    let comments: String?     // mimoLive calls this "comments"; we expose it as "description"
    let duration: Int?
}

struct MimoDocumentRelationships: Codable {
    let sources: MimoRelationship?
    let layers: MimoRelationship?

    enum CodingKeys: String, CodingKey {
        case sources
        case layers
    }
}

struct MimoRelationship: Codable {
    let data: [MimoRelationshipItem]?
}

struct MimoRelationshipItem: Codable {
    let type: String
    let id: String
}

extension MimoDocument {
    init(from data: MimoDocumentData) {
        self.id = data.id
        self.name = data.attributes.name
        self.filePath = data.attributes.filepath ?? ""
        self.liveState = data.attributes.liveState ?? "off"
        self.width = data.attributes.metadata?.width ?? 0
        self.height = data.attributes.metadata?.height ?? 0
        self.framerate = data.attributes.metadata?.framerate ?? 0
        self.samplerate = data.attributes.metadata?.samplerate ?? 0
        self.duration = Int(data.attributes.duration ?? 0)
        self.formattedDuration = data.attributes.formattedDuration ?? "00:00:00"

        // Metadata fields surfaced for the dashboard
        self.title = data.attributes.metadata?.title?.nonEmpty
        self.show = data.attributes.metadata?.show?.nonEmpty
        self.author = data.attributes.metadata?.author?.nonEmpty
        self.description = data.attributes.metadata?.comments?.nonEmpty

        // Kiosk mode is not exposed via the mimoLive HTTP API — read it from the
        // document bundle's Document.plist when we have an on-disk path.
        self.kioskMode = MimoDocument.readKioskMode(at: data.attributes.filepath)

        // Convert Core Foundation timestamp to ISO 8601 for the browser
        if let cfTimestamp = data.attributes.showStart {
            let date = Date(timeIntervalSinceReferenceDate: cfTimestamp)
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            self.showStart = fmt.string(from: date)
        } else {
            self.showStart = nil
        }
        self.sourceCount = data.relationships?.sources?.data?.count ?? 0
        self.layerCount = data.relationships?.layers?.data?.count ?? 0

        self.outputDestinations = []  // populated later by MimoLiveMonitor

        // Parse outputs from raw dict array
        if let rawOutputs = data.attributes.outputs {
            self.outputs = rawOutputs.compactMap { dict in
                guard let id = dict["id"],
                      let type = dict["type"],
                      let state = dict["live-state"] else { return nil }
                return MimoOutput(id: id, type: type, liveState: state)
            }
        } else {
            self.outputs = []
        }
    }

    /// Returns the document name suitable for display (strips .mls extension if present)
    var displayName: String {
        name.hasSuffix(".mls") ? String(name.dropLast(4)) : name
    }

    /// Whether the show is currently live
    var isLive: Bool {
        liveState == "live"
    }

    /// Resolution string like "1920x1080"
    var resolution: String {
        guard width > 0 && height > 0 else { return "" }
        return "\(width)x\(height)"
    }

    /// Audio sample rate formatted as "48 kHz" (empty when unknown).
    var formattedSamplerate: String {
        guard samplerate > 0 else { return "" }
        let kHz = Double(samplerate) / 1000.0
        if kHz == floor(kHz) {
            return "\(Int(kHz)) kHz"
        }
        return String(format: "%.1f kHz", kHz)
    }

    // MARK: - Kiosk Mode (read from on-disk .tvshow bundle)

    /// Reads `openDocumentInKioskMode` from the document bundle's Document.plist.
    /// The flag lives at `documentState.showController.showSettings.openDocumentInKioskMode`.
    /// Returns nil if we don't have a file path or the plist can't be read.
    static func readKioskMode(at filepath: String?) -> Bool? {
        guard let filepath = filepath, !filepath.isEmpty else { return nil }
        let plistURL = URL(fileURLWithPath: filepath)
            .appendingPathComponent("Document.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any] else {
            return nil
        }
        if let documentState = dict["documentState"] as? [String: Any],
           let showController = documentState["showController"] as? [String: Any],
           let showSettings = showController["showSettings"] as? [String: Any],
           let flag = showSettings["openDocumentInKioskMode"] as? Bool {
            return flag
        }
        return nil
    }
}

// MARK: - String helper

private extension String {
    /// Returns nil when the string is empty, otherwise self.
    var nonEmpty: String? { isEmpty ? nil : self }
}
