import Foundation

// Standalone precondition tests, run by build.sh on macOS.
@main
enum HistorySafetyTests {
    static func main() {
        precondition(!HistorySafety.shouldCapture(changeCount: 10, lastChangeCount: 10, ignoredChangeCount: nil))
        precondition(!HistorySafety.shouldCapture(changeCount: 11, lastChangeCount: 10, ignoredChangeCount: 11))
        // Another app copies before the next poll: only our exact count is ignored.
        precondition(HistorySafety.shouldCapture(changeCount: 12, lastChangeCount: 10, ignoredChangeCount: 11))
        precondition(HistorySafety.shouldCapture(changeCount: 12, lastChangeCount: 11, ignoredChangeCount: nil))
        precondition(HistorySafety.shouldCapture(changeCount: 0, lastChangeCount: Int.max, ignoredChangeCount: Int.max))

        precondition(HistorySafety.orphanedFiles(existing: ["used.png", "orphan.png"], referenced: ["used.png", "missing.png"]) == ["orphan.png"])
        precondition(HistorySafety.orphanedFiles(existing: [], referenced: ["missing.png"]).isEmpty)
        precondition(HistorySafety.orphanedFiles(existing: ["a.png", "b.png"], referenced: []) == ["a.png", "b.png"])
        precondition(HistorySafety.orphanedFiles(existing: ["used.png"], referenced: ["used.png"]).isEmpty)

        precondition(HistorySafety.backupName(existing: [], timestamp: "123") == "history.json.corrupt")
        precondition(HistorySafety.backupName(existing: ["history.json.corrupt"], timestamp: "123") == "history.json.corrupt.123")
        precondition(HistorySafety.backupName(existing: ["history.json.corrupt", "history.json.corrupt.123", "history.json.corrupt.123.1"], timestamp: "123") == "history.json.corrupt.123.2")
    }
}
