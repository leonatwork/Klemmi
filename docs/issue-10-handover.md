# Issue #10 — implementation handover

Issue: https://github.com/leonatwork/Klemmi/issues/10

## Base and review context

Implemented on the existing checkout at
`01db226485d1a96419cd929a2938294e8c46314e`, identical to `origin/master`.
`origin/HEAD` points to `origin/master`; the follow-up task explicitly confirms
that this is the intended standard-branch base. The earlier `NOTES-BLOCKER.md`
has been corrected and moved here. No other PR branch was used.

`CONTRIBUTING.md`, the existing Build workflow and relevant sources were read.
Neither `CLAUDE.md` nor `AGENTS.md` exists in this checkout. The knowledge base
confirms the dependency-free AppKit architecture and localization conventions.
GitHub access through `gh` is prohibited by this session's tool policy, so issue
comments and open PRs remain unreviewed. The implementation is self-contained
on the checked-out base; possible overlap with open PRs remains unverified.

## Acceptance criteria and implementation

The supplied structured issue body is the acceptance contract. All actions use
standard AppKit selectors and nil targets for responder-chain dispatch.

| Criterion | Implementation / regression coverage | Pending macOS acceptance |
| --- | --- | --- |
| AC-1: Command-V/C/X/A edit search text in all three views | Edit menu has `paste:`, `copy:`, `cut:`, `selectAll:` with the specified shortcuts. Tests assert selectors, targets and modifiers. | Exercise overview, popover and overlay search fields in accessory and Dock modes. |
| AC-2: Command-Z / Shift-Command-Z undo / redo search input | Edit menu has `undo:` / `redo:` with distinct modifiers, asserted by tests. | Type, undo and redo in each search field in both modes. |
| AC-3: Command-W closes and Command-M minimizes the overview | Window menu has `performClose:` / `performMiniaturize:`; menu is registered as `NSApp.windowsMenu`. Tests cover both. | Close and minimize the overview while it is key, in both modes. |
| AC-4: Localized App, Edit, Window menus in Dock mode | `Sources/main.swift` installs `MainMenu.make()` at startup for either activation policy. Tests check the three menus. | Inspect the active app's menu bar and toggle Dock mode. |
| AC-5: All titles localized in ten languages | All titles go through `L10n.tr`. Sixteen new keys per language; `menu.quit` and `list.delete` reused. A test-only translation sentinel detects literal titles. | Localization script must report OK; inspect German and English menus. |
| AC-6: Overlay arrows, Return and Escape retain their behavior | Existing navigation code is untouched. Tests ensure no menu shortcut captures these keys or Shift-Command-C. | Exercise selection, activation, Escape with a query and Escape with an empty query. |
| AC-7: Command-Q quits, including overlay focus | App menu has `terminate:` with Command-Q through the responder chain, asserted by tests. | Quit from each focused search field, especially the nonactivating overlay. |

The new source is listed in `build.sh`. The existing macOS Build workflow now
runs `MainMenuTests` and the localization check before building the app.

Interpretation of the issue's apparent conflicts:

- The structured decision that Command-Q always quits with overlay focus
  supersedes the original description's unresolved question.
- AC-3 applies to the overview, despite the broad manual-QS wording about all
  three search fields. Command-W in the overlay is explicitly out of scope;
  Escape remains its dismissal key.
- Settings, new product actions and status-item context-menu changes are excluded.

## Verification and remaining evidence

`Tests/MainMenuTests.swift` was written before the implementation, using the
repository's standalone `precondition` style. Before the fix, source inspection
found neither a main-menu implementation/installation nor the new localization
keys. This is **not an executed failing regression test**. An observed red/green
TDD result could not be obtained: this Linux session has no Swift/AppKit or
`osascript`, and the task explicitly prohibits build/application/test execution
here. No macOS tests, localization script, CI run or manual reproduction ran.

Completed static checks: `git diff --check` passed; each of the ten localization
files contains all sixteen new keys; the production diff was reviewed against
AC-1 through AC-7. These checks do not establish runtime acceptance.

Run from the repository root on macOS:

```bash
swiftc Sources/MainMenu.swift Tests/MainMenuTests.swift -framework AppKit -o /tmp/MainMenuTests
/tmp/MainMenuTests
scripts/check-localizations.sh
./build.sh
```

The test intentionally substitutes `L10n` to detect untranslated titles; do not
include `Sources/Localization.swift` in that test compilation. It checks menu
construction, not live field-editor behavior. Complete the manual matrix above
in both activation modes, including About, Hide, Hide Others, Show All and Zoom.
Confirm the original paste failure separately on the base version, using only
disposable sample text. Runtime key-equivalent handling in the nonactivating
overlay is an explicit outstanding check, not a proven result.

No commit, push, PR creation, merge, release or deployment was performed.
