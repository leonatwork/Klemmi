# Issue #11 — Start at Login handover

## Scope and review limitations

Implemented against the supplied structured issue description (AC-1–AC-8).
It resolves the original opt-in question in favour of one automatic registration
attempt and supersedes the original AC numbering. The review-fix request explicitly
requires implementation despite the previously documented environment limitations.

- The unchanged checkout base is `d2963b980f033c0c5aa27f59c1bf2795f5e3410a`,
  equal to `origin/master` and `origin/HEAD`. There is no local `origin/main`;
  the original literal base requirement cannot be met here.
- Reading the complete issue thread and listing open PRs through `gh` was denied
  by tool permissions. Comments and current PR dependencies remain unverified.
  The knowledge-base query supplied repository context, not a complete thread.
- `CONTRIBUTING.md` and the local Build workflow were read. Neither `CLAUDE.md`
  nor `AGENTS.md` was found in the workspace.
- No other branch was checked out and no PR code was used. This implementation
  requires no changes from another PR; any universal-binary work is separate.

## Acceptance criteria and implementation evidence

All runtime outcomes below still require macOS verification.

| Criterion | Implementation / evidence |
| --- | --- |
| AC-1: register and checkmark | `LoginItem.perform` calls `SMAppService.mainApp.register()`. `LoginItemPolicy` maps `.enabled` to `.on` and `.notRegistered`/`.notFound` to `.off` with the register action. |
| AC-2: unregister and clear checkmark | `.enabled` selects `unregister()`. The menu rereads actual status after the action rather than toggling a saved value. |
| AC-3: external changes | `StatusItemController.showMenu` calls `updateLoginItem` on every menu creation. The click handler also reads fresh system status. |
| AC-4: approval required | `.requiresApproval` maps to `.mixed` and a localized title directing the user to System Settings. Its action calls `SMAppService.openSystemSettingsLoginItems()`. |
| AC-5: recoverable errors | Both throwing operations share a catch with localized `NSAlert` title/message and `NSLog` operation/domain/code. After dismissing the alert, the menu rereads system status. |
| AC-6: login without a window | The existing app startup creates the status item and starts monitoring without showing the overview or overlay. Registration adds no success dialog or window. `LSUIElement` and the existing Dock preference remain in use. Logout/login verification is pending. |
| AC-7: exactly one automatic attempt | `main.swift` calls `registerOnFirstLaunch`. `Settings.loginItemFirstLaunchCompleted` is persisted **before** attempting registration, including on failure. A set marker skips future attempts regardless of current system status. Existing installations without the marker receive one attempt. |
| AC-8: pure decisions tested | `Tests/LoginItemTests.swift` asserts checkmark and action for all four statuses and the decision for both marker values. It uses standalone `precondition` assertions and an `@main` entry point like the existing build-integrated tests. |

The four new UI keys exist in all ten localizations and are used through `L10n.tr`.
The alert uses AppKit's default localized OK button. Both READMEs describe the
feature, first-run behaviour, and approval state.

`build.sh` runs the new decision tests before app compilation and includes both
new source files. The existing Build workflow invokes this script. The screenshot
script includes the new files through its existing source glob; it excludes
`main.swift`, so rendering does not auto-register the harness or set the marker.
Both app and harness explicitly link ServiceManagement and compile for macOS 13.

## Verification performed

- **PASS:** `git diff --check`.
- **PASS:** `bash -n build.sh scripts/screenshots/render.sh scripts/check-localizations.sh`.
- **Static review:** four new keys in each of ten languages, matching source uses;
  all four status/action pairs and both marker decisions covered in the test source;
  startup marker written before registration and never used as menu state.
- **Not run:** Swift tests, app build, screenshot rendering, and manual macOS tests,
  per the Linux/no-Swift/AppKit execution restriction.
- **Not run:** `scripts/check-localizations.sh`; it needs macOS `osascript`/Foundation
  as well as `plutil`. Shell syntax validation is not a localization-check OK result.
- **TDD limitation:** tests and their build invocation were added before the policy
  or service implementation. Their missing implementation was inspected, but no
  failing test execution or subsequent passing execution is claimed. The required
  observed red/green evidence remains unavailable here.
- **CI:** no Build run was triggered or verified. Nothing was committed or pushed.

## Remaining macOS verification

Run the decision tests independently (they do not access real login items):

```bash
TEST_DIR="$(mktemp -d)"
swiftc -target "$(uname -m)-apple-macosx13.0" \
  Sources/LoginItemPolicy.swift Tests/LoginItemTests.swift \
  -framework AppKit -framework ServiceManagement -o "$TEST_DIR/LoginItemTests"
"$TEST_DIR/LoginItemTests"
```

Then run `scripts/check-localizations.sh`, `./build.sh --install` (which also runs
the existing history tests), and `scripts/screenshots/render.sh` on a test Mac.
Record the Build CI result once this patch is submitted for review.

1. From `/Applications/Klemmi.app`, disable and re-enable Start at Login; compare
   the checkmark with System Settings (AC-1/2).
2. Remove or disable Klemmi externally while it runs; reopen the menu. For
   `.requiresApproval`, verify the mixed mark and explanatory title; click it
   and approve in System Settings, then reopen the menu (AC-3/4).
3. Exercise register and unregister failures in a disposable debug build (a
   temporary injected throw is suitable). Verify localized alert, log, unchanged
   real status and continued operation; remove the fault injection (AC-5).
4. With registration enabled, log out and back in. Verify monitoring starts with
   a menu-bar icon and no overview/overlay window (AC-6).
5. Quit Klemmi, then reset **only** the first-attempt marker on the test Mac:
   `defaults delete de.local.klemmi loginItemFirstLaunchCompleted`.
   Launch, verify registration and marker value (`defaults read de.local.klemmi
   loginItemFirstLaunchCompleted`). Disable registration and relaunch: it must
   stay disabled. Repeat with a forced failure on the first register call; after
   removing the fault, relaunch with the marker retained and verify no automatic
   retry. Explicit registration through the menu must still work (AC-7).

This document replaces the previous `NOTES-BLOCKER.md` with implementation evidence
and outstanding verification. No commit, push, PR, merge, release or deployment
was performed.
