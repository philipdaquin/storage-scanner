# StorageScanner

StorageScanner is a SwiftUI macOS app for understanding disk usage with a UI inspired by `ncdu`.

It scans a Mac filesystem once, builds a navigable size tree, and lets you explore the results in a list or treemap view without re-scanning every time you switch views.

## What It Does

- Scans the full macOS filesystem root or a selected folder.
- Builds a tree of folders and files with sizes, modification dates, and trashability info.
- Lets you navigate with breadcrumbs and drill into folders.
- Switches between a detailed list view and a treemap map view.
- Shows scan progress while the scan is running.
- Scans the system root or a chosen folder from the `Scan Disk` action.
- Lets you select items and move them to Trash from inside the app.

## How It Works

The scanner walks the filesystem once, records the results into an in-memory tree, and then the UI renders that captured tree. That keeps view changes fast and avoids repeated filesystem work after the scan finishes.

On macOS, root scans need special handling because the sealed system volume and writable data volume expose the same content through multiple paths. StorageScanner accounts for that so the root scan stays much closer to `ncdu`-style accounting and avoids obvious double-counting of top-level system-volume aliases.

## Requirements

- macOS 12.3 or later
- Xcode 16 or later

## Run In Xcode

1. Open `StorageScanner.xcodeproj`.
2. Select the `StorageScanner` scheme.
3. Build and run.
4. Click `Scan Disk` to inspect the full system, or `Scan Folder` to choose a directory.

## Release Pipeline

The repository includes a local-first macOS release script at `Scripts/release.sh`.

Use it like this:

```bash
Scripts/release.sh local
Scripts/release.sh publish
```

`local` builds the signed app bundle, creates the DMG, creates the Sparkle ZIP, and generates `appcast.xml` in a release workspace.

`publish` performs the same local release work, notarizes and staples the DMG, creates a GitHub Release, uploads the DMG and ZIP, and refreshes the appcast download URLs for the published assets.

`upload` is the GitHub Actions-friendly mode. It does the same build/sign/notarize/package work, uploads the DMG and ZIP to an existing release, and refreshes `appcast.xml` for the GitHub-hosted download URLs.

The script reads signing and update credentials from `release.env` when present. A sample file is available at `release.env.example`.

Before publishing, run the release doctor:

```bash
Scripts/release-doctor.sh --github
```

The doctor checks local release tools, local signing/update environment values, and required GitHub Actions secret names without printing secret values. A publish run is not ready until this command reports that the StorageScanner release inputs look ready.

## GitHub Actions

The release workflow lives at `.github/workflows/release.yml`.

It can run automatically when a GitHub Release is published, or manually from GitHub Actions with `publish` to create a GitHub Release or `upload` to push assets to an existing release.

It expects these secrets in GitHub:

- `DEVELOPER_ID_IDENTITY`
- `DEVELOPER_ID_CERTIFICATE_P12_BASE64`
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`
- `NOTARYTOOL_PROFILE` or `NOTARYTOOL_API_KEY_P8`, `NOTARYTOOL_API_KEY_ID`, `NOTARYTOOL_API_ISSUER_ID`
- `SPARKLE_PRIVATE_KEY` or the legacy `SPARKLE_PRIVATE_KEY_FILE` secret containing the private key text
- `SPARKLE_PUBLIC_ED_KEY`

To create the certificate secrets, export your Developer ID Application certificate from Keychain Access as a password-protected `.p12`, then run:

```bash
base64 -i /path/to/DeveloperIDApplication.p12 | pbcopy
gh secret set DEVELOPER_ID_CERTIFICATE_P12_BASE64 --repo philipdaquin/storage-scanner
gh secret set DEVELOPER_ID_CERTIFICATE_PASSWORD --repo philipdaquin/storage-scanner
```

Paste the base64 output for `DEVELOPER_ID_CERTIFICATE_P12_BASE64`, and paste the `.p12` export password for `DEVELOPER_ID_CERTIFICATE_PASSWORD`.

After a successful publish or upload, the workflow uploads the DMG and ZIP, then commits the updated `appcast.xml` back to the default branch.

The CI workflow also uploads a downloadable artifact bundle so you can grab the DMG and ZIP directly from the successful Actions run.

## Notes

- Scanning protected system locations may require macOS permissions.
- Large filesystems can still take time to scan, but the app avoids unnecessary reprocessing after the scan completes.
- The release flow is designed to support a signed Developer ID `.app`, a direct-download DMG, a Sparkle ZIP, and a GitHub release feed.

## License

This project is released under the terms of the Unlicense. See [LICENSE](LICENSE) for details.
