#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/Scripts/release.sh"

TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/storage-scanner-release-signing.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT

export RELEASE_SKIP_SIGNING=0
export DEVELOPER_ID_IDENTITY="Developer ID Application: Test User (TEAMID)"
export APP_PATH="$TEMP_DIR/StorageScanner.app"
export CODESIGN_LOG="$TEMP_DIR/codesign.log"
export SPCTL_LOG="$TEMP_DIR/spctl.log"

mkdir -p "$APP_PATH/Contents/Frameworks/Foo.framework" "$APP_PATH/Contents/MacOS"
touch "$APP_PATH/Contents/MacOS/StorageScanner"

MOCK_BIN="$TEMP_DIR/bin"
mkdir -p "$MOCK_BIN"

cat >"$MOCK_BIN/codesign" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"${CODESIGN_LOG:?}"
exit 0
EOF
chmod +x "$MOCK_BIN/codesign"

export PATH="$MOCK_BIN:$PATH"

sign_release_app

grep -Fq -- "--force --timestamp --options runtime --sign Developer ID Application: Test User (TEAMID) $APP_PATH/Contents/Frameworks/Foo.framework" "$CODESIGN_LOG"
grep -Fq -- "--force --timestamp --options runtime --entitlements $ROOT/StorageScanner/SidebarApp.entitlements --sign Developer ID Application: Test User (TEAMID) $APP_PATH" "$CODESIGN_LOG"
grep -Fq -- "--verify --deep --strict --verbose=2 $APP_PATH" "$CODESIGN_LOG"

echo "Release signing flow tests passed."
