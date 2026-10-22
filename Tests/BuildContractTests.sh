#!/usr/bin/env bash
# Run on macOS: bash Tests/BuildContractTests.sh [repository-to-test]
# Isolated fixtures and tool doubles: never installs or signs a real app.
set -euo pipefail
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$TMP/bin" "$TMP/project/Resources/en.lproj" "$TMP/temp output"
cp "$ROOT/build.sh" "$TMP/project/build.sh"
export PATH="$TMP/bin:$PATH" TMPDIR="$TMP/temp output"
export ARGUMENTS="$TMP/arguments" OUTPUT="$TMP/output" CODESIGN_IDENTITY=- VERSION=

cat > "$TMP/bin/swiftc" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "$ARGUMENTS"
while (( $# )); do
  if [[ "$1" == -o ]]; then
    printf '%s' "$2" > "$OUTPUT"
    printf 'compiled executable' > "$2"
    exit "$COMPILE_STATUS"
  fi
  shift
done
exit 99
STUB
cat > "$TMP/bin/git" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
cat > "$TMP/bin/swift" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
cat > "$TMP/bin/codesign" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[[ "$(cat dist/Klemmi.app/Contents/MacOS/Klemmi)" == 'compiled executable' ]]
STUB
chmod +x "$TMP/bin/"*

APP="$TMP/project/dist/Klemmi.app"
export COMPILE_STATUS=42
for existing in no yes; do
  if [[ "$existing" == yes ]]; then
    mkdir -p "$APP/Contents/MacOS"
    printf 'previous executable' > "$APP/Contents/MacOS/Klemmi"
    printf 'previous metadata' > "$APP/Contents/Info.plist"
    cp -R "$APP" "$TMP/previous.app"
  fi
  status=0
  bash "$TMP/project/build.sh" > "$TMP/build.log" 2>&1 || status=$?
  [[ "$status" == 42 ]] || fail "compiler failure was not propagated ($status)"
  if [[ "$existing" == no ]]; then
    [[ ! -e "$APP" ]] || fail 'failed compilation created a partial bundle'
  else
    diff -r "$TMP/previous.app" "$APP" || fail 'failed compilation changed existing bundle'
  fi
  [[ ! -e "$(cat "$OUTPUT")" ]] || fail 'temporary compiler output leaked on failure'
done

export COMPILE_STATUS=0
bash "$TMP/project/build.sh"
[[ "$(cat "$APP/Contents/MacOS/Klemmi")" == 'compiled executable' ]] || fail 'binary not installed in bundle'
[[ -f "$APP/Contents/Info.plist" && -d "$APP/Contents/Resources/en.lproj" ]] || fail 'incomplete bundle'
grep -Fx -- '-O' "$ARGUMENTS" >/dev/null || fail 'optimization missing'
target=$(awk 'previous == "-target" { print } { previous = $0 }' "$ARGUMENTS")
[[ "$target" == arm64-apple-macos13 ]] || fail "incorrect compiler target: $target"
[[ "$(cat "$OUTPUT")" != dist/Klemmi.app/* ]] || fail 'compiler wrote directly into bundle'
[[ ! -e "$(cat "$OUTPUT")" ]] || fail 'temporary compiler output leaked on success'

# Exercise the same binary inspector used by both workflows, including tool failures
# that still print plausible output. No Apple command-line tools are used here.
cat > "$TMP/bin/lipo" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == -archs && "$2" == "$BINARY" ]] || exit 99
printf '%s\n' "$ARCHS"
exit "$LIPO_STATUS"
STUB
cat > "$TMP/bin/vtool" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == -show-build && "$2" == "$BINARY" ]] || exit 99
printf '%s\n' "$BUILD_INFO"
exit "$VTOOL_STATUS"
STUB
chmod +x "$TMP/bin/lipo" "$TMP/bin/vtool"
export BINARY="$APP/Contents/MacOS/Klemmi" LIPO_STATUS=0 VTOOL_STATUS=0
valid_info=$'Load command 10\n      cmd LC_BUILD_VERSION\n platform MACOS\n    minos 13.0\n      sdk 15.5'
export ARCHS=arm64 BUILD_INFO="$valid_info"
bash "$ROOT/scripts/check-binary.sh" "$BINARY" || fail 'valid arm64/macOS 13 binary rejected'
reject() {
  if bash "$ROOT/scripts/check-binary.sh" "$BINARY"; then
    fail "invalid binary accepted: $*"
  fi
}
for ARCHS in x86_64 'x86_64 arm64' 'arm64 x86_64' ''; do
  reject "architectures: $ARCHS"
done
export ARCHS=arm64
for BUILD_INFO in '' '    minos 15.0' '    minos 13.1' '    minos 13.0.1' '    sdk 13.0' \
  $'    minos 13.0\n    minos 15.0'; do
  reject "build version: $BUILD_INFO"
done
export BUILD_INFO="$valid_info" LIPO_STATUS=1
reject 'lipo failure with valid output'
export LIPO_STATUS=0 VTOOL_STATUS=1
reject 'vtool failure with valid output'
echo '==> Build contract tests passed'
