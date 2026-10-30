import Foundation

// macOS, without AppKit or a test target:
// swiftc Sources/Localization.swift Sources/HistoryItem.swift Sources/HistoryPinning.swift Tests/HistoryPinningTests.swift -o /tmp/HistoryPinningTests && /tmp/HistoryPinningTests
@main
enum HistoryPinningTests {
    static func main() throws {
        try decoding()
        orderingAndTrimming()
    }

    static func decoding() throws {
        // Literal legacy JSON, not produced by the new encoder: both kinds and
        // optional metadata must survive the migration without losing entries.
        let legacy = Data("""
        [
          {"id":"00000000-0000-0000-0000-000000000001","kind":"text",
           "text":"synthetic text","sourceAppName":"Editor",
           "sourceBundleID":"org.example.editor","date":"2026-10-01T12:00:00Z"},
          {"id":"00000000-0000-0000-0000-000000000002","kind":"image",
           "imageFile":"synthetic.png","date":"2026-10-02T12:00:00Z"}
        ]
        """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let old = try decoder.decode([HistoryItem].self, from: legacy)
        precondition(old.count == 2 && old.allSatisfy { !$0.pinned })
        precondition(old[0].id.uuidString == "00000000-0000-0000-0000-000000000001")
        precondition(old[0].kind == .text && old[0].text == "synthetic text")
        precondition(old[0].sourceAppName == "Editor" && old[0].sourceBundleID == "org.example.editor")
        precondition(old[0].imageFile == nil && old[1].text == nil)
        precondition(old[1].kind == .image && old[1].imageFile == "synthetic.png")
        precondition(old[1].sourceAppName == nil && old[1].sourceBundleID == nil)
        precondition(old[1].date.timeIntervalSince(old[0].date) == 86_400)

        let current = Data("""
        [
          {"id":"00000000-0000-0000-0000-000000000001","kind":"text",
           "text":"synthetic text","date":"2026-10-01T12:00:00Z","pinned":true},
          {"id":"00000000-0000-0000-0000-000000000002","kind":"image",
           "imageFile":"synthetic.png","date":"2026-10-02T12:00:00Z","pinned":false},
          {"id":"00000000-0000-0000-0000-000000000003","kind":"text",
           "date":"2026-10-03T12:00:00Z","pinned":null}
        ]
        """.utf8)
        let new = try decoder.decode([HistoryItem].self, from: current)
        precondition(new.map(\.pinned) == [true, false, false])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(new)
        let roundTrip = try decoder.decode([HistoryItem].self, from: encoded)
        precondition(roundTrip == new)
        let objects = try JSONSerialization.jsonObject(with: encoded) as! [[String: Any]]
        precondition(objects.map { $0["pinned"] as? Bool } == [true, false, false])
    }

    static func item(_ seconds: Double, pinned: Bool = false) -> HistoryItem {
        HistoryItem(id: UUID(), kind: .text, text: "synthetic \(seconds)", imageFile: nil,
                    sourceAppName: nil, sourceBundleID: nil,
                    date: Date(timeIntervalSince1970: seconds), pinned: pinned)
    }

    static func orderingAndTrimming() {
        let oldestPin = item(1, pinned: true)
        let newestPin = item(3, pinned: true)
        let oldest = item(2)
        let middle = item(4)
        let newest = item(5)
        let input = [middle, oldestPin, newest, newestPin, oldest]
        let expected = [newestPin, oldestPin, newest, middle, oldest]
        precondition(HistoryPinning.ordered(input) == expected)
        precondition(HistoryPinning.ordered(expected) == expected)
        precondition(HistoryPinning.trimmed(input, limit: 4) == Array(expected.prefix(4)))
        precondition(HistoryPinning.trimmed(input, limit: 5) == expected)
        precondition(HistoryPinning.trimmed(input, limit: 100) == expected)
        // Pins count toward the limit, but never consume the last ordinary slot.
        let minimum = [newestPin, oldestPin, newest]
        precondition(HistoryPinning.trimmed(input, limit: 3) == minimum)
        precondition(HistoryPinning.trimmed(input, limit: 2) == minimum)
        precondition(HistoryPinning.trimmed(input, limit: 1) == minimum)
        precondition(HistoryPinning.trimmed(input, limit: 0) == minimum)
        precondition(HistoryPinning.trimmed(input, limit: -1) == minimum)
        precondition(HistoryPinning.trimmed(input, limit: Int.min) == minimum)
        precondition(HistoryPinning.trimmed(input, limit: Int.max) == expected)
        precondition(HistoryPinning.trimmed([], limit: 1).isEmpty)
        precondition(HistoryPinning.trimmed([oldestPin, newestPin], limit: 1) == [newestPin, oldestPin])
        precondition(HistoryPinning.trimmed([oldest, newest, middle], limit: 2) == [newest, middle])
        precondition(HistoryPinning.trimmed([oldest, newest], limit: 0) == [newest])
        // Unpinning restores date order and exposes the formerly protected oldest
        // entry to trimming without changing its timestamp.
        var unpinned = oldestPin
        unpinned.pinned = false
        precondition(HistoryPinning.ordered([unpinned, newestPin, newest]) == [newestPin, newest, unpinned])
        precondition(HistoryPinning.trimmed([unpinned, newestPin, newest], limit: 2) == [newestPin, newest])
        // Equal timestamps preserve incoming order within each pin group.
        let tie = item(5)
        let pinTie = item(3, pinned: true)
        precondition(HistoryPinning.ordered([tie, pinTie, newest, newestPin]) == [pinTie, newestPin, tie, newest])
    }
}
