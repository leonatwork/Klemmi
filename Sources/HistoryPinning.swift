import Foundation

/// Pure ordering and retention rules shared by the store and its tests.
enum HistoryPinning {
    /// Pins first, newest first in each group. Keep input order for equal dates.
    static func ordered(_ items: [HistoryItem]) -> [HistoryItem] {
        items.enumerated().sorted { a, b in
            if a.element.pinned != b.element.pinned { return a.element.pinned }
            if a.element.date != b.element.date { return a.element.date > b.element.date }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// Pins count toward the limit and are never removed. Even when pins reach
    /// or exceed the limit, reserve at least one slot for an ordinary entry.
    static func trimmed(_ items: [HistoryItem], limit: Int) -> [HistoryItem] {
        let sorted = ordered(items)
        let pins = sorted.filter(\.pinned)
        let ordinarySlots = max(1, max(1, limit) - pins.count)
        return pins + Array(sorted.filter { !$0.pinned }.prefix(ordinarySlots))
    }
}
