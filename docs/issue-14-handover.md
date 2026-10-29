# Issue #14 — privacy package 1 handover

Issue: https://github.com/leonatwork/Klemmi/issues/14

## Basis, scope and unavailable context

The existing checkout started clean at
`7700cd06fb26933eabc7610e40148a7315f08b27`, exactly matching
`origin/master` and `origin/HEAD`. There is no `origin/main` ref in this
repository checkout. The instruction to use `origin/main` cannot be met
literally; implementation uses the checked-out default-branch commit instead.
No branches were created or checked out and no foreign PR commits were used.

GitHub issue/comment and open-PR queries were denied by tool permissions.
Consequently, the complete live thread and current PR list remain **unverified**;
the supplied structured issue is the acceptance source. Review those before
opening the eventual PR. The implementation is self-contained on the starting
commit and has no identified code dependency on an open PR.

Read `CONTRIBUTING.md`, the current sources, test conventions, `build.sh`, the
Build workflow and localization checker. Neither `CLAUDE.md` nor `AGENTS.md`
exists in the workspace.

The structured **package 1** scope supersedes the broader title and preserved
original description: binding criteria are AC-1, AC-2, AC-3, AC-6, AC-8, AC-9
and AC-10. Original AC-4/5 (age-based deletion) belong to package 2; original
AC-7 (exclusion-list UI) and README changes belong to package 3. They are not
unfinished package-1 criteria. Encryption, a settings window and pinning remain
out of scope. The original suggestion of testing expiry selection therefore
does not apply to this package.

## Acceptance review

| AC | Implementation and tests | Evidence status |
| --- | --- | --- |
| AC-1 | `Settings.excludedAppBundleIDs` persists a list, defaulting to exactly `com.apple.keychainaccess` and `com.apple.Passwords`. Explicit `[]` remains empty. `ClipboardMonitor.poll()` checks the sampled frontmost bundle ID before reading content or enqueueing writes. `CapturePolicyTests` covers defaults/custom/empty lists; `HistoryPersistenceTests.capturePrivacy` checks rejected text and images and immediate list changes. | Code reviewed; macOS execution pending. |
| AC-2 | All six marker strings live in `CapturePolicy.sensitiveMarkers`. The existing `ignoreConcealed` switch gates all six, not app exclusion or pause. Unit expectations enumerate the six strings independently. Integration tests reject text/images for each marker and admit text for each with the switch off. | Code reviewed; macOS execution pending. |
| AC-3 | Session-only `isRecordingPaused`, checkmarked localized right-click item, clipboard icon with two pause bars, localized tooltip/accessibility label. Timer stays active; change counts and self-copy tracking advance before the policy rejects content. Resume polls once **while still paused**, discarding copies after the last timer tick. Integration tests cover polled/unpolled paused copies, images, termination polling, resume and a fresh monitor; a no-op resume must not swallow a legitimate change. | State logic reviewed; macOS tests and visual/restart checks pending. |
| AC-6 | Store initialization creates and chmods the base folder before `Images/`, both to `0700`, before loading. Existing folders are repaired explicitly. Permission/setup failure is logged and disables disk saving. `privateDirectories` checks fresh/existing directories, unchanged parent permissions and preserved synthetic bytes. | Code reviewed; filesystem tests pending. |
| AC-8 | Two new keys (`menu.pauseRecording`, `statusItem.tooltip.paused`) in all ten languages, without placeholders, both used through literal `L10n.tr` calls. | New-key presence/usage inspected; actual checker OK pending on macOS. |
| AC-9 | `CapturePolicy.shouldSave` has only explicit value inputs, no settings/workspace/pasteboard access. Unit tests exercise 112 combinations (pause × switch × four app cases × seven marker cases), plus custom/empty exclusions, exact marker matching and multiple markers. | Tests written before implementation; execution pending. |
| AC-10 | New policy source is listed in the app compiler invocation, standalone policy test and persistence-test compiler invocation in `build.sh`. New tests run before app compilation. Existing Build workflow already calls `./build.sh`; screenshot compilation automatically includes all non-main sources. | Wiring and shell syntax reviewed; warning-free build and green Build CI pending. |

Source-app attribution remains the existing frontmost-app heuristic sampled
at polling time, not guaranteed clipboard authorship. Fast app switches within
the 0.5-second interval can affect exclusion. README wording is deferred to the
explicitly separate documentation package.

## TDD and checks performed

1. Added `Tests/CapturePolicyTests.swift`, the privacy/permission integration
   tests and test compiler wiring **before** creating the policy or changing
   production behavior.
2. Inspected the pre-fix state: `Sources/CapturePolicy.swift` was absent, and
   the monitor/settings had none of the new APIs. This predicts compilation
   failure of the new tests against the baseline; the original permission code
   also cannot repair the tests' explicitly set `0755`/`0777` modes.
   **This is static evidence, not an observed failing test run.**
3. Implemented the narrow package-1 changes and reviewed the actual diff
   against every binding criterion. All fixtures use temporary stores, a private
   pasteboard and synthetic contents; the test restores modified defaults.
4. PASS: `git diff --check`.
5. PASS: `bash -n build.sh scripts/check-localizations.sh` (syntax only).
6. Inspected both new localization keys in all ten languages and their usage.

The explicit Linux-server rule prohibits builds and test execution here.
No Swift tests, `./build.sh`, localization checker or CI job were run. A
verified red/green TDD cycle, AC-8's actual OK and AC-10's green Build are
**not yet delivered**. No commits, pushes, PRs, releases, deployments or
production-data changes were made.

## Required macOS verification before acceptance

On a Mac, from this checkout:

```bash
./build.sh                     # policy, persistence and existing build tests
scripts/check-localizations.sh # must report OK
```

Record a warning-free build and a green GitHub **Build** run for the eventual
PR. For baseline red evidence use an isolated copy of commit `7700cd0` with
the new tests/test wiring applied first; missing policy/monitor APIs should
fail compilation. Do not check out or depend on another PR. A behavioral
permission regression can be checked with the new `privateDirectories` test
alone against that isolated baseline: existing `0755`/`0777` directories must
fail the `0700` expectations. Record actual output, then run the full fixed
tests above.

Manual checks, using only disposable synthetic clipboard contents/test stores:

1. With fresh default settings, copy from Keychain Access and Passwords: no
   entry. Copy synthetic secrets from 1Password with marker filtering enabled:
   no entry. Toggle the sensitive-content filter off and check marked content
   follows normal capture behavior (app exclusion still applies).
2. Pause: check menu checkmark, distinct pause bars and tooltip; copy text and
   an image; confirm history and image files do not change. Resume immediately
   after a copy (before 0.5 seconds): nothing from the pause appears. A new copy
   after resume is captured normally.
3. Restart while paused: recording starts active and the ordinary icon returns.
4. Use `ls -ld` on the base store folder and `Images/`: both must show
   `drwx------`. Repeat after starting with permissive directories in a
   disposable store; check both become `0700` and existing data is unchanged.
5. Inspect the icon in light/dark menu bars and the localized menu/tooltip.

Live issue-thread/open-PR review and these macOS results are the outstanding
handover items, rather than claimed successful checks.
