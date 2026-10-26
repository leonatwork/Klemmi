import AppKit

/// Reine Entscheidungen für „Direkt einfügen“ im Overlay, ohne Einstellungen,
/// Berechtigungen oder Tastatur anzufassen.
enum DirectPastePolicy {
    /// Woher die Auswahl kam: ↩ im Overlay oder ein Mausklick in der Liste.
    enum Source: Equatable {
        case keyboard, mouse
    }

    enum Action: Equatable {
        /// Eintrag nur in die Zwischenablage legen (Verhalten wie bisher).
        case copyOnly
        /// Zusätzlich ⌘V an die zuvor aktive App senden.
        case copyAndPaste
    }

    /// Welcher Hinweis im Overlay angezeigt wird. Er nennt nur das Standardverhalten
    /// von ↩; die Umkehr per ⌥↩ steht in der Doku.
    enum Hint: Equatable {
        /// „↩ kopieren · esc schließen“ – wie bisher.
        case copy
        /// „↩ einfügen · esc schließen“ – Einstellung an und Recht vorhanden.
        case paste
    }

    enum MenuAction: Equatable {
        /// Erklärdialog zeigen und danach das Recht anfordern.
        case request
        /// Einstellung ausschalten.
        case disable
    }

    struct MenuState {
        let checkmark: NSControl.StateValue
        let action: MenuAction
    }

    /// Mausklick und Doppelklick kopieren immer nur. Ohne Bedienungshilfen-Recht wird
    /// nie eingefügt, auch nicht mit ⌥. Sonst gilt die Einstellung, die ⌥ für diesen
    /// einen Eintrag umkehrt.
    static func action(enabled: Bool, trusted: Bool, invert: Bool, source: Source) -> Action {
        guard source == .keyboard, trusted else { return .copyOnly }
        return enabled != invert ? .copyAndPaste : .copyOnly
    }

    /// Einfügen wird nur angekündigt, wenn ↩ es tatsächlich tut (Einstellung an und Recht
    /// vorhanden); sonst bleibt der Hinweis wie bisher.
    static func hint(enabled: Bool, trusted: Bool) -> Hint {
        enabled && trusted ? .paste : .copy
    }

    /// Ein entzogenes Recht wird im Menü sichtbar (gemischter Zustand); der Klick führt
    /// dann erneut zum Erklärdialog statt die Einstellung stumm auszuschalten.
    static func menuState(enabled: Bool, trusted: Bool) -> MenuState {
        guard enabled else { return MenuState(checkmark: .off, action: .request) }
        return trusted
            ? MenuState(checkmark: .on, action: .disable)
            : MenuState(checkmark: .mixed, action: .request)
    }

    /// Nach dem Erklärdialog: Nur „Fortfahren“ schaltet die Einstellung ein.
    static func settingAfterRequest(continued: Bool) -> Bool {
        continued
    }

    /// Sucht den virtuellen Tastencode, der in der aktuellen Belegung `character` liefert.
    /// `translate` übersetzt einen Tastencode ohne Modifier in das erzeugte Zeichen
    /// (im Produktivcode über UCKeyTranslate). Bei Dvorak liegt „v“ z. B. nicht auf der
    /// ANSI-V-Position. Liefert die Belegung das Zeichen nirgends, gilt `fallback`.
    static func keyCode(for character: Character, translate: (UInt16) -> String?, fallback: UInt16) -> UInt16 {
        let wanted = String(character).lowercased()
        for code in UInt16(0)..<128 {
            guard let produced = translate(code), produced.count == 1 else { continue }
            if produced.lowercased() == wanted { return code }
        }
        return fallback
    }
}
