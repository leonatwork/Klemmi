#!/usr/bin/env bash
# Enforce the release contract in both Build and Release CI.
set -euo pipefail
BINARY="${1:-dist/Klemmi.app/Contents/MacOS/Klemmi}"

ARCHS=$(lipo -archs "$BINARY")
if [[ "$ARCHS" != arm64 ]]; then
  echo "Expected exactly arm64, got: $ARCHS" >&2
  exit 1
fi

BUILD_INFO=$(vtool -show-build "$BINARY")
printf '%s\n' "$BUILD_INFO"
MINOS=$(printf '%s\n' "$BUILD_INFO" | awk '$1 == "minos" { print $2 }')
if [[ "$MINOS" != 13.0 ]]; then
  echo "Expected exactly one minos 13.0, got: $MINOS" >&2
  exit 1
fi
