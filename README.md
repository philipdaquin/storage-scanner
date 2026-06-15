# StorageScanner

StorageScanner is a SwiftUI macOS app for understanding disk usage with a UI inspired by `ncdu`.

It can scan the system root or a chosen folder, build a navigable size tree, and let you explore the results in both list and treemap views without re-scanning the filesystem every time you change the UI.

## What It Does

- Scans the full macOS filesystem root or a selected folder.
- Builds a tree of folders and files with sizes, modification dates, and trashability info.
- Lets you navigate with breadcrumbs and drill into folders.
- Switches between a detailed list view and a treemap map view.
- Shows scan progress while the scan is running.
- Filters the current tree by categories like Applications, Documents, Downloads, and Media.
- Selects items and moves them to Trash from inside the app.
- Rescans the current target when you want fresh data.

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

## Notes

- Scanning protected system locations may require macOS permissions.
- Large filesystems can still take time to scan, but the app avoids unnecessary reprocessing after the scan completes.
- The project is a local macOS app, not a packaged release.

## License

This project is released under the terms of the Unlicense. See [LICENSE](LICENSE) for details.
