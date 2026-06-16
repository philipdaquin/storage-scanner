#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/storage-scanner-release-notes.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT

OUTPUT="$TEMP_DIR/release-notes.md"

bash "$ROOT/Scripts/release-notes.sh" "0.0.1" "$OUTPUT"

grep -Fq "StorageScanner 0.0.1" "$OUTPUT"
grep -Fq "Generated from commit subjects" "$OUTPUT"
grep -Fq "## Added" "$OUTPUT"
grep -Fq "Add Sparkle auto-update support" "$OUTPUT"
grep -Fq "Stop category selection from starting scans" "$OUTPUT"
if grep -Fq "Use stapler validation for DMG release" "$OUTPUT"; then
  echo "ERROR: release plumbing should not appear in drafted release notes." >&2
  exit 1
fi

echo "Release notes draft tests passed."
