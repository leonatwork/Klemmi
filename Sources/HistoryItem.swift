import Foundation

enum HistoryKind: String, Codable {
    case text
    case image
}

struct HistoryItem: Codable, Identifiable, Equatable {
    let id: UUID
    let kind: HistoryKind
    var text: String?
    /// Dateiname (relativ zum Bilderordner) für .image-Einträge.
    var imageFile: String?
    let sourceAppName: String?
    let sourceBundleID: String?
    var date: Date
    var pinned = false

    init(id: UUID, kind: HistoryKind, text: String?, imageFile: String?,
         sourceAppName: String?, sourceBundleID: String?, date: Date, pinned: Bool = false) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imageFile = imageFile
        self.sourceAppName = sourceAppName
        self.sourceBundleID = sourceBundleID
        self.date = date
        self.pinned = pinned
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, text, imageFile, sourceAppName, sourceBundleID, date, pinned
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        kind = try values.decode(HistoryKind.self, forKey: .kind)
        text = try values.decodeIfPresent(String.self, forKey: .text)
        imageFile = try values.decodeIfPresent(String.self, forKey: .imageFile)
        sourceAppName = try values.decodeIfPresent(String.self, forKey: .sourceAppName)
        sourceBundleID = try values.decodeIfPresent(String.self, forKey: .sourceBundleID)
        date = try values.decode(Date.self, forKey: .date)
        pinned = try values.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    }

    var preview: String {
        switch kind {
        case .text:
            let t = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? L10n.tr("item.empty") : t
        case .image:
            return L10n.tr("item.image")
        }
    }
}
