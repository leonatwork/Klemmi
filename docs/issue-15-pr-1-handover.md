# Issue #15 — PR 1: pinning logic

## Scope and basis

The supplied triaged decision splits this feature into three PRs. This run
implements **PR 1 (model, pure ordering/trim rules, store integration and tests)**.
PR 2 supplies UI actions, recognition/accessibility, grouping and confirmation
with localized text. PR 3 updates both READMEs. The whole issue is not complete
until those follow-ups and macOS acceptance checks are complete.

The existing checkout's HEAD equals `origin/master` at
`d631c6e479993194c7e76ddd9b439d6de01070e0`, and `origin/HEAD` points to that
branch. There is no local `origin/main` ref. The literal `origin/main` instruction
therefore remains **unfulfilled**; changes use the existing checkout. No other
branch was checked out and no foreign PR commits were used or cherry-picked.

GitHub queries for the complete issue thread/comments, open PRs and default
branch were denied by tool permissions. Live issue decisions and potential
open-PR overlap remain **unverified**. The supplied issue and corrective findings
are the acceptance source. No implementation dependency on an open PR was
identified from the checked-out code; this is not a live PR verification.

Read `CONTRIBUTING.md`, the model/store and history views, test conventions,
`build.sh`, the Build workflow and localization checker. No `CLAUDE.md` or
`AGENTS.md` was found in the workspace. The `kb ask` lookup confirmed the recorded
default branch and architecture/test conventions, not live GitHub state.

## Implementation

- `HistoryItem.pinned` defaults to false. The explicit decoder uses
  `decodeIfPresent(Bool.self, forKey: .pinned) ?? false`; existing optional fields
  remain optional. Synthesized encoding includes `pinned`. The explicit normal
  initializer preserves all existing call sites.
- `HistoryPinning.ordered(_:)` puts pins first, with descending date within both
  groups and stable input order for equal dates.
- `HistoryPinning.trimmed(_:limit:)` preserves all pins, counts them toward the
  limit, and retains the newest `max(1, limit - pinCount)` ordinary entries.
  Nonpositive limits also retain one ordinary slot. With pins at/over the limit,
  total count can exceed the limit by design. It creates no ordinary placeholder
  when none exists.
- Store insertion and `togglePinned(_:)` trim on the existing serial disk queue,
  save, then publish the snapshot on main. Toggling does not change the date;
  a missing ID is a no-op. Startup orders decoded entries without trimming them.
  Popover/overlay already consume this order and filter pins like other entries.
- `clear()` preserves pins. Trim/clear enqueue only removed entries' image files
  in `pendingImageRemovals`. Existing save ordering and reference checks remain
  intact: images are deleted after successful index persistence and files still
  referenced by remaining entries are protected. Individual deletion also
  accepts pinned IDs.
- Recopying a pinned text creates an ordinary entry; ordinary consecutive
  duplicate suppression now looks past the pinned group.
- Removed the specifically reported uncommitted age-cleanup code/settings/tests,
  recording-status and extra privacy tests, unrelated README additions and
  privacy-step handovers. Already-merged privacy and persistence safety code
  remains part of the base. Final README and settings contents match HEAD.

## Acceptance mapping

All implementation/test statements below are based on static review; Swift
execution and manual acceptance are pending.

| AC | PR 1 evidence and remaining work |
| --- | --- |
| AC-1 | Literal legacy text/image JSON without `pinned` is decoded in `HistoryPinningTests`, checking entry count, metadata, dates and false pin values. New JSON covers true, false and null; round-trip and encoded keys are checked. macOS legacy-history startup acceptance remains pending. |
| AC-2 | Ordering is supplied through store snapshots; pin persistence/restart is covered by `HistoryPersistenceTests.pinning`. Context menus, overlay ⌘P, row symbol and VoiceOver label belong to **PR 2**, so full AC-2 is pending. |
| AC-3 | Pure tests cover oldest-first ordinary eviction, pins counting toward the limit, pins equal to/over the limit, all-pin/empty/no-pin inputs, and equal timestamps. Store tests check pinned image bytes survive insertion/trim while the removed ordinary image disappears. Runtime evidence pending. |
| AC-4 | Store preservation of pins/images on clear is implemented/tested. The shared confirmation helper, three entry points, explanatory text and cancellation behavior belong to **PR 2**; full AC-4 is pending. |
| AC-5 | Pure and store tests cover unpinning without changing date, reinsertion by date, immediate trimming and deletion of the now-unprotected oldest image. UI action belongs to **PR 2**. |
| AC-6 | First, exclusive “Pinned” group for all overview groupings belongs to **PR 2**. |
| AC-7 | Store test individually deletes a pinned image and checks empty JSON/history image directory. UI/manual acceptance follows **PR 2**. |
| AC-8 | New localized UI texts and all ten translations belong to **PR 2**. Resources are unchanged here. The checker is still required by Build CI; no OK result is claimed because it needs macOS `osascript`/Foundation. |

The feature-list additions to `README.md` and `README.de.md` belong to **PR 3**.
Screenshots, age-based cleanup and JSON recovery changes are outside this scope.

## Tests and verification

The regression tests were written before the production fix. Before the fix,
static inspection confirmed that the base lacked `pinned`, `HistoryPinning` and
`togglePinned`: the new test sources would not compile against that base. This
is **not an observed failing test result**. The explicit Linux-server rule
prohibits building/running the Swift tests here. A runtime red/green TDD proof,
warning-free compilation and a green Build CI run remain unavailable.

Performed successfully:

- `git diff --check`
- `bash -n build.sh`
- `bash -n scripts/check-localizations.sh`
- Static review of the actual diff, edge-case expectations, serial write/image
  removal ordering, test isolation and compiler wiring. The new pure suite and
  existing persistence suite are both wired into `build.sh`, called by Build CI.

On macOS, run the relevant suites first from the repository root:

```bash
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc Sources/Localization.swift Sources/HistoryItem.swift Sources/HistoryPinning.swift \
  Tests/HistoryPinningTests.swift -o "$TEST_DIR/HistoryPinningTests"
"$TEST_DIR/HistoryPinningTests"
swiftc Sources/Support.swift Sources/Localization.swift Sources/HistoryItem.swift \
  Sources/HistorySafety.swift Sources/HistoryPinning.swift Sources/HistoryStore.swift \
  Sources/CapturePolicy.swift Sources/ClipboardMonitor.swift Sources/Clipboard.swift \
  Tests/HistoryPersistenceTests.swift -framework AppKit -o "$TEST_DIR/HistoryPersistenceTests"
"$TEST_DIR/HistoryPersistenceTests"
scripts/check-localizations.sh
./build.sh
```

Fixtures use synthetic contents, temporary stores and the existing private
pasteboard; changed settings are restored and disk writes drained before
assertions. No real status item is created by the new tests.

Before final acceptance: verify the live issue/open PRs and resolve the branch
name requirement; obtain test and green Build CI evidence. After PR 2, back up
`history.json` and manually check AC-1 through AC-7 on a Mac in popover, overlay
and overview, including cancel/confirm at all three clear entry points.

No commit, push, PR creation, merge, release, production deployment or
production-data operation was performed.
