# Issue #16 — history and clipboard data-loss fixes

Issue: https://github.com/leonatwork/Klemmi/issues/16

## Delivery and available context

Implemented on the existing checkout at `01db226485d1a96419cd929a2938294e8c46314e`,
which equals `origin/master`. There is no `origin/main` ref. The follow-up task
explicitly authorizes this base, superseding the original `origin/main` requirement.
No other PR branch was checked out or used. No commit, push, PR, merge, release or
deployment was performed.

`CONTRIBUTING.md`, the current sources, test style, build script and Build workflow
were inspected. Neither `CLAUDE.md` nor `AGENTS.md` exists in this checkout.
The attempts to read the issue comments and list open PRs with `gh` were denied
by tool policy. The supplied issue description and follow-up findings are the
available requirements; additional comments and dependencies on open PRs remain
unverified. The knowledge base confirms the `origin/master` baseline. Missing
remote access is a context limitation, not an implementation blocker.

## Acceptance criteria and implementation

| Criterion | Implementation | Added regression coverage (not executed here) |
| --- | --- | --- |
| AC-1 | Copy undecodable history to `history.json.corrupt`, then timestamp/suffix variants on collision. Log the backup filename without clipboard contents. Disable saving if reading or backing up fails, preserving the original. Missing index is a normal first launch. | Corrupt bytes survive a later save; an older backup stays unchanged; backup-name collisions; first launch. |
| AC-2 | Store the successful write's `clearContents()` count. Skip only that exact value; discard the marker on the next observed change. | Own text/image is skipped; a foreign copy before the next poll is retained; pure decision cases. |
| AC-3 | Prepare and validate text/image payload before touching the pasteboard; beep and return failure for unavailable contents. Missing-image entries remain in history. | Private pasteboard contents and count survive a missing-image write; the next real copy is captured. |
| AC-4 | Pass captured image bytes to a serial utility queue. Bitmap decoding, PNG encoding, image writes and JSON encoding/writes run there. Only UI snapshots and notifications are dispatched to main. | Ordered persistence is covered; perceived responsiveness and 5K-image latency require manual macOS testing. |
| AC-5 | On termination stop the timer, poll once for a copy before the next timer tick, then drain persistence with `queue.sync {}`. Workers finish image and JSON writes without waiting for a main callback. | Immediate flush without running main callbacks; restart finds image and entry; final poll captures text and image; queued clear cannot resurrect a pending image. |
| AC-6 | After decoding succeeds, queue a set-difference cleanup of unreferenced regular files directly under `Images/`. Keep referenced files and entries whose image is missing. | Referenced file retained, orphan removed, missing-image entry retained; pure set-difference cases. |
| AC-7 | No startup cleanup after a missing or failed load. A failed load also blocks image deletion for the rest of that store session, even after a successful replacement save. | Images survive corrupt loading, subsequent save and clear. |

No contradiction between AC-1–AC-7 was found in the supplied requirements. Their
macOS execution/UX evidence remains outstanding; implementation is not an
acceptance-test pass.

### Persistence ordering

The worker queue owns a separate history snapshot after initialization. All
mutations (including delete/clear) are serialized with image encoding, so a slow
image cannot overwrite newer text or reappear after a clear. `items` and change
notifications remain on main. An image is published only after its file is written.
Text updates also arrive asynchronously, in queue order.

Removed/trimmed image files are deleted only after the updated JSON is written
successfully; a failed save retains images needed by the previous index. A
regression test forces this write-failure path. Failures are logged using error
codes rather than potentially sensitive history contents. Unreadable or
unbacked-up history disables persistence until the next store initialization.

## Validation status

- Added `Tests/HistorySafetyTests.swift` and `Tests/HistoryPersistenceTests.swift`
  before implementing the fixes, using standalone `precondition` assertions.
  Registered both in `build.sh` before app compilation, with assertions enabled.
- Persistence tests use invented text, generated pixels and disposable store
  directories. Clipboard tests use `NSPasteboard.withUniqueName()`, never the
  general pasteboard or real history. No extra dependencies were added.
- `git diff --check`: passed after implementation.
- Reviewed call sites, queue ownership/order, startup paths, failed-save handling,
  termination and the build source list statically.
- **Not run:** Swift tests, app build, macOS manual checks, or GitHub Build CI.
  This Linux host has no Swift/Xcode/AppKit, and the task explicitly forbids
  building/executing here. Consequently there is **no verified red-before-fix or
  green-after-fix result**. This conflicts with the original local-macOS TDD/QS
  requirement; that evidence cannot be supplied in this environment.

## Required macOS follow-up

1. Run `./build.sh` on macOS 13+ with Command Line Tools. It runs both added test
   executables before building the app. Record results and compiler warnings.
   The existing GitHub **Build** workflow invokes this same script on macOS 15;
   obtain its result when remote delivery is authorized.
2. Use an isolated manual-test app/store. In a disposable local source copy, set
   `HistoryStore.baseDirectoryOverride` to a fresh temporary directory before the
   `let app = NSApplication.shared` line in `main.swift`, then build that copy.
   Use only synthetic history/image data. Do not commit this local test setting.
3. AC-1/AC-7: stop the test app, truncate its test `history.json`, retain its Images
   directory, and launch. Confirm the backup bytes and log, copy new synthetic
   text, and confirm both backup and pre-existing images remain. Repeat with an
   existing `.corrupt` backup to check collision handling.
4. AC-2/AC-3: restore an item and copy different synthetic text from another app
   within 0.5 seconds; only the foreign copy should be added. Delete a test image
   file, try restoring its entry, check the beep and unchanged clipboard, then
   copy new synthetic text and verify capture.
5. AC-4/AC-5: copy a synthetic 5K image while interacting with overlay/popover;
   check responsiveness. Quit both before the next poll and while image encoding
   is pending. Relaunch and verify the entry and valid image file. Normal quit is
   the acceptance case; force-kill/power-loss durability is not claimed.
6. AC-6: with a valid test index, add an unused file under Images, launch, and
   verify only the unused file disappears. Repeat with valid empty JSON (`[]`).
   Repeat with a corrupt or missing index and verify that startup deletes nothing.

The superseded `NOTES-BLOCKER.md` has been replaced by this implementation handover.
