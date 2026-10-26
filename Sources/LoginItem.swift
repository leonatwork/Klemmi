import AppKit
import ServiceManagement

enum LoginItem {
    /// Nur der App-Einstieg ruft dies auf, nicht der Screenshot-Harness.
    static func registerOnFirstLaunch() {
        guard LoginItemPolicy.shouldAutoRegister(markerSet: Settings.loginItemFirstLaunchCompleted) else { return }
        // Vor dem Versuch speichern: Auch nach einem Fehler nicht automatisch erneut anmelden.
        Settings.loginItemFirstLaunchCompleted = true
        perform(.register)
    }

    static func perform(_ action: LoginItemPolicy.Action) {
        do {
            switch action {
            case .register:
                try SMAppService.mainApp.register()
            case .unregister:
                try SMAppService.mainApp.unregister()
            case .openSettings:
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            let nsError = error as NSError
            NSLog("Klemmi: login item %@ failed (%@, error %ld)",
                  String(describing: action), nsError.domain, nsError.code)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L10n.tr("loginItem.error.title")
            alert.informativeText = L10n.tr("loginItem.error.message")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}
