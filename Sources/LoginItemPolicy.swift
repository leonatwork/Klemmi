import AppKit
import ServiceManagement

/// Reine Entscheidungen, ohne Anmeldeobjekte oder Einstellungen zu verändern.
enum LoginItemPolicy {
    enum Action: Equatable {
        case register, unregister, openSettings
    }

    struct MenuState {
        let checkmark: NSControl.StateValue
        let action: Action
    }

    static func menuState(for status: SMAppService.Status) -> MenuState {
        switch status {
        case .notRegistered, .notFound:
            return MenuState(checkmark: .off, action: .register)
        case .enabled:
            return MenuState(checkmark: .on, action: .unregister)
        case .requiresApproval:
            return MenuState(checkmark: .mixed, action: .openSettings)
        @unknown default:
            return MenuState(checkmark: .mixed, action: .openSettings)
        }
    }

    static func shouldAutoRegister(markerSet: Bool) -> Bool {
        !markerSet
    }
}
