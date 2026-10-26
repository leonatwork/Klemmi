import AppKit
import ServiceManagement

// Standalone precondition tests, run by build.sh on macOS; no login items are changed.
@main
enum LoginItemTests {
    static func main() {
        assertMenu(.notRegistered, checkmark: .off, action: .register)
        assertMenu(.enabled, checkmark: .on, action: .unregister)
        assertMenu(.requiresApproval, checkmark: .mixed, action: .openSettings)
        assertMenu(.notFound, checkmark: .off, action: .register)

        precondition(LoginItemPolicy.shouldAutoRegister(markerSet: false),
                     "A missing marker must trigger the first registration attempt")
        precondition(!LoginItemPolicy.shouldAutoRegister(markerSet: true),
                     "A completed attempt must never be retried, even after failure or manual removal")
    }

    private static func assertMenu(
        _ status: SMAppService.Status,
        checkmark: NSControl.StateValue,
        action: LoginItemPolicy.Action,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let menu = LoginItemPolicy.menuState(for: status)
        precondition(menu.checkmark == checkmark, "Incorrect checkmark for \(status)", file: file, line: line)
        precondition(menu.action == action, "Incorrect action for \(status)", file: file, line: line)
    }
}
