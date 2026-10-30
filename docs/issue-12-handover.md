# Issue #12 — configurable overlay shortcut

## Basis, rules and binding decisions

The clean initial checkout equals `origin/master` at
`d631c6e479993194c7e76ddd9b439d6de01070e0`. `origin/HEAD` also points to
`origin/master`; there is no local or remote-tracking `main`. The request's
literal `origin/main` prerequisite cannot be met in this checkout. Work uses
only the existing default-branch snapshot, as identified in the supplied
repository context. No branches were created or checked out and no foreign PR
code was used.

Read `CONTRIBUTING.md`, the existing implementation, build workflow, standalone
test conventions and localization checker. `CLAUDE.md` and `AGENTS.md` are absent
from the workspace. GitHub issue/comment and open-PR queries were denied by tool
permissions. The full live thread, PR status and remote freshness are therefore
**unverified**; the supplied structured issue and owner decisions establish the
implementation scope. There is no code dependency on an open PR: main menus,
the existing overlay and Settings are already on this baseline.

Binding decisions supersede the preserved original description:

- Default: **⌃⌥⌘V**, replacing both ⌘⇧C and the earlier proposed ⌘⇧V.
- Every user without a stored shortcut receives that default; no ⌘⇧C migration.
- A modal recorder opens from **Change Shortcut…** in the right-click menu.
- Carbon remains the registration API, without Accessibility permission.
- `menu.overlayHotKey` retains its `%@` placeholder.

## Implementation and acceptance review

| Criterion | Implementation and evidence |
| --- | --- |
| AC-1 | `HotKeyRegistration` acquires the new registration, removes the old one and only then commits its active handle. `OverlayHotKey.change` saves only on success. Carbon events are filtered by signature and the current registration ID, including queued events from an old registration. Fake registry tests assert exactly one new shortcut remains. Actual overlay activation needs macOS. |
| AC-2 | Settings stores a single `overlayHotKey` dictionary with key code and Carbon modifiers. Missing, incomplete or invalid values fall back to ⌃⌥⌘V. Isolated UserDefaults tests cover reload, existing enabled users without a stored value and invalid data. Actual process restart needs macOS. |
| AC-3 | Recorder validation requires ⌘, ⌃ or ⌥; no modifiers, Shift-only and irrelevant flags are rejected without closing the dialog. Invalid changes do not touch the active registration or saved preference. Tests cover validation, exact modifier conversion and preservation. |
| AC-4 | Failed new registration preserves the old handle and preference; a localized warning appears. Fake registry tests cover collisions, old-registration removal failure and retrying failed cleanup. See the ordering clarification below. The system collision/dialog scenario needs macOS. |
| AC-5 | `apply()` returns success; actual registration state is exposed. The menu checkmark uses `isActive`, and a localized “Registration Failed” suffix uses `isUnavailable` (failure with no active handle). Failed changes retain diagnostics and show the localized warning, but do not label the still-working old shortcut as failed. Tests cover failed startup, recovery, disabled state and active old registration after registration/removal failure. |
| AC-6 | Disabling removes registration without changing the saved shortcut. Enabling reads the same preference. Fake registry tests cover disable/re-enable and changing while disabled. |
| AC-7 | Menu construction reads `TISCopyCurrentKeyboardLayoutInputSource` and uses `UCKeyTranslate` without modifier transformations or dead-key state. Layout-data lifetime is retained. Pure display tests cover German QWERTZ and Dvorak labels, glyphs, modifier order and missing layout data. Without a translation, the numeric key position is shown instead of an invented ANSI letter. Real layout switching needs macOS. |
| AC-8 | Seven new keys exist in each of the ten localizations, with matching `%@` placeholders, and every new key is used through `L10n.tr`. Static key-count/search checks passed. The required `scripts/check-localizations.sh` OK result is **pending** because the checker requires macOS `osascript`/Foundation and Apple `plutil`. |

### Registration ordering clarification

The scope text says to unregister the old shortcut before registering the new
one, while AC-4 requires the old one to remain active if registration fails.
Releasing it first would require another registration that can itself fail or
lose the shortcut to another process. This implementation **registers the new
shortcut first, then unregisters the old**. A registration failure leaves the
old registration untouched. On a removal failure, the candidate is removed
again and the old remains selected; failed candidate cleanup retains its handle
for retry. Only the committed ID can invoke the overlay. The operation-order
wording is not followed literally; the observable AC-1/AC-4 behavior takes
precedence.

### Recorder and documentation

Esc cancels without changes; Backspace resets to the layout-labelled default.
Valid input is applied immediately when the dialog ends. Key events are consumed
before application commands can act on them, repeats are ignored, and the monitor
is removed on every exit. The currently registered Klemmi shortcut is routed to
the recorder rather than opening the overlay, so recording it needs no temporary
unregistration. Disabling the shortcut does not prevent recording a new preference.
Localized errors do not claim to detect other apps' internal keyboard commands.

