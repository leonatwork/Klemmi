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
export CODESIGN_ARGUMENTS="$TMP/codesign-arguments" IMPORT_ARGUMENTS="$TMP/import-arguments"
export EXPORT_ARGUMENTS="$TMP/export-arguments"

cat > "$TMP/bin/swiftc" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "$ARGUMENTS"
while (( $# )); do
  if [[ "$1" == -o ]]; then
    # Test executables built by build.sh's pre-flight step: runnable no-op, always succeeds.
    if [[ "$(basename "$2")" == *Tests ]]; then
      printf '#!/bin/sh\nexit 0\n' > "$2"
      chmod +x "$2"
      exit 0
    fi
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
printf '%s\n' "$@" > "$CODESIGN_ARGUMENTS"
[[ "$(cat dist/Klemmi.app/Contents/MacOS/Klemmi)" == 'compiled executable' ]]
STUB
# Keychain double: lists $IDENTITIES for find-identity, records import arguments.
cat > "$TMP/bin/security" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  find-identity) printf '%s\n' "${IDENTITIES:-}" ;;
  import) printf '%s\n' "$@" > "$IMPORT_ARGUMENTS" ;;
  *) exit 99 ;;
esac
STUB
# OpenSSL double: random output for `rand`, records the PKCS#12 export arguments.
cat > "$TMP/bin/openssl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  rand) printf 'random%s%s%s\n' "$$" "$RANDOM" "$RANDOM" ;;
  req) ;;
  pkcs12) printf '%s\n' "$@" > "$EXPORT_ARGUMENTS" ;;
  *) exit 99 ;;
esac
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
# --deep is deprecated and unnecessary: the bundle has no nested code.
! grep -Fx -- '--deep' "$CODESIGN_ARGUMENTS" >/dev/null || fail 'codesign called with --deep'
[[ "$(tail -n 1 "$CODESIGN_ARGUMENTS")" == dist/Klemmi.app ]] || fail 'codesign did not sign the bundle'

# Keychain identity preference: Klemmi names first, Tappi only as legacy fallback.
signed_identity() { awk 'previous == "--sign" { print } { previous = $0 }' "$CODESIGN_ARGUMENTS"; }
identity() { printf '  %s) %040d "%s"\n' "$1" "$1" "$2"; }
expect_identity() {
  CODESIGN_IDENTITY= bash "$TMP/project/build.sh" > "$TMP/build.log" 2>&1 || fail "build failed: $2"
  [[ "$(signed_identity)" == "$1" ]] || fail "signed with '$(signed_identity)' instead of '$1': $2"
}
IDENTITIES="$(identity 1 'Tappi Local Signing'; identity 2 'leonatwork Code Signing'; identity 3 'Klemmi Local Signing')" \
  expect_identity 'Klemmi Local Signing' 'all identities present'
IDENTITIES="$(identity 1 'Tappi Local Signing'; identity 2 'leonatwork Code Signing')" \
  expect_identity 'leonatwork Code Signing' 'shared identity before legacy'
IDENTITIES="$(identity 1 'Tappi Local Signing')" expect_identity 'Tappi Local Signing' 'legacy fallback'
IDENTITIES='' expect_identity - 'no identity falls back to ad-hoc'

# setup-signing.sh: per-run random PKCS#12 password, never printed, no access for all apps.
cp "$ROOT/setup-signing.sh" "$TMP/project/setup-signing.sh"
mkdir -p "$TMP/home"
after() { awk -v flag="$1" 'previous == flag { print } { previous = $0 }' "$2"; }
passwords=()
for run in 1 2; do
  rm -f "$IMPORT_ARGUMENTS" "$EXPORT_ARGUMENTS"
  HOME="$TMP/home" IDENTITIES='' bash "$TMP/project/setup-signing.sh" > "$TMP/setup.log" 2>&1 \
    || fail "setup-signing.sh failed: $(cat "$TMP/setup.log")"
  [[ "$(after -name "$EXPORT_ARGUMENTS")" == 'Klemmi Local Signing' ]] || fail 'default identity is not Klemmi Local Signing'
  ! grep -Fx -- '-A' "$IMPORT_ARGUMENTS" >/dev/null || fail 'import grants all applications access (-A)'
  [[ "$(after -T "$IMPORT_ARGUMENTS")" == /usr/bin/codesign ]] || fail 'import does not restrict access to codesign'
  password="$(after -P "$IMPORT_ARGUMENTS")"
  [[ -n "$password" && "$password" != tappi ]] || fail "import password is fixed or empty: '$password'"
  [[ "$(after -passout "$EXPORT_ARGUMENTS")" == "pass:$password" ]] || fail 'export and import passwords differ'
  ! grep -F -- "$password" "$TMP/setup.log" >/dev/null || fail 'password was printed'
  passwords+=("$password")
done
[[ "${passwords[0]}" != "${passwords[1]}" ]] || fail 'password is not generated per run'

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
