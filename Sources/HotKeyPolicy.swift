import AppKit
import Carbon.HIToolbox

/// Persistierte Tastenposition mit normalisierten Carbon-Modifiern, ohne Systemzugriffe.
struct HotKeyShortcut: Equatable {
    let keyCode: UInt16
    let modifiers: UInt32

    static let standard = HotKeyShortcut(keyCode: UInt16(kVK_ANSI_V), flags: [.control, .option, .command])
    private static let supported = UInt32(cmdKey | controlKey | optionKey | shiftKey)

    init(keyCode: UInt16, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers & Self.supported
    }

    init(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        self.init(keyCode: keyCode, modifiers: modifiers)
    }

    var flags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }

    var isValid: Bool {
        keyCode < 128 && modifiers & UInt32(cmdKey | controlKey | optionKey) != 0
    }

    static func load(from defaults: UserDefaults) -> Self {
        guard let value = defaults.dictionary(forKey: "overlayHotKey"),
              let code = value["keyCode"] as? Int, let keyCode = UInt16(exactly: code),
              let mask = value["modifiers"] as? Int, let modifiers = UInt32(exactly: mask),
              modifiers & ~supported == 0 else { return .standard }
        let shortcut = Self(keyCode: keyCode, modifiers: modifiers)
        return shortcut.isValid ? shortcut : .standard
    }

    func save(to defaults: UserDefaults) {
        guard isValid else { return }
        defaults.set(["keyCode": Int(keyCode), "modifiers": Int(modifiers)], forKey: "overlayHotKey")
    }

    func displayString(translate: (UInt16) -> String?) -> String {
        var prefix = ""
        if flags.contains(.control) { prefix += "⌃" }
        if flags.contains(.option) { prefix += "⌥" }
        if flags.contains(.shift) { prefix += "⇧" }
        if flags.contains(.command) { prefix += "⌘" }
        let special: [UInt16: String] = [
            UInt16(kVK_Return): "↩", UInt16(kVK_Tab): "⇥", UInt16(kVK_Space): "␣",
            UInt16(kVK_Delete): "⌫", UInt16(kVK_ForwardDelete): "⌦", UInt16(kVK_Escape): "⎋",
            UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
            UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
            UInt16(kVK_Home): "↖", UInt16(kVK_End): "↘",
            UInt16(kVK_PageUp): "⇞", UInt16(kVK_PageDown): "⇟",
            UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3",
            UInt16(kVK_F4): "F4", UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6",
            UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8", UInt16(kVK_F9): "F9",
            UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
            UInt16(kVK_F13): "F13", UInt16(kVK_F14): "F14", UInt16(kVK_F15): "F15",
            UInt16(kVK_F16): "F16", UInt16(kVK_F17): "F17", UInt16(kVK_F18): "F18",
            UInt16(kVK_F19): "F19", UInt16(kVK_F20): "F20"
        ]
        let translated = translate(keyCode).flatMap { $0.isEmpty ? nil : $0.uppercased() }
        return prefix + (special[keyCode] ?? translated ?? "[\(keyCode)]")
    }
}

enum HotKeyPolicy {
    enum Recording: Equatable { case cancel, invalid, shortcut(HotKeyShortcut) }

    static func record(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Recording {
        if keyCode == UInt16(kVK_Escape) { return .cancel }
        if keyCode == UInt16(kVK_Delete) { return .shortcut(.standard) }
        let shortcut = HotKeyShortcut(keyCode: keyCode, flags: flags)
        return shortcut.isValid ? .shortcut(shortcut) : .invalid
    }
}

struct HotKeyFailure: Error {
    let status: Int32
}

/// Transaktion mit injizierten Systemoperationen: Ein Fehler lässt das alte Handle bestehen.
final class HotKeyRegistration<Handle> {
    private let register: (HotKeyShortcut) -> Result<Handle, HotKeyFailure>
    private let unregister: (Handle) -> Result<Void, HotKeyFailure>
    private(set) var activeHandle: Handle?
    private(set) var activeShortcut: HotKeyShortcut?
    private(set) var failure: HotKeyFailure?
    private var pendingRemoval: Handle?
    var isActive: Bool { activeHandle != nil }
    // Der letzte Wechsel kann scheitern, obwohl das bisherige Kürzel weiter aktiv ist.
    var isUnavailable: Bool { !isActive && failure != nil }

    init(register: @escaping (HotKeyShortcut) -> Result<Handle, HotKeyFailure>,
         unregister: @escaping (Handle) -> Result<Void, HotKeyFailure>) {
        self.register = register
        self.unregister = unregister
    }

    @discardableResult
    func apply(_ shortcut: HotKeyShortcut, enabled: Bool) -> Bool {
        guard shortcut.isValid else { return false }
        if let handle = pendingRemoval {
            if case .failure(let error) = unregister(handle) { failure = error; return false }
            pendingRemoval = nil
        }
        if !enabled {
            if let handle = activeHandle {
                if case .failure(let error) = unregister(handle) { failure = error; return false }
            }
            activeHandle = nil
            activeShortcut = nil
            failure = nil
            return true
        }
        if activeShortcut == shortcut { failure = nil; return true }
        switch register(shortcut) {
        case .failure(let error):
            failure = error
            return false
        case .success(let newHandle):
            if let oldHandle = activeHandle,
               case .failure(let error) = unregister(oldHandle) {
                if case .failure = unregister(newHandle) { pendingRemoval = newHandle }
                failure = error
                return false
            }
            activeHandle = newHandle
            activeShortcut = shortcut
            failure = nil
            return true
        }
    }
}
