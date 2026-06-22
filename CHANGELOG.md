# Changelog

## 0.0.2 — 2026-06-22

### Added
- Category tabs now prewarm from the completed scan tree so switching between views feels immediate.

### Changed
- The Xcode project version settings now stay aligned with `version.env`.

### Fixed
- Category switching no longer blocks on building the filtered tree on the main thread.
- The current scan tree is reused for category views instead of triggering new scans.

## 0.0.1 — 2026-06-16

### Added
- Sparkle auto-update support.
- A signed and notarized macOS release pipeline with GitHub Release publishing.

### Changed
- The app now keeps a captured scan tree in memory so switching views does not rescan the filesystem.
- Root scans better account for macOS system volume layout so top-level usage is easier to understand.
- The release flow now produces a direct-download DMG and a Sparkle ZIP for updates.

### Fixed
- Scan category switching no longer starts a fresh scan on its own.
- Double-counting at the macOS root volume is reduced by the scanner's accounting logic.

## Unreleased

### Added
- Future release notes go here.

### Fixed
- Future fixes go here.
