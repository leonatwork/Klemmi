import AppKit
import Carbon.HIToolbox

/// „Direkt einfügen“: Bedienungshilfen-Recht prüfen und anfordern, ⌘V an die zuvor
/// aktive App senden. Die Entscheidungen dazu liegen in DirectPastePolicy.
enum DirectPaste {
    /// Pause zwischen dem Schließen des Overlays und ⌘V, damit die Ziel-App den
    /// Tastendruck annimmt. Manuell ermittelt; bei Problemen hier nachjustieren.
    static let pasteDelay: TimeInterval = 0.05

    /// Liest nur den Status. Zeigt keine Systemabfrage und trägt Klemmi nirgends ein.
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Einschalten: Liegt das Recht vor, sofort an. Sonst erst der Erklärdialog, dann die
    /// Systemabfrage. Gibt zurück, ob die Einstellung danach an sein soll (AC-2: Abbruch → aus).
    static func enable() -> Bool {
        if isTrusted() { return true }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.tr("directPaste.permission.title")
        alert.informativeText = L10n.tr("directPaste.permission.message")
        alert.addButton(withTitle: L10n.tr("directPaste.permission.continue"))
        alert.addButton(withTitle: L10n.tr("directPaste.permission.cancel")).keyEquivalent = "\u{1b}"
        NSApp.activate(ignoringOtherApps: true)
        let continued = alert.runModal() == .alertFirstButtonReturn

        if continued { promptForPermission() }
        return DirectPastePolicy.settingAfterRequest(continued: continued)
    }

    /// Systemabfrage auslösen (trägt Klemmi in die Bedienungshilfen-Liste ein). macOS zeigt
    /// die Abfrage pro App nur einmal; bei jeder weiteren Anfrage (z. B. nach einem Entzug)
    /// wird stattdessen der Bereich in den Systemeinstellungen geöffnet.
    private static func promptForPermission() {
        let shownBefore = Settings.directPastePromptShown
        Settings.directPastePromptShown = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard !AXIsProcessTrustedWithOptions(options), shownBefore else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: ⌘V senden

    /// Nach dem Schließen des Overlays mit kurzer Verzögerung einfügen. Das Recht wird dabei
    /// noch einmal geprüft: Ohne Recht wird nichts gesendet (AC-4), der Eintrag liegt dann
    /// bereits in der Zwischenablage.
    static func pasteAfterOverlayClosed() {
        DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay) {
            guard isTrusted() else { return }
            sendPasteKeystroke()
        }
    }

    private static func sendPasteKeystroke() {
        let keyCode = pasteKeyCode()
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            NSLog("Klemmi: could not create the paste key events")
            return
        }
        // Nur ⌘, auch wenn der Nutzer ⌥ von ⌥↩ noch hält.
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// Tastencode, der in der aktuellen Belegung „v“ erzeugt. kVK_ANSI_V ist nur eine
    /// Tastenposition: Bei Dvorak liegt dort „.“ und ⌘. wäre ein anderes Kürzel (AC-5).
    static func pasteKeyCode() -> UInt16 {
        let fallback = UInt16(kVK_ANSI_V)
        guard let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutRef = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return fallback
        }
        // Die Layout-Daten gehören der Input-Source; sie muss bis zum Ende am Leben bleiben.
        return withExtendedLifetime(inputSource) { () -> UInt16 in
            let layoutData = Unmanaged<CFData>.fromOpaque(layoutRef).takeUnretainedValue() as Data
            let keyboardType = UInt32(LMGetKbdType())

            return DirectPastePolicy.keyCode(for: "v", translate: { code in
                layoutData.withUnsafeBytes { buffer -> String? in
                    guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
                    var deadKeyState: UInt32 = 0
                    var chars = [UniChar](repeating: 0, count: 4)
                    var length = 0
                    let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), 0, keyboardType,
                                                OptionBits(kUCKeyTranslateNoDeadKeysMask),
                                                &deadKeyState, chars.count, &length, &chars)
                    guard status == noErr, length > 0 else { return nil }
                    return String(utf16CodeUnits: chars, count: Int(length))
                }
            }, fallback: fallback)
        }
    }
}
