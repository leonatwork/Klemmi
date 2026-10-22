import AppKit

// Run on macOS, without a test target (do not compile Sources/Localization.swift):
// swiftc Sources/MainMenu.swift Tests/MainMenuTests.swift -framework AppKit -o /tmp/MainMenuTests && /tmp/MainMenuTests

// A distinctive translation makes hard-coded titles fail, even when the test
// executable has no bundled localizations. Production uses Sources/Localization.swift.
enum L10n {
    static func tr(_ key: String) -> String { "localized<\(key)>" }
}

private struct ExpectedItem {
    let titleKey: String
    let action: String
    let key: String
    let modifiers: NSEvent.ModifierFlags

    init(_ titleKey: String, _ action: String, _ key: String = "",
         _ modifiers: NSEvent.ModifierFlags = .command) {
        self.titleKey = titleKey
        self.action = action
        self.key = key
        self.modifiers = modifiers
    }
}

private func assertMenu(_ item: NSMenuItem, titleKey: String, entries: [ExpectedItem?]) {
    precondition(item.title == L10n.tr(titleKey), "unlocalized top-level title: \(titleKey)")
    precondition(item.action == nil && item.keyEquivalent.isEmpty)
    guard let menu = item.submenu else { preconditionFailure("missing submenu: \(titleKey)") }
    precondition(menu.title == L10n.tr(titleKey), "unlocalized submenu: \(titleKey)")
    precondition(menu.autoenablesItems, "AppKit must validate the responder-chain actions")
    precondition(menu.items.count == entries.count, "unexpected items in \(titleKey)")

    for (actual, expected) in zip(menu.items, entries) {
        guard let expected else {
            precondition(actual.isSeparatorItem, "missing separator in \(titleKey)")
            continue
        }
        precondition(!actual.isSeparatorItem)
        precondition(actual.title == L10n.tr(expected.titleKey), "unlocalized title: \(expected.titleKey)")
        precondition(actual.action == NSSelectorFromString(expected.action), "wrong action: \(expected.titleKey)")
        precondition(actual.target == nil, "action must use the responder chain: \(expected.titleKey)")
        precondition(actual.keyEquivalent == expected.key, "wrong shortcut: \(expected.titleKey)")
        precondition(actual.keyEquivalentModifierMask == expected.modifiers, "wrong modifiers: \(expected.titleKey)")
        precondition(actual.submenu == nil)
    }
}

private func runMainMenuTests() {
    let menu = MainMenu.make()
    precondition(menu.items.count == 3, "expected App, Edit and Window menus")
    assertMenu(menu.items[0], titleKey: "menu.app", entries: [
        ExpectedItem("menu.about", "orderFrontStandardAboutPanel:"),
        nil,
        ExpectedItem("menu.hide", "hide:", "h"),
        ExpectedItem("menu.hideOthers", "hideOtherApplications:", "h", [.option, .command]),
        ExpectedItem("menu.showAll", "unhideAllApplications:"),
        nil,
        ExpectedItem("menu.quit", "terminate:", "q"),
    ])
    assertMenu(menu.items[1], titleKey: "menu.edit", entries: [
        ExpectedItem("menu.undo", "undo:", "z"),
        ExpectedItem("menu.redo", "redo:", "z", [.shift, .command]),
        nil,
        ExpectedItem("menu.cut", "cut:", "x"),
        ExpectedItem("menu.copy", "copy:", "c"),
        ExpectedItem("menu.paste", "paste:", "v"),
        ExpectedItem("list.delete", "delete:"),
        ExpectedItem("menu.selectAll", "selectAll:", "a"),
    ])
    assertMenu(menu.items[2], titleKey: "menu.window", entries: [
        ExpectedItem("menu.minimize", "performMiniaturize:", "m"),
        ExpectedItem("menu.zoom", "performZoom:"),
        nil,
        ExpectedItem("menu.close", "performClose:", "w"),
    ])
    precondition(NSApp.windowsMenu === menu.items[2].submenu, "Window menu must be registered with AppKit")

    // No menu shortcut may capture the overlay's arrows, Return or Escape, or
    // the existing global overlay hotkey (Shift-Command-C).
    let commands = menu.items.flatMap { $0.submenu!.items }.filter { !$0.keyEquivalent.isEmpty }
    let navigationKeys = ["\u{f700}", "\u{f701}", "\r", "\n", "\u{3}", "\u{1b}"]
    precondition(commands.allSatisfy { !navigationKeys.contains($0.keyEquivalent) })
    precondition(!commands.contains { $0.keyEquivalent == "c" && $0.keyEquivalentModifierMask == [.shift, .command] })
    for (index, command) in commands.enumerated() {
        precondition(!commands.dropFirst(index + 1).contains {
            $0.keyEquivalent == command.keyEquivalent && $0.keyEquivalentModifierMask == command.keyEquivalentModifierMask
        }, "duplicate shortcut: \(command.keyEquivalent)")
    }
}

@main
private enum MainMenuTests {
    static func main() {
        _ = NSApplication.shared
        runMainMenuTests()
        print("MainMenuTests: OK")
    }
}
