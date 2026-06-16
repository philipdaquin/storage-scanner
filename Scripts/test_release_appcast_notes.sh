#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/Scripts/release.sh"

TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/storage-scanner-release-appcast-notes.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT

export APPCAST_PATH="$TEMP_DIR/appcast.xml"

cat >"$APPCAST_PATH" <<'XML'
<rss>
  <channel>
    <item>
      <title>StorageScanner 0.0.1</title>
      <enclosure url="https://example.invalid/StorageScanner.dmg" length="123" type="application/octet-stream" />
    </item>
  </channel>
</rss>
XML

MOCK_BIN="$TEMP_DIR/bin"
mkdir -p "$MOCK_BIN"

cat >"$MOCK_BIN/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-C" && "${3:-}" == "remote" && "${4:-}" == "get-url" && "${5:-}" == "origin" ]]; then
  printf '%s\n' "https://github.com/example/storage-scanner.git"
  exit 0
fi

echo "unexpected git invocation: $*" >&2
exit 1
EOF
chmod +x "$MOCK_BIN/git"

export PATH="$MOCK_BIN:$PATH"

annotate_appcast_release_notes

grep -Fq '<sparkle:releaseNotesLink>https://github.com/example/storage-scanner/releases/tag/v0.0.1</sparkle:releaseNotesLink>' "$APPCAST_PATH"

echo "Release appcast notes tests passed."
