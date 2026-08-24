import Foundation

struct Settings {
    private static let d = UserDefaults.standard

    /// Maximale Anzahl gespeicherter Einträge; älteste fallen danach raus.
    static var maxHistoryItems: Int {
        get { let v = d.integer(forKey: "maxHistoryItems"); return v > 0 ? v : 200 }
        set { d.set(newValue, forKey: "maxHistoryItems") }
    }
    static var showInDock: Bool {
        get { d.bool(forKey: "showInDock") }
        set { d.set(newValue, forKey: "showInDock") }
    }
    /// Respektiert die org.nspasteboard-Konvention, mit der z.B. Passwort-Manager
    /// einzelne Kopiervorgänge als "nicht speichern" markieren.
    static var ignoreConcealed: Bool {
        get { d.object(forKey: "ignoreConcealed") as? Bool ?? true }
        set { d.set(newValue, forKey: "ignoreConcealed") }
    }
    /// Zuletzt gewählte Gruppierung in der Übersicht (Rohwert von GroupingMode).
    static var groupingMode: Int {
        get { d.integer(forKey: "groupingMode") }
        set { d.set(newValue, forKey: "groupingMode") }
    }
}
