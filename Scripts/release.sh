#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
source "$SCRIPT_DIR/release-common.sh"
storage_scanner_load_env "$ROOT"

MODE="${1:-local}"
if [[ $# -gt 0 ]]; then
  shift
fi

if [[ -n "${RELEASE_BASE_DIR:-}" ]]; then
  RELEASE_ROOT="$RELEASE_BASE_DIR"
else
  RELEASE_ROOT=$(storage_scanner_release_root "$ROOT")
fi
ARTIFACTS_DIR="${RELEASE_ARTIFACTS_DIR:-$RELEASE_ROOT/artifacts}"
SOURCEPACKAGES_DIR="${RELEASE_SOURCEPACKAGES_DIR:-$RELEASE_ROOT/SourcePackages}"
DERIVED_DATA_DIR="${RELEASE_DERIVED_DATA_DIR:-$RELEASE_ROOT/DerivedData}"
SPARKLE_DERIVED_DATA_DIR="${RELEASE_SPARKLE_DERIVED_DATA_DIR:-$RELEASE_ROOT/SparkleDerivedData}"
PACKAGE_CACHE_DIR="${RELEASE_PACKAGE_CACHE_DIR:-$RELEASE_ROOT/PackageCache}"
STAGING_DIR="${RELEASE_STAGING_DIR:-$RELEASE_ROOT/dmg-stage}"
CACHE_DIR="$RELEASE_ROOT/cache"
APP_PATH="${RELEASE_APP_PATH:-$DERIVED_DATA_DIR/Build/Products/Release/StorageScanner.app}"
DMG_PATH="${RELEASE_DMG_PATH:-$ARTIFACTS_DIR/StorageScanner-$(storage_scanner_arch_label "${RELEASE_ARCHS:-arm64 x86_64}")-$(storage_scanner_release_version).dmg}"
ZIP_PATH="${RELEASE_ZIP_PATH:-$ARTIFACTS_DIR/StorageScanner-$(storage_scanner_arch_label "${RELEASE_ARCHS:-arm64 x86_64}")-$(storage_scanner_release_version).zip}"
APPCAST_PATH="${RELEASE_APPCAST_PATH:-$ARTIFACTS_DIR/appcast.xml}"
DOWNLOAD_URL_PREFIX=$(storage_scanner_release_download_url_prefix "$ROOT" "$MODE")
APPCAST_FEED_URL=$(storage_scanner_appcast_feed_url "$ROOT")
SPARKLE_KEY_FILE=""

SPARKLE_CHECKOUT="$SOURCEPACKAGES_DIR/checkouts/Sparkle"

mkdir -p "$ARTIFACTS_DIR" "$SOURCEPACKAGES_DIR" "$PACKAGE_CACHE_DIR" "$CACHE_DIR"
export XDG_CACHE_HOME="$CACHE_DIR"

usage() {
  cat >&2 <<EOF
Usage: $(basename "$0") [local|publish|upload|appcast]

local     Build StorageScanner, package DMG and Sparkle ZIP, and generate appcast.xml.
publish   Do local release work, notarize the DMG, generate appcast.xml with GitHub URLs, and upload assets with gh release.
upload    Do local release work, notarize the DMG, generate appcast.xml with GitHub URLs, and upload assets to an existing GitHub release.
appcast   Regenerate appcast.xml from the current ZIP artifact directory.

Environment:
  RELEASE_ARCHS=arm64 x86_64
  APPCAST_URL=https://raw.githubusercontent.com/<owner>/<repo>/main/appcast.xml
  SPARKLE_PRIVATE_KEY_FILE=/path/to/private-ed25519.key
  SPARKLE_PRIVATE_KEY=...               (alternative to the file path)
  DEVELOPER_ID_IDENTITY=Developer ID Application: ...
  NOTARYTOOL_PROFILE=<keychain profile>
  NOTARYTOOL_API_KEY_FILE=/path/to/AuthKey_XXXX.p8
  NOTARYTOOL_API_KEY_ID=XXXX
  NOTARYTOOL_API_ISSUER_ID=YYYY-YYYY-YYYY-YYYY
  RELEASE_SKIP_SIGNING=1
  RELEASE_SKIP_NOTARIZATION=1
EOF
}

resolve_signing_options() {
  if [[ "${RELEASE_SKIP_SIGNING:-0}" == "1" ]]; then
    return 0
  fi

  if [[ -z "${DEVELOPER_ID_IDENTITY:-}" ]]; then
    echo "ERROR: DEVELOPER_ID_IDENTITY is required unless RELEASE_SKIP_SIGNING=1." >&2
    return 1
  fi

  return 0
}

build_release_app() {
  local feed_url="$APPCAST_FEED_URL"
  local sparkle_public_key="${SPARKLE_PUBLIC_ED_KEY:-}"

  xcodebuild \
    -project "$ROOT/StorageScanner.xcodeproj" \
    -scheme StorageScanner \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    -clonedSourcePackagesDirPath "$SOURCEPACKAGES_DIR" \
    -packageCachePath "$PACKAGE_CACHE_DIR" \
    -disableAutomaticPackageResolution \
    -skipPackageUpdates \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    ONLY_ACTIVE_ARCH=NO \
    ARCHS="${RELEASE_ARCHS:-arm64 x86_64}" \
    CLANG_MODULE_CACHE_PATH="$CACHE_DIR/clang-module-cache" \
    SHARED_PRECOMPS_DIR="$CACHE_DIR/shared-precompiled-headers" \
    INFOPLIST_KEY_SUFeedURL="$feed_url" \
    INFOPLIST_KEY_SUPublicEDKey="$sparkle_public_key" \
    INFOPLIST_KEY_SUEnableAutomaticChecks=YES \
    build
}

sign_release_app() {
  if [[ "${RELEASE_SKIP_SIGNING:-0}" == "1" ]]; then
    return 0
  fi

  local entitlements="$ROOT/StorageScanner/SidebarApp.entitlements"
  local framework

  if [[ ! -d "$APP_PATH" ]]; then
    echo "ERROR: Missing built app at $APP_PATH" >&2
    return 1
  fi

  while IFS= read -r framework; do
    [[ -z "$framework" ]] && continue
    codesign \
      --force \
      --timestamp \
      --options runtime \
      --sign "$DEVELOPER_ID_IDENTITY" \
      "$framework"
  done < <(find "$APP_PATH/Contents/Frameworks" -maxdepth 1 -type d -name '*.framework' | sort)

  sign_sparkle_framework

  codesign \
    --force \
    --timestamp \
    --options runtime \
    --entitlements "$entitlements" \
    --sign "$DEVELOPER_ID_IDENTITY" \
    "$APP_PATH"

  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
}

resolve_sparkle_version_dir() {
  local sparkle="$1"
  local versions_dir="$sparkle/Versions"
  local version_dirs=()
  local candidate

  if [[ -L "$sparkle" ]]; then
    echo "ERROR: Sparkle framework root must not be a symlink: $sparkle" >&2
    return 1
  fi

  if [[ -L "$versions_dir" ]]; then
    echo "ERROR: Sparkle versions directory must not be a symlink: $versions_dir" >&2
    return 1
  fi

  if [[ ! -d "$versions_dir" ]]; then
    echo "ERROR: Missing Sparkle versions directory: $versions_dir" >&2
    return 1
  fi

  if [[ -e "$versions_dir/Current" || -L "$versions_dir/Current" ]]; then
    if ! candidate=$(cd "$versions_dir/Current" 2>/dev/null && pwd -P); then
      echo "ERROR: Sparkle Versions/Current does not resolve: $versions_dir/Current" >&2
      return 1
    fi
    if [[ "$(dirname "$candidate")" != "$(cd "$versions_dir" && pwd -P)" ]]; then
      echo "ERROR: Sparkle Versions/Current resolves outside the framework versions directory: $versions_dir/Current" >&2
      return 1
    fi
    printf '%s\n' "$candidate"
    return 0
  fi

  shopt -s nullglob
  for candidate in "$versions_dir"/*; do
    [[ -d "$candidate" ]] && version_dirs+=("$candidate")
  done
  shopt -u nullglob

  case "${#version_dirs[@]}" in
    1)
      printf '%s\n' "$(cd "${version_dirs[0]}" && pwd -P)"
      ;;
    0)
      echo "ERROR: Sparkle framework has no version directory under: $versions_dir" >&2
      return 1
      ;;
    *)
      echo "ERROR: Sparkle framework has multiple version directories and no Versions/Current symlink: $versions_dir" >&2
      return 1
      ;;
  esac
}

sign_sparkle_target() {
  local target="$1"

  codesign \
    --force \
    --timestamp \
    --options runtime \
    --sign "$DEVELOPER_ID_IDENTITY" \
    "$target"
}

sign_sparkle_framework() {
  local sparkle="$APP_PATH/Contents/Frameworks/Sparkle.framework"
  local version_dir

  if [[ ! -d "$sparkle" ]]; then
    echo "ERROR: Missing Sparkle framework at $sparkle" >&2
    return 1
  fi

  version_dir=$(resolve_sparkle_version_dir "$sparkle")

  sign_sparkle_target "$version_dir/Sparkle"
  sign_sparkle_target "$version_dir/Autoupdate"
  sign_sparkle_target "$version_dir/Updater.app/Contents/MacOS/Updater"
  sign_sparkle_target "$version_dir/Updater.app"
  sign_sparkle_target "$version_dir/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"
  sign_sparkle_target "$version_dir/XPCServices/Downloader.xpc"
  sign_sparkle_target "$version_dir/XPCServices/Installer.xpc/Contents/MacOS/Installer"
  sign_sparkle_target "$version_dir/XPCServices/Installer.xpc"
  sign_sparkle_target "$version_dir"
  sign_sparkle_target "$sparkle"
}

package_dmg() {
  rm -rf "$STAGING_DIR"
  mkdir -p "$STAGING_DIR"
  cp -R "$APP_PATH" "$STAGING_DIR/"
  ln -s /Applications "$STAGING_DIR/Applications"

  rm -f "$DMG_PATH"
  hdiutil create \
    -volname "StorageScanner" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"
}

notarize_dmg() {
  if [[ "${RELEASE_SKIP_NOTARIZATION:-0}" == "1" ]]; then
    return 0
  fi

  local notary_args_output
  local notary_submit_output
  local notary_submission_id notary_status
  local -a args=()

  if ! notary_args_output=$(storage_scanner_notarytool_args); then
    echo "ERROR: Configure NOTARYTOOL_PROFILE or NOTARYTOOL_API_KEY_* for notarization." >&2
    return 1
  fi

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    args+=("$line")
  done <<<"$notary_args_output"

  notary_submit_output=$(xcrun notarytool submit "$DMG_PATH" "${args[@]}" --wait --output-format json)
  notary_submission_id=$(ruby -rjson -e 'data = JSON.parse(STDIN.read); puts data.fetch("id")' <<<"$notary_submit_output")
  notary_status=$(ruby -rjson -e 'data = JSON.parse(STDIN.read); puts data.fetch("status")' <<<"$notary_submit_output")

  if [[ "$notary_status" != "Accepted" ]]; then
    echo "ERROR: Notarization for $DMG_PATH finished with status $notary_status (submission $notary_submission_id)." >&2
    xcrun notarytool log "$notary_submission_id" "${args[@]}"
    return 1
  fi

  xcrun stapler staple "$DMG_PATH"
  spctl -a -t open -vv "$DMG_PATH"
}

build_sparkle_tool() {
  storage_scanner_release_generate_appcast_tool "$SPARKLE_CHECKOUT" "$SPARKLE_DERIVED_DATA_DIR" "$PACKAGE_CACHE_DIR"
}

create_zip() {
  rm -f "$ZIP_PATH"
  ditto --norsrc -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
}

generate_appcast() {
  local tool prefix appcast_dir key_args=()

  tool=$(build_sparkle_tool)
  prefix="$DOWNLOAD_URL_PREFIX"
  appcast_dir="$ARTIFACTS_DIR/appcast-input"

  rm -rf "$appcast_dir"
  mkdir -p "$appcast_dir"
  cp "$ZIP_PATH" "$appcast_dir/"

  if SPARKLE_KEY_FILE=$(storage_scanner_sparkle_key_file "$ROOT" 2>/dev/null); then
    key_args=(--ed-key-file "$SPARKLE_KEY_FILE")
  elif [[ "$MODE" == "publish" || "$MODE" == "upload" ]]; then
    echo "ERROR: SPARKLE_PRIVATE_KEY_FILE or SPARKLE_PRIVATE_KEY is required to generate the signed appcast for publish/upload mode." >&2
    return 1
  fi

  if ((${#key_args[@]})); then
    "$tool" "${key_args[@]}" --download-url-prefix "$prefix" -o "$APPCAST_PATH" "$appcast_dir"
  else
    "$tool" --download-url-prefix "$prefix" -o "$APPCAST_PATH" "$appcast_dir"
  fi
}

publish_release() {
  local tag repo

  repo=$(storage_scanner_repo_slug)
  tag=$(storage_scanner_release_tag)

  if ! command -v gh >/dev/null 2>&1; then
    echo "ERROR: gh is required to create the GitHub release." >&2
    return 1
  fi

  gh release create "$tag" "$DMG_PATH" "$ZIP_PATH" \
    --repo "$repo" \
    --title "StorageScanner ${MARKETING_VERSION}" \
    --generate-notes

  generate_appcast
}

upload_release() {
  local tag repo

  repo=$(storage_scanner_repo_slug)
  tag=$(storage_scanner_release_tag)

  if ! command -v gh >/dev/null 2>&1; then
    echo "ERROR: gh is required to upload GitHub release assets." >&2
    return 1
  fi

  gh release upload "$tag" "$DMG_PATH" "$ZIP_PATH" \
    --repo "$repo" \
    --clobber
}

main() {
  case "$MODE" in
    -h|--help|help)
      usage
      ;;
    local)
      build_release_app
      resolve_signing_options
      sign_release_app
      package_dmg
      notarize_dmg
      create_zip
      generate_appcast
      printf 'Local release complete.\n'
      printf 'App: %s\n' "$APP_PATH"
      printf 'DMG: %s\n' "$DMG_PATH"
      printf 'ZIP: %s\n' "$ZIP_PATH"
      printf 'Appcast: %s\n' "$APPCAST_PATH"
      ;;
    publish)
      build_release_app
      resolve_signing_options
      sign_release_app
      package_dmg
      notarize_dmg
      create_zip
      generate_appcast
      publish_release
      cp "$APPCAST_PATH" "$ROOT/appcast.xml"
      printf 'Publish complete.\n'
      printf 'GitHub release tag: %s\n' "$(storage_scanner_release_tag)"
      printf 'Appcast updated at: %s\n' "$ROOT/appcast.xml"
      ;;
    upload)
      build_release_app
      resolve_signing_options
      sign_release_app
      package_dmg
      notarize_dmg
      create_zip
      generate_appcast
      upload_release
      cp "$APPCAST_PATH" "$ROOT/appcast.xml"
      printf 'Upload complete.\n'
      printf 'GitHub release tag: %s\n' "$(storage_scanner_release_tag)"
      printf 'Appcast updated at: %s\n' "$ROOT/appcast.xml"
      ;;
    appcast)
      generate_appcast
      printf 'Appcast regenerated at %s\n' "$APPCAST_PATH"
      ;;
    *)
      echo "ERROR: Unknown mode: $MODE" >&2
      usage
      exit 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
