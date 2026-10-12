import AppKit
import Carbon.HIToolbox

/// Globales Tastaturkürzel ⌘⇧C über die Carbon-Hotkey-API.
/// Braucht keine Bedienungshilfen-Berechtigung und keine Abhängigkeiten.
final class OverlayHotKey {
    static let shared = OverlayHotKey()

    /// Wird auf dem Main-Thread aufgerufen, sobald das Kürzel gedrückt wurde.
    var onPressed: (() -> Void)?

    static let keyCode = UInt32(kVK_ANSI_C)
    static let modifiers = UInt32(cmdKey | shiftKey)
    static let displayString = "⌘⇧C"

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: 0x4B4C_4D49 /* "KLMI" */, id: 1)

    private init() {}

    /// Registriert oder entfernt das Kürzel je nach Einstellung.
    func apply() {
        if Settings.overlayHotKeyEnabled { register() } else { unregister() }
    }

    private func register() {
        guard hotKeyRef == nil else { return }
        installHandlerIfNeeded()

        let status = RegisterEventHotKey(Self.keyCode, Self.modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            hotKeyRef = nil
            NSLog("Klemmi: Tastenkürzel \(Self.displayString) konnte nicht registriert werden (Status \(status))")
        }
    }

    private func unregister() {
        guard let ref = hotKeyRef else { return }
        UnregisterEventHotKey(ref)
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
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
            if pressed.id == hotKey.hotKeyID.id {
                DispatchQueue.main.async { hotKey.onPressed?() }
            }
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &spec, context, &handlerRef)
    }
}
