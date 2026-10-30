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
    /// Erststart erledigt; kein gespeicherter Anmeldestatus. Auch bei Fehlern gesetzt.
    static var loginItemFirstLaunchCompleted: Bool {
        get { d.bool(forKey: "loginItemFirstLaunchCompleted") }
        set { d.set(newValue, forKey: "loginItemFirstLaunchCompleted") }
    }
    /// Respektiert die org.nspasteboard-Konvention, mit der z.B. Passwort-Manager
    /// einzelne Kopiervorgänge als "nicht speichern" markieren.
    static var ignoreConcealed: Bool {
        get { d.object(forKey: "ignoreConcealed") as? Bool ?? true }
        set { d.set(newValue, forKey: "ignoreConcealed") }
    }
    /// Quell-App-Heuristik: Standard aktiv, eine explizit leere Liste bleibt leer.
    /// Die Pflegeoberfläche folgt in einem separaten Paket.
    static var excludedAppBundleIDs: [String] {
        get { d.stringArray(forKey: "excludedAppBundleIDs") ?? CapturePolicy.defaultExcludedAppBundleIDs }
        set { d.set(newValue, forKey: "excludedAppBundleIDs") }
    }
    /// Globales Overlay-Kürzel registrieren; ohne gespeicherten Wert gilt ⌃⌥⌘V.
    static var overlayHotKeyEnabled: Bool {
        get { d.object(forKey: "overlayHotKeyEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "overlayHotKeyEnabled") }
    }
    static var overlayHotKey: HotKeyShortcut {
        get { HotKeyShortcut.load(from: d) }
        set { newValue.save(to: d) }
    }
    /// ↩ im Overlay sendet zusätzlich ⌘V an die zuvor aktive App (braucht Bedienungshilfen).
    /// Standard aus: Ohne die Einstellung fragt Klemmi keine Berechtigung ab.
    static var directPaste: Bool {
        get { d.bool(forKey: "directPaste") }
        set { d.set(newValue, forKey: "directPaste") }
    }
    /// Die Systemabfrage für Bedienungshilfen wurde schon einmal ausgelöst (macOS zeigt sie
    /// pro App nur einmal; danach öffnet Klemmi stattdessen die Systemeinstellungen).
    static var directPastePromptShown: Bool {
        get { d.bool(forKey: "directPastePromptShown") }
        set { d.set(newValue, forKey: "directPastePromptShown") }
    }
    /// Zuletzt gewählte Gruppierung in der Übersicht (Rohwert von GroupingMode).
    static var groupingMode: Int {
        get { d.integer(forKey: "groupingMode") }
        set { d.set(newValue, forKey: "groupingMode") }
    }
}
