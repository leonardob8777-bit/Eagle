#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/private/tmp}/eagle-matrix.XXXXXX")"

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

SUPPORT_SOURCE="$PROJECT_ROOT/lara/funcs/isunsupported.swift"
MATRIX_SOURCE="$PROJECT_ROOT/scripts/verify_prepare_support_matrix.swift"

compile_and_run() {
  local name="$1"
  shift
  local executable="$TEMP_DIR/$name"

  swiftc \
    -parse-as-library \
    "$@" \
    "$SUPPORT_SOURCE" \
    "$MATRIX_SOURCE" \
    -o "$executable"
  "$executable"
}

echo "Verifying public Prepare support matrix..."
compile_and_run public

echo "Verifying laboratory Prepare support matrix..."
compile_and_run laboratory -D EAGLE_A18_PREPARE_LAB

echo "Prepare support matrices passed (50/50)."
