#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/Scripts/release.sh"

TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/storage-scanner-release-notarize.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT

export RELEASE_SKIP_NOTARIZATION=0
export DMG_PATH="$TEMP_DIR/StorageScanner.dmg"
export NOTARYTOOL_PROFILE="StorageScanner Notary"
export XCRUN_LOG="$TEMP_DIR/xcrun.log"

touch "$DMG_PATH"

MOCK_BIN="$TEMP_DIR/bin"
mkdir -p "$MOCK_BIN"

cat >"$MOCK_BIN/xcrun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"${XCRUN_LOG:?}"
exit 0
EOF
chmod +x "$MOCK_BIN/xcrun"

export PATH="$MOCK_BIN:$PATH"

notarize_dmg

grep -Fq "notarytool submit $DMG_PATH --keychain-profile StorageScanner Notary --wait" "$XCRUN_LOG"
grep -Fq "stapler staple $DMG_PATH" "$XCRUN_LOG"

echo "Release notarization flow tests passed."
