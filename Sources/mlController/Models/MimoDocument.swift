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
    let duration: Int              // seconds since show started (0 = not live)
    let formattedDuration: String  // "HH:MM:SS"
    let showStart: String?         // ISO date when show went live, nil when off
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
        self.duration = Int(data.attributes.duration ?? 0)
        self.formattedDuration = data.attributes.formattedDuration ?? "00:00:00"

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
}
