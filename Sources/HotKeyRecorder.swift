import AppKit

/// Modaler Recorder aus dem Rechtsklick-Menü; keine globalen Event-Taps/Berechtigungen.
enum HotKeyRecorder {
    static func record() -> HotKeyShortcut? {
        let alert = NSAlert()
        alert.messageText = L10n.tr("hotKey.recorder.title")
        alert.informativeText = L10n.tr("hotKey.recorder.message", HotKeyShortcut.standard.displayString(translate: OverlayHotKey.label))
        alert.addButton(withTitle: L10n.tr("directPaste.permission.cancel"))
        alert.buttons.first?.keyEquivalent = "\u{1b}"
        let feedback = NSTextField(wrappingLabelWithString: OverlayHotKey.displayString)
        feedback.frame = NSRect(x: 0, y: 0, width: 360, height: 52)
        feedback.setAccessibilityLabel(L10n.tr("hotKey.recorder.title"))
        alert.accessoryView = feedback
        var selected: HotKeyShortcut?
        var finished = false
        func accept(_ shortcut: HotKeyShortcut) {
            guard !finished else { return }
            selected = shortcut
            finished = true
            NSApp.stopModal(withCode: .alertSecondButtonReturn)
        }
        let hotKey = OverlayHotKey.shared
        hotKey.onRecordingShortcut = { accept($0) }
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !finished, NSApp.modalWindow === alert.window else { return event }
            guard !event.isARepeat else { return nil }
            switch HotKeyPolicy.record(keyCode: event.keyCode, flags: event.modifierFlags) {
            case .cancel:
                finished = true
                NSApp.stopModal(withCode: .alertFirstButtonReturn)
            case .invalid:
                feedback.stringValue = L10n.tr("hotKey.recorder.invalid")
            case .shortcut(let shortcut):
                accept(shortcut)
            }
            return nil // Kein Durchreichen an ⌘Q, Edit-Menü oder Standardknöpfe.
        }
        defer {
            if let monitor { NSEvent.removeMonitor(monitor) }
            hotKey.onRecordingShortcut = nil
        }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        return response == .alertSecondButtonReturn ? selected : nil
    }
}
