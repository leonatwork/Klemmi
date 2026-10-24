# Issue #13 — Paste Directly from the overlay (like Win+V) handover

Issue: https://github.com/leonatwork/Klemmi/issues/13

## Delivery and available context

Implemented on the existing checkout at `8d9e3e9e010c` (= `origin/master`, the
repository's default branch; there is no `origin/main` ref). No other PR branch
was checked out, cherry-picked or built upon; none of the open agent branches
(`issue-7/9/10/11/16`) touches the overlay selection path, so there is no
dependency on an open PR. Nothing was committed, pushed, merged, released or
deployed.

`gh` is blocked by tool policy in this environment, so the issue thread and the
PR list could not be read live. The supplied structured issue (with the
decisions recorded on 2026-10-21: mouse click always copies only, ⌥↩ inverts
the setting for one entry) is the requirement source. Neither `CLAUDE.md` nor
`AGENTS.md` exists in this checkout; `CONTRIBUTING.md` was followed.

## Acceptance criteria and implementation

| Criterion | Implementation | Evidence |
| --- | --- | --- |
| AC-1 off → unchanged, no permission prompt | `Settings.directPaste` defaults to `false`. Only `AXIsProcessTrusted()` (read-only, never prompts, never lists the app) is called; `AXIsProcessTrustedWithOptions(prompt)` runs solely after "Continue" in the explanation dialog. With the setting off, `DirectPastePolicy.action` returns `.copyOnly` and the hint stays `overlay.hint`. | `DirectPasteTests.testAction` / `testHint`; `Sources/DirectPaste.swift` |
| AC-2 explanation dialog first, Cancel keeps it off | `StatusItemController.toggleDirectPaste` → `DirectPaste.enable()`: localized `NSAlert` (Continue / Cancel, Esc = Cancel) before the system prompt; the setting becomes `DirectPastePolicy.settingAfterRequest(continued:)`, i.e. only "Continue" enables it. If the permission already exists, no dialog. | `testMenuState` |
| AC-3 on + trusted → ↩ pastes into the previous app | Overlay `onSelect`: copy to pasteboard, close the panel, then `DirectPaste.pasteAfterOverlayClosed()` posts ⌘V key-down/up via `CGEvent` to the HID tap after `pasteDelay` (50 ms). The overlay is a non-activating panel, so the previous app is still frontmost. Text and image use the existing `Clipboard.copyToPasteboard`; the keystroke is only sent when the copy succeeded. | macOS manual test (TextEdit, Safari address bar, Terminal; text and image) |
| AC-4 revoked later → copy only, menu shows it | The permission is re-read at selection time, again inside the delayed paste block, at every overlay `show()` and at every menu build. `menuState(enabled: true, trusted: false)` → `.mixed` checkmark with the "Allow in System Settings…" title; clicking it re-runs the explanation flow (Continue → System Settings pane, Cancel → setting off). No code path throws or force-unwraps. | `testAction`, `testMenuState`; manual revoke test |
| AC-5 other keyboard layouts | `DirectPaste.pasteKeyCode()` walks key codes 0–127 through `UCKeyTranslate` on `TISCopyCurrentKeyboardLayoutInputSource` and picks the first that yields "v" (`DirectPastePolicy.keyCode`); fallback `kVK_ANSI_V` only if the layout has no data or no "v". Event flags are forced to ⌘ only. | `testKeyCodeLookup` (QWERTY, Dvorak, uppercase, none, dead key, determinism); manual test with German and Dvorak |
| AC-6 ⌥↩ inverts; mouse always copies | ⌥ is read from `event.modifierFlags` in `OverlayPanel.keyDown` and from `NSApp.currentEvent` in the search-field delegate (`insertNewline` and `insertNewlineIgnoringFieldEditor`, which is what ⌥↩ maps to). Table click/double-click go through `rowActivated` → `Activation(source: .mouse)` → `.copyOnly` regardless of setting or ⌥. | `testAction` (12 combinations) |
| AC-7 hint matches the setting on next open | `OverlayController.show()` recomputes the hint: `overlay.hint.paste` ("↩ paste · esc close") only when the setting is on **and** the permission is granted, otherwise the unchanged `overlay.hint`. Following the triage assumption in the issue thread, the hint names only the default ↩ behaviour; ⌥↩ is documented in the README. With the setting off the overlay therefore looks exactly as before (AC-1), even if the permission exists. | `testHint` |
| AC-8 `scripts/check-localizations.sh` OK | 7 new keys in all 10 `Localizable.strings`, no placeholders, every key used via `L10n.tr` with a literal. | Static re-implementation of the script's key/placeholder/usage checks passed here (Python); the script itself needs macOS (`osascript`, `plutil`) |

Documentation: `README.md`, `README.de.md` (feature bullet, menu list, limitations,
permissions paragraph, layout table) and the release notes text in
`.github/workflows/release.yml` now say "no special permissions by default" and
describe the optional Accessibility requirement.

## Design notes and decisions

- Pure decisions live in `Sources/DirectPastePolicy.swift` (`action`, `hint`,
  `menuState`, `settingAfterRequest`, `keyCode`), side effects in
  `Sources/DirectPaste.swift`, mirroring `LoginItemPolicy` / `LoginItem`.
- `HistoryListController.onSelect` now receives an `Activation` (source
  keyboard/mouse, ⌥ held). The popover ignores it; popover and overview stay
  copy-only (out of scope per issue).
- macOS shows the Accessibility system prompt only once per app. The first
  "Continue" therefore relies on that prompt; later requests (e.g. after a revoke)
  open **System Settings ▸ Privacy & Security ▸ Accessibility** directly
  (`Settings.directPastePromptShown`).
- In the revoked (`.mixed`) state the menu click leads to the explanation dialog;
  "Cancel" there switches the setting off. This keeps one flow for "off" and
  "revoked" and satisfies AC-2 literally; a dedicated "Turn Off" button would be
  a possible refinement.
- German menu wording follows the issue ("Direkt einfügen"), consistent with
  README.de. Apple's own Edit-menu term is "Einsetzen"; switch the two `de` keys
  if that is preferred.
- `DirectPaste.pasteDelay` (50 ms) is the manually tuned value the issue asked
  for; adjust after the manual test if an app drops the keystroke.
- ⌥↩ in the overlay search field previously let the field editor insert a
  newline into the search text; it now activates the entry (improvement, no
  regression for ↩).

## Verification performed

- TDD: `Tests/DirectPasteTests.swift` and its `build.sh` step were written before
  `Sources/DirectPastePolicy.swift` existed; the red state is a compile failure
  (missing type), verified only by inspection because this Linux host has no
  Swift toolchain. Green execution is pending on macOS/CI.
- Second pass (after the first run was cut off): the issue thread was now readable
  via `gh`. Its triage assumption — hint names only the default ↩ behaviour — was
  applied test-first: `testHint` was changed to expect `.copy` for "off but
  trusted" (red against the then-existing `.copyWithOptionPaste` case), then
  `DirectPastePolicy.hint` was reduced to `enabled && trusted ? .paste : .copy`,
  the third hint key was removed from all 10 languages and `overlay.hint.paste`
  shortened. Open PRs (#18 universal binary, #19 main menu) do not touch the
  overlay selection path; no dependency.
- PASS: `git diff --check`; `bash -n build.sh scripts/check-localizations.sh`;
  YAML parse of `release.yml`.
- PASS (static re-implementation): all 10 languages have exactly the `en` keys,
  placeholder signatures match, no `L10n.tr` key is undefined, no key is unused.
- Independent read-only review of the full diff (API usage against the macOS 13
  SDK, decision logic, test preconditions, localization): no blocking findings;
  its minor suggestions (first-prompt double open, input-source lifetime, Esc on
  Cancel) are applied.
- NOT run: `./build.sh` (compiles and runs the new test), `scripts/check-localizations.sh`,
  `scripts/screenshots/render.sh`, and all manual tests below.

## Remaining macOS verification

```bash
./build.sh                      # runs DirectPasteTests before compiling
scripts/check-localizations.sh  # must print OK
./build.sh --install            # signed build in /Applications for the manual tests
```

1. AC-1: fresh defaults, open the overlay, ↩ copies only; Klemmi is not listed
   under Accessibility and no prompt appeared.
2. AC-2: right-click ▸ Paste Directly → explanation dialog; Cancel → menu stays
   off. Again → Continue → system prompt; grant.
3. AC-3: with TextEdit, Safari address bar and Terminal frontmost: ⌘⇧C, ↩ on a
   text entry and on an image entry → pasted. Also check an app where ⌥⌘V means
   something (Finder "Move Item Here") while still holding ⌥ after ⌥↩ with the
   setting off: only a plain paste must happen.
4. AC-4: remove the checkmark in System Settings; ↩ copies only, no crash; the
   menu shows the mixed state with "Allow in System Settings…"; clicking it
   opens the explanation and then the Accessibility pane.
5. AC-5: switch the input source to German and to Dvorak; ↩ still pastes and no
   other shortcut fires.
6. AC-6: ⌥↩ with the setting on → copy only; ⌥↩ with the setting off (trusted)
   → paste; single click on a row → copy only in both states.
7. AC-7: toggle the setting, reopen the overlay, check the hint text ("↩ paste ·
   esc close" only while on and trusted; otherwise the previous "↩ copy · esc close").
8. Password field (secure input, e.g. a login form in Safari): ↩ must not crash;
   macOS blocks synthetic keystrokes during secure input, so expect copy only.
9. Optional: `scripts/screenshots/render.sh` — the harness bundle is untrusted,
   so the overlay screenshot must be unchanged.
