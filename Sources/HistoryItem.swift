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

    var preview: String {
        switch kind {
        case .text:
            let t = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? "(leer)" : t
        case .image:
            return "Bild"
        }
    }
}
