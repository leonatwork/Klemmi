# Issue #9 — implementation handover

## Basis and binding scope

The starting checkout matches `origin/master` at
`01db226485d1a96419cd929a2938294e8c46314e`; `origin/HEAD` points to
`origin/master`. This is the repository's main branch and the base explicitly
authorized by the review findings. No foreign PR code was used.

The supplied triaged decision is binding: **arm64 only, Apple Silicon,
macOS 13.0**. It supersedes the Universal Binary/Intel requirements in the title
and preserved original description.

Read `CONTRIBUTING.md`, the existing build/workflows and test conventions.
No `CLAUDE.md` or `AGENTS.md` was found in the workspace. GitHub issue/comment
and open-PR queries were denied by tool permissions; the supplied issue text
and review findings therefore form the scope of this implementation. There is
no implementation dependency on an open PR.

## Acceptance review

| Criterion | Implementation and evidence status |
| --- | --- |
| AC-1 | `build.sh` uses `swiftc -O -target arm64-apple-macos13`. Both workflows enforce exactly `arm64` through `scripts/check-binary.sh`. Actual Mach-O evidence requires macOS. |
| AC-2 | The same checker requires exactly one `minos 13.0` from `vtool -show-build`; missing or multiple values fail. Actual Mach-O evidence requires macOS. |
| AC-3 | Compilation uses `mktemp` output with an EXIT cleanup trap. The existing bundle is removed and recreated only after compilation succeeds. Regression cases cover a fresh build, preservation of an existing bundle on compiler failure, successful replacement and temporary-output cleanup. Execution is pending on macOS. |
| AC-4 | Build and Release call the shared checker immediately after building, before packaging or publishing. Regression cases cover wrong/multiple/empty architectures, wrong/missing/multiple minimum versions and failing inspection tools even when they print valid output. Both workflows run the regression suite before building. CI evidence is pending. |
| AC-5 | Both workflows run `codesign --verify --strict dist/Klemmi.app`, including ad-hoc builds. Signing behavior is preserved. Actual signature verification is pending on macOS. |
| AC-6 | The existing `--install` copy and launch sequence is preserved. Manual launch verification is pending on macOS. |
| AC-7 | Both README badges and requirement text, plus CONTRIBUTING, specify Apple Silicon and macOS 13+. Bug-report guidance asks for the Apple Silicon chip model instead of Intel. Verified in the diff. |
| AC-8 | The explicit deployment target enables compiler availability diagnostics for macOS 13. No compiler run was possible here, so absence of newly exposed API warnings is not claimed. |

## Checks performed

- Added `Tests/BuildContractTests.sh` before changing the implementation. It uses
  isolated fixtures and shell tool doubles, without dependencies or a test framework.
- Passed syntax-only checks: `bash -n build.sh`,
  `bash -n scripts/check-binary.sh`, `bash -n Tests/BuildContractTests.sh`.
- Passed `git diff --check`; reviewed workflow ordering and the acceptance
  criteria against the actual changes.
- Per the explicit Linux-server rule, no build or test suite was executed.
  In particular, there is no observed red/green result. Static inspection of
  the baseline predicts the first regression will fail with
  `failed compilation created a partial bundle`; this is not a test result.
- Resources were not changed, so the conditional localization check is not needed.
- No commits, pushes, PR creation, releases or deployments were performed.

## Open evidence for the eventual PR

1. **macOS evidence:** run `bash Tests/BuildContractTests.sh` and obtain a green
   Build CI run on `macos-15`. For pre-fix regression evidence, the test accepts
   an optional repository/fixture directory containing the original `build.sh`;
   run the new test against that isolated baseline first and record its failure.
   Then record a warning-free `./build.sh`,
   `lipo -archs dist/Klemmi.app/Contents/MacOS/Klemmi`,
   `vtool -show-build dist/Klemmi.app/Contents/MacOS/Klemmi`, and
   `codesign --verify --strict dist/Klemmi.app`.
   Verify `./build.sh --install` launches from `/Applications` on a Mac.
   An additional macOS 13/14 launch check is optional.
2. **Latest published release:** inspect the latest `v*` release asset on a Mac
   and include its tag, asset name and actual `vtool -show-build` output in the
   PR description. `minos 15.x` remains an assumption, not a measured result.
