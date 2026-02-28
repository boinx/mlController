import Foundation

// MARK: - Domain Model

struct MimoDocument: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let filePath: String
}

// MARK: - JSON:API Response Wrappers

struct MimoAPIResponse: Codable {
    let data: [MimoDocumentData]
}

struct MimoDocumentData: Codable {
    let id: String
    let type: String
    let attributes: MimoDocumentAttributes
}

struct MimoDocumentAttributes: Codable {
    let name: String
    let filepath: String?

    enum CodingKeys: String, CodingKey {
        case name
        case filepath
    }
}

extension MimoDocument {
    init(from data: MimoDocumentData) {
        self.id = data.id
        self.name = data.attributes.name
        self.filePath = data.attributes.filepath ?? ""
    }

    /// Returns the document name suitable for display (strips .mls extension if present)
    var displayName: String {
        name.hasSuffix(".mls") ? String(name.dropLast(4)) : name
    }
}
