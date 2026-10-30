import AppKit
import Carbon.HIToolbox

// Standalone precondition tests; no global shortcuts or UI are created.
// swiftc Sources/HotKeyPolicy.swift Tests/HotKeyTests.swift -framework AppKit -framework Carbon -o /tmp/HotKeyTests && /tmp/HotKeyTests
@main
enum HotKeyTests {
    static func main() {
        testValidationAndRecorder()
        testDisplay()
        testPersistence()
        testRegistration()
    }

    private static func testValidationAndRecorder() {
        let standard = HotKeyShortcut.standard
        precondition(standard.keyCode == UInt16(kVK_ANSI_V))
        precondition(standard.modifiers == UInt32(controlKey | optionKey | cmdKey))
        precondition(standard.isValid, "The default must pass modifier validation")
        let invalidFlags: [NSEvent.ModifierFlags] = [[], .shift, .capsLock, [.shift, .function]]
        for flags in invalidFlags {
            precondition(!HotKeyShortcut(keyCode: 0, flags: flags).isValid)
        }
        let validFlags: [NSEvent.ModifierFlags] = [.command, .control, .option, [.command, .shift], [.control, .option, .command, .shift]]
        for flags in validFlags {
            let shortcut = HotKeyShortcut(keyCode: 0, flags: flags)
            precondition(shortcut.isValid)
            precondition(shortcut.flags == flags)
            precondition(HotKeyShortcut(keyCode: 0, flags: flags.union([.capsLock, .function, .numericPad])) == shortcut)
        }
        let mappings: [(NSEvent.ModifierFlags, UInt32)] = [
            (.command, UInt32(cmdKey)), (.control, UInt32(controlKey)),
            (.option, UInt32(optionKey)), (.shift, UInt32(shiftKey))
        ]
        for (flag, carbon) in mappings {
            precondition(HotKeyShortcut(keyCode: 0, flags: flag).modifiers == carbon)
            precondition(HotKeyShortcut(keyCode: 0, modifiers: carbon).flags == flag)
        }
        precondition(HotKeyPolicy.record(keyCode: UInt16(kVK_Escape), flags: .command) == .cancel)
        precondition(HotKeyPolicy.record(keyCode: UInt16(kVK_Delete), flags: []) == .shortcut(standard))
        precondition(HotKeyPolicy.record(keyCode: 0, flags: .shift) == .invalid)
        precondition(HotKeyPolicy.record(keyCode: 0, flags: .command) == .shortcut(HotKeyShortcut(keyCode: 0, flags: .command)))
    }

    private static func testDisplay() {
        let shortcut = HotKeyShortcut.standard
        precondition(shortcut.displayString(translate: { code in
            precondition(code == UInt16(kVK_ANSI_V))
            return "v"
        }) == "⌃⌥⌘V")
        // Same physical key, different current layout; no fixed ANSI character fallback.
        precondition(shortcut.displayString(translate: { _ in "." }) == "⌃⌥⌘.")
        let yPosition = HotKeyShortcut(keyCode: UInt16(kVK_ANSI_Y), flags: .command)
        precondition(yPosition.displayString(translate: { _ in "z" }) == "⌘Z") // German QWERTZ.
        precondition(yPosition.displayString(translate: { _ in "f" }) == "⌘F") // Dvorak.
        precondition(HotKeyShortcut(keyCode: 0, flags: [.control, .option, .shift, .command]).displayString(translate: { _ in "a" }) == "⌃⌥⇧⌘A")
        precondition(HotKeyShortcut(keyCode: UInt16(kVK_LeftArrow), flags: .command).displayString(translate: { _ in nil }) == "⌘←")
        precondition(shortcut.displayString(translate: { _ in nil }) == "⌃⌥⌘[9]")
    }

