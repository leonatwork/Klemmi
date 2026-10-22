import Foundation

/// Pure decisions shared by persistence/clipboard code and standalone tests.
enum HistorySafety {
    static func shouldCapture(changeCount: Int, lastChangeCount: Int, ignoredChangeCount: Int?) -> Bool {
        changeCount != lastChangeCount && changeCount != ignoredChangeCount
    }

    static func orphanedFiles(existing: Set<String>, referenced: Set<String>) -> Set<String> {
        existing.subtracting(referenced)
    }

    static func backupName(existing: Set<String>, timestamp: String) -> String {
        let base = "history.json.corrupt"
        guard existing.contains(base) else { return base }
        let dated = "\(base).\(timestamp)"
        var candidate = dated
        var suffix = 0
        while existing.contains(candidate) {
            suffix += 1
            candidate = "\(dated).\(suffix)"
        }
        return candidate
    }
}