Both READMEs explain configuration, persistence, registration state and the new
default, and remove the fixed-shortcut limitation. Existing overlay screenshot
pixels need no regeneration: the overlay layout is unchanged; captions and the
harness comment no longer mention the old shortcut.

## Tests and checks

`Tests/HotKeyTests.swift` was added **before** implementation, following the
standalone `precondition` convention with `@main` as used by DirectPaste tests.
`build.sh` runs it before app compilation; the existing **Build** CI workflow
runs `build.sh`. The history-persistence compile also includes the new Settings
type dependency. Screenshot compilation already includes every source except
`main.swift`.

Per the explicit Linux restriction, no application build, Swift test executable,
localization script or screenshot renderer was run. There is **no observed
pre-fix red run, post-fix green run, compiler result or green CI result**. On the
original snapshot the new test's policy types do not exist; that expected compile
failure is not a behavioral regression result. Behavioral red/green evidence
must still be obtained on macOS with a compiling faulty implementation or an
appropriate isolated baseline adapter.

Checks actually performed:

- `git diff --check`: passed.
- `bash -n build.sh` and `bash -n scripts/check-localizations.sh`: passed.
- Static resource search: exactly seven new definitions in each of ten languages;
  all seven keys are referenced in source, and placeholder signatures match.
- Manual source/diff review of all acceptance criteria, source-list integration,
  Carbon result handling and modal monitor cleanup.

No commits, pushes, PRs, releases, deployments or production-data changes were made.

### Focused review correction: active shortcut after a failed change

The review found that the menu interpreted the last operation's `failure` as
failure of the displayed, saved shortcut. `HotKeyRegistration.isUnavailable`
now separates these states: only a failure **without an active registration**
adds the existing localized menu suffix. `OverlayHotKey` exposes this property
and the status menu consumes it. The failed attempt's error remains available
for logging and the existing localized alert; registration and persistence
behavior are unchanged.

Regression assertions were added before the fix to the existing fake-registry
suite. They cover initial state, startup failure, recovery, failed replacement,
failed old-handle removal and disabling. No Swift execution is allowed on this
Linux server, so this correction has **no observed red/green test result**.
For behavioral red evidence on macOS, use an isolated copy of the corrected
policy and tests and change only `isUnavailable` to `failure != nil` (the faulty
menu decision). The failed-replacement assertion must fail; with the corrected
decision the complete suite must pass. Both runs remain outstanding.

Correction checks completed: `git diff --check` and
`bash -n build.sh scripts/check-localizations.sh` passed. Source inspection
confirmed the menu uses the tested decision and the focused suite remains
included in `build.sh`, which the Build workflow invokes.

## macOS handover / outstanding evidence

1. Run the focused suite:
   ```bash
   swiftc -target "$(uname -m)-apple-macosx13.0" \
     Sources/HotKeyPolicy.swift Tests/HotKeyTests.swift \
     -framework AppKit -framework Carbon -o /tmp/HotKeyTests
   /tmp/HotKeyTests
   ```
   Obtain the missing pre-fix behavioral red result separately; do not treat
   missing symbols or the Linux execution restriction as a successful TDD proof.
2. Run `scripts/check-localizations.sh` and record its **OK** result.
3. Run `./build.sh` warning-free and obtain a green **Build** CI run when this
   work is submitted. Do not merge or deploy as part of this handover.
4. On a test Mac, verify the unsaved default; change the shortcut and confirm
   only the new one opens the overlay; restart and confirm persistence; disable
   and re-enable; change while disabled; cancel with Esc and reset with ⌫.
5. Try no modifiers and Shift-only: show validation feedback, keep the dialog
   open and leave the old shortcut active. Try the current Klemmi shortcut in
   the recorder. Confirm recording ⌘Q does not quit and Return alone is rejected.
6. With a test helper or second instance holding a global shortcut, record that
   shortcut (or use ⌫ to request the occupied default): verify localized failure,
   saved preference preservation and the old shortcut still opening the overlay.
   Another app may consume its globally registered key before the recorder
   receives it; resetting to an occupied default provides a deterministic UI
   collision path. Restart with the saved shortcut occupied: no checkmark,
   visible registration-error suffix. Release the collision and re-enable.
7. In Chrome, verify ⌘⇧C is available after switching away from it. In a text
   editor, verify Paste and Match Style / Paste without Formatting is available
   while ⌃⌥⌘V opens Klemmi.
8. Switch between German and Dvorak, reopen the menu and verify the label follows
   the same physical key. Exercise a dead key, arrow and function key shortcut
   and verify no new Accessibility prompt for the overlay shortcut.
