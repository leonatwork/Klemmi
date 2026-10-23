import AppKit

/// Standardmenüs und Tastenkürzel für Dock- und Accessory-Modus.
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()

        let app = submenu(title: L10n.tr("menu.app"), in: main)
        app.addItem(withTitle: L10n.tr("menu.about"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: L10n.tr("menu.hide"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = app.addItem(withTitle: L10n.tr("menu.hideOthers"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.option, .command]
        app.addItem(withTitle: L10n.tr("menu.showAll"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: L10n.tr("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let edit = submenu(title: L10n.tr("menu.edit"), in: main)
        // Undo/Redo sind Standardaktionen der Responder-Kette, aber keine
        // als Swift-Methoden deklarierten Aktionen von NSResponder.
        edit.addItem(withTitle: L10n.tr("menu.undo"), action: NSSelectorFromString("undo:"), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: L10n.tr("menu.redo"), action: NSSelectorFromString("redo:"), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.shift, .command]
        edit.addItem(.separator())
        edit.addItem(withTitle: L10n.tr("menu.cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L10n.tr("menu.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L10n.tr("menu.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L10n.tr("list.delete"), action: #selector(NSText.delete(_:)), keyEquivalent: "")
        edit.addItem(withTitle: L10n.tr("menu.selectAll"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let window = submenu(title: L10n.tr("menu.window"), in: main)
        window.addItem(withTitle: L10n.tr("menu.minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: L10n.tr("menu.zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(.separator())
        window.addItem(withTitle: L10n.tr("menu.close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.windowsMenu = window

        // Alle Targets bleiben nil: AppKit findet den jeweiligen First Responder,
        // das Key-Window oder NSApplication (auch terminate: bei Overlay-Fokus).
        return main
    }

    private static func submenu(title: String, in main: NSMenu) -> NSMenu {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        item.submenu = menu
        main.addItem(item)
        return menu
    }
}
