import AppKit
import Carbon.HIToolbox

/// Frei belegbares globales Tastaturkürzel über die Carbon-Hotkey-API.
/// Braucht keine Bedienungshilfen-Berechtigung und keine Abhängigkeiten.
final class OverlayHotKey {
    static let shared = OverlayHotKey()

    /// Wird auf dem Main-Thread aufgerufen, sobald das Kürzel gedrückt wurde.
    var onPressed: (() -> Void)?

    /// Der Recorder kann auch das bereits global registrierte Kürzel aufnehmen.
    var onRecordingShortcut: ((HotKeyShortcut) -> Void)?

    private struct Registration {
        let ref: EventHotKeyRef
        let id: UInt32
    }
    private lazy var registration = HotKeyRegistration<Registration>(register: { [unowned self] shortcut in
        let handlerStatus = self.installHandlerIfNeeded()
        guard handlerStatus == noErr else { return .failure(HotKeyFailure(status: handlerStatus)) }
        self.nextID += 1
        let id = EventHotKeyID(signature: self.signature, id: self.nextID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.modifiers, id,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            return .failure(HotKeyFailure(status: status == noErr ? OSStatus(paramErr) : status))
        }
        return .success(Registration(ref: ref, id: id.id))
    }, unregister: { handle in
        let status = UnregisterEventHotKey(handle.ref)
        return status == noErr ? .success(()) : .failure(HotKeyFailure(status: status))
    })
    private var handlerRef: EventHandlerRef?
    private let signature: OSType = 0x4B4C_4D49 // "KLMI"
    private var nextID: UInt32 = 0

    var isActive: Bool { registration.isActive }
    var isUnavailable: Bool { registration.isUnavailable }
    var failure: HotKeyFailure? { registration.failure }
    static var displayString: String { Settings.overlayHotKey.displayString(translate: label) }

    private init() {}

    /// Registriert oder entfernt das Kürzel je nach Einstellung.
    @discardableResult
    func apply() -> Bool {
        registration.apply(Settings.overlayHotKey, enabled: Settings.overlayHotKeyEnabled)
    }

    /// Erst nach erfolgreichem Wechsel speichern, auch bei deaktiviertem Kürzel.
    @discardableResult
    func change(to shortcut: HotKeyShortcut) -> Bool {
        guard registration.apply(shortcut, enabled: Settings.overlayHotKeyEnabled) else { return false }
        Settings.overlayHotKey = shortcut
        return true
    }

    func showRegistrationError() {
        if let failure { NSLog("Klemmi: shortcut registration failed (status %d)", failure.status) }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.tr("hotKey.error.title")
        alert.informativeText = L10n.tr("hotKey.error.message")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func installHandlerIfNeeded() -> OSStatus {
        guard handlerRef == nil else { return noErr }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()

        // Der Handler ist ein C-Funktionszeiger und darf nichts einfangen; `self` kommt über userData.
        let handler: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            var pressed = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            guard status == noErr else { return status }
            let hotKey = Unmanaged<OverlayHotKey>.fromOpaque(userData).takeUnretainedValue()
            if pressed.signature == hotKey.signature {
                let id = pressed.id
                DispatchQueue.main.async {
                    // Bereits eingereihte Ereignisse des alten Kürzels nach einem Wechsel ignorieren.
                    guard hotKey.registration.activeHandle?.id == id else { return }
                    if let record = hotKey.onRecordingShortcut, let shortcut = hotKey.registration.activeShortcut {
                        record(shortcut)
                    } else {
                        hotKey.onPressed?()
                    }
                }
            }
            return noErr
        }

        return InstallEventHandler(GetApplicationEventTarget(), handler, 1, &spec, context, &handlerRef)
    }

    /// Frisch aus der aktuellen Belegung lesen, ohne ⌥/⇧-Zeichen oder Dead-Key-Zustand.
    static func label(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        return withExtendedLifetime(source) {
            let data = Unmanaged<CFData>.fromOpaque(rawData).takeUnretainedValue() as Data
            return data.withUnsafeBytes { buffer -> String? in
                guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
                var deadKeyState: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 8)
                let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0,
                                            UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
                                            &deadKeyState, characters.count, &length, &characters)
                guard status == noErr, length > 0 else { return nil }
                return String(utf16CodeUnits: characters, count: length)
            }
        }
    }
}
