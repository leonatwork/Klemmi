import AppKit

// Standalone precondition tests, run by build.sh on macOS; no events are posted and
// no permission is requested.
@main
enum DirectPasteTests {
    static func main() {
        testAction()
        testHint()
        testMenuState()
        testKeyCodeLookup()
    }

    // MARK: Entscheidung kopieren / einfügen

    private static func testAction() {
        // AC-1: Einstellung aus → nur kopieren, ganz gleich, ob das Recht vorliegt.
        assertAction(enabled: false, trusted: false, invert: false, source: .keyboard, expected: .copyOnly)
        assertAction(enabled: false, trusted: true, invert: false, source: .keyboard, expected: .copyOnly)

        // AC-3: Einstellung an und Recht vorhanden → ↩ fügt ein.
        assertAction(enabled: true, trusted: true, invert: false, source: .keyboard, expected: .copyAndPaste)

        // AC-4: Recht entzogen → Rückfall auf „nur kopieren“, auch mit ⌥.
        assertAction(enabled: true, trusted: false, invert: false, source: .keyboard, expected: .copyOnly)
        assertAction(enabled: true, trusted: false, invert: true, source: .keyboard, expected: .copyOnly)
        assertAction(enabled: false, trusted: false, invert: true, source: .keyboard, expected: .copyOnly)

        // AC-6: ⌥↩ kehrt die Einstellung für diesen Eintrag um.
        assertAction(enabled: true, trusted: true, invert: true, source: .keyboard, expected: .copyOnly)
        assertAction(enabled: false, trusted: true, invert: true, source: .keyboard, expected: .copyAndPaste)

        // AC-6: Mausklick und Doppelklick kopieren immer nur, unabhängig von allem anderen.
        assertAction(enabled: true, trusted: true, invert: false, source: .mouse, expected: .copyOnly)
        assertAction(enabled: true, trusted: true, invert: true, source: .mouse, expected: .copyOnly)
        assertAction(enabled: false, trusted: true, invert: true, source: .mouse, expected: .copyOnly)
    }

    private static func assertAction(
        enabled: Bool, trusted: Bool, invert: Bool, source: DirectPastePolicy.Source,
        expected: DirectPastePolicy.Action,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let actual = DirectPastePolicy.action(enabled: enabled, trusted: trusted, invert: invert, source: source)
        precondition(actual == expected,
                     "enabled=\(enabled) trusted=\(trusted) invert=\(invert) source=\(source): expected \(expected), got \(actual)",
                     file: file, line: line)
    }

    // MARK: Hinweis im Overlay (AC-7)

    private static func testHint() {
        // AC-1: Einstellung aus → Hinweis wie heute, auch wenn das Recht bereits vorliegt.
        precondition(DirectPastePolicy.hint(enabled: false, trusted: false) == .copy,
                     "Without the setting the hint must stay as before")
        precondition(DirectPastePolicy.hint(enabled: false, trusted: true) == .copy,
                     "Setting off: the hint must stay as before even when trusted")
        // AC-4: Recht entzogen → der Hinweis darf kein Einfügen versprechen.
        precondition(DirectPastePolicy.hint(enabled: true, trusted: false) == .copy,
                     "A revoked permission must not advertise pasting")
        // AC-7: Einstellung an und Recht vorhanden → ↩ fügt ein.
        precondition(DirectPastePolicy.hint(enabled: true, trusted: true) == .paste,
                     "Setting on and trusted: ↩ pastes")
    }

    // MARK: Menüpunkt (AC-2, AC-4)

    private static func testMenuState() {
        assertMenu(enabled: false, trusted: false, checkmark: .off, action: .request)
        assertMenu(enabled: false, trusted: true, checkmark: .off, action: .request)
        assertMenu(enabled: true, trusted: true, checkmark: .on, action: .disable)
        // Recht entzogen: Zustand sichtbar machen, Klick führt wieder zur Freigabe.
        assertMenu(enabled: true, trusted: false, checkmark: .mixed, action: .request)

        // AC-2: Abbruch im Erklärdialog lässt die Einstellung aus; Fortfahren schaltet sie ein.
        precondition(!DirectPastePolicy.settingAfterRequest(continued: false))
        precondition(DirectPastePolicy.settingAfterRequest(continued: true))
    }

    private static func assertMenu(
        enabled: Bool, trusted: Bool,
        checkmark: NSControl.StateValue, action: DirectPastePolicy.MenuAction,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let menu = DirectPastePolicy.menuState(enabled: enabled, trusted: trusted)
        precondition(menu.checkmark == checkmark, "Incorrect checkmark for enabled=\(enabled) trusted=\(trusted)", file: file, line: line)
        precondition(menu.action == action, "Incorrect action for enabled=\(enabled) trusted=\(trusted)", file: file, line: line)
    }

    // MARK: Tastencode aus der Belegung (AC-5)

    private static let ansiV: UInt16 = 9
    private static let ansiPeriod: UInt16 = 47

    private static func testKeyCodeLookup() {
        // QWERTY/QWERTZ: „v“ liegt auf der ANSI-V-Position.
        let qwerty: (UInt16) -> String? = { $0 == ansiV ? "v" : ($0 == ansiPeriod ? "." : "x") }
        precondition(DirectPastePolicy.keyCode(for: "v", translate: qwerty, fallback: ansiV) == ansiV)

        // Dvorak: auf der ANSI-V-Position liegt „.“, „v“ liegt auf der Punkt-Position.
        let dvorak: (UInt16) -> String? = { $0 == ansiV ? "." : ($0 == ansiPeriod ? "v" : "x") }
        precondition(DirectPastePolicy.keyCode(for: "v", translate: dvorak, fallback: ansiV) == ansiPeriod)

        // Großbuchstaben aus der Belegung (z. B. Caps-Lock-Varianten) zählen ebenfalls.
        let upper: (UInt16) -> String? = { $0 == ansiPeriod ? "V" : nil }
        precondition(DirectPastePolicy.keyCode(for: "v", translate: upper, fallback: ansiV) == ansiPeriod)

        // Belegung ohne „v“ (oder ohne Layout-Daten): auf die ANSI-Position zurückfallen.
        let none: (UInt16) -> String? = { _ in nil }
        precondition(DirectPastePolicy.keyCode(for: "v", translate: none, fallback: ansiV) == ansiV)

        // Dead keys/Mehrzeichen-Ergebnisse dürfen nicht als Treffer gelten.
        let multi: (UInt16) -> String? = { $0 == ansiPeriod ? "vv" : nil }
        precondition(DirectPastePolicy.keyCode(for: "v", translate: multi, fallback: ansiV) == ansiV)

        // Der erste Treffer in Tastencode-Reihenfolge gewinnt (deterministisch).
        let twice: (UInt16) -> String? = { $0 == 3 || $0 == ansiPeriod ? "v" : nil }
        precondition(DirectPastePolicy.keyCode(for: "v", translate: twice, fallback: ansiV) == 3)
    }
}