    private static func testPersistence() {
        let suite = "HotKeyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        precondition(HotKeyShortcut.load(from: defaults) == .standard)
        defaults.set(true, forKey: "overlayHotKeyEnabled") // Existing user, no stored shortcut.
        precondition(HotKeyShortcut.load(from: defaults) == .standard)
        let custom = HotKeyShortcut(keyCode: 0, flags: [.option, .shift])
        custom.save(to: defaults)
        precondition(HotKeyShortcut.load(from: UserDefaults(suiteName: suite)!) == custom)
        HotKeyShortcut(keyCode: 0, flags: .shift).save(to: defaults)
        precondition(HotKeyShortcut.load(from: defaults) == custom)
        defaults.set(["keyCode": -1, "modifiers": Int(cmdKey)], forKey: "overlayHotKey")
        precondition(HotKeyShortcut.load(from: defaults) == .standard)
        defaults.set(["keyCode": 0, "modifiers": Int(shiftKey)], forKey: "overlayHotKey")
        precondition(HotKeyShortcut.load(from: defaults) == .standard)
        defaults.set(["keyCode": 0], forKey: "overlayHotKey")
        precondition(HotKeyShortcut.load(from: defaults) == .standard)
        defaults.set(["keyCode": 128, "modifiers": Int(cmdKey)], forKey: "overlayHotKey")
        precondition(HotKeyShortcut.load(from: defaults) == .standard)
        defaults.set(["keyCode": 0, "modifiers": Int(cmdKey) | 1], forKey: "overlayHotKey")
        precondition(HotKeyShortcut.load(from: defaults) == .standard)
    }

    private static func testRegistration() {
        var registered: [Int: HotKeyShortcut] = [:]
        var nextID = 0
        var fail = false
        var failRemoval = false
        let state = HotKeyRegistration<Int>(register: { shortcut in
            if fail { return .failure(HotKeyFailure(status: -9878)) }
            nextID += 1
            registered[nextID] = shortcut
            return .success(nextID)
        }, unregister: { id in
            if failRemoval && id == 1 { return .failure(HotKeyFailure(status: -50)) }
            registered.removeValue(forKey: id)
            return .success(())
        })
        let old = HotKeyShortcut.standard
        let new = HotKeyShortcut(keyCode: 0, flags: .command)
        precondition(!state.isUnavailable, "An unattempted registration must not show a menu error")
        fail = true
        precondition(!state.apply(old, enabled: true))
        precondition(!state.isActive && state.failure != nil) // Startup failure: no checkmark.
        precondition(state.isUnavailable, "Startup failure must show the menu error")
        fail = false
        precondition(state.apply(old, enabled: true))
        precondition(state.isActive && state.failure == nil)
        precondition(!state.isUnavailable)
        let firstID = state.activeHandle!
        precondition(state.apply(old, enabled: true) && state.activeHandle == firstID)
        precondition(!state.apply(HotKeyShortcut(keyCode: 0, flags: .shift), enabled: true))
        precondition(registered == [firstID: old] && state.activeShortcut == old)
        fail = true
        precondition(!state.apply(new, enabled: true))
        precondition(registered == [firstID: old] && state.isActive && state.failure != nil)
        precondition(state.activeShortcut == old)
        // Reopening the menu only reads state; no successful apply should be needed.
        precondition(!state.isUnavailable, "A failed change must not label the working old shortcut as failed")
        precondition(state.failure?.status == -9878, "Keep the attempted change's error for diagnostics")
        fail = false
        failRemoval = true
        precondition(!state.apply(new, enabled: true))
        precondition(registered == [firstID: old] && state.activeShortcut == old)
        precondition(!state.isUnavailable && state.failure?.status == -50)
        failRemoval = false
        precondition(state.apply(new, enabled: true))
        precondition(registered.count == 1 && registered[state.activeHandle!] == new)
        precondition(state.activeShortcut == new && state.failure == nil)
        precondition(state.apply(new, enabled: false))
        precondition(registered.isEmpty && !state.isActive && state.failure == nil)
        precondition(!state.isUnavailable, "A disabled shortcut must not show a menu error")
        precondition(state.apply(new, enabled: true))
        precondition(state.activeShortcut == new && registered.count == 1)
        precondition(state.apply(new, enabled: false))
        precondition(state.apply(old, enabled: false)) // Changing while disabled never registers.
        precondition(registered.isEmpty)

        // Even a failed rollback cleanup must retain its handle for a later retry.
        var liveHandles = Set<Int>()
        var refuseRemoval = true
        var id = 0
        let cleanup = HotKeyRegistration<Int>(register: { _ in
            id += 1
            liveHandles.insert(id)
            return .success(id)
        }, unregister: { handle in
            if refuseRemoval { return .failure(HotKeyFailure(status: -50)) }
            liveHandles.remove(handle)
            return .success(())
        })
        precondition(cleanup.apply(old, enabled: true))
        precondition(!cleanup.apply(new, enabled: true))
        precondition(cleanup.activeShortcut == old && liveHandles == [1, 2])
        precondition(!cleanup.apply(new, enabled: false))
        precondition(liveHandles == [1, 2])
        refuseRemoval = false
        precondition(cleanup.apply(old, enabled: false))
        precondition(liveHandles.isEmpty && !cleanup.isActive)
    }
}
