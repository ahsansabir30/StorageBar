# StorageBar

A small native macOS menu bar app that shows the free space on your startup disk, e.g. `274 GB`.
Click it for details. Built with Swift 6 and SwiftUI. No dependencies, no network, no telemetry.

- Menu bar shows a disk icon and free space (e.g. `[disk] 128 GB`); free GB, free %, used % or icon + GB are selectable, and the icon can be hidden.
- Popup: disk name, total, used, available, % used, usage bar, last refresh, Refresh,
  Open Storage Settings, Preferences, Quit.
- Refreshes every 60 s by default (30 s / 1 / 5 / 15 min available), on popup open, and after wake.
- Optional low-storage notifications (default warn below 10 %, critical below 5 % available;
  once per state, permission requested only when you turn them on).
- Optional launch at login (`SMAppService`).
- Requires macOS 15 or later, Apple Silicon. Sandboxed, hardened runtime, no Dock icon.

## Build and run

Requires Xcode (developed with Xcode 27.1, macOS 27 SDK) selected via `xcode-select`.

```bash
xcodebuild -project StorageBar.xcodeproj -scheme StorageBar -configuration Release \
  -derivedDataPath /tmp/StorageBar-dd build
open /tmp/StorageBar-dd/Build/Products/Release/StorageBar.app
```

Or open `StorageBar.xcodeproj` in Xcode and press Run.

Build output must live **outside `~/Documents`/iCloud-synced folders**; file-provider extended
attributes make `codesign` fail with "resource fork, Finder information, or similar detritus".

### Install

```bash
cp -R /tmp/StorageBar-dd/Build/Products/Release/StorageBar.app /Applications/
```

The build is **ad-hoc signed ("Sign to Run Locally")**. It is not notarised or Developer ID signed,
so it runs on the Mac that built it. Copying it to another Mac triggers Gatekeeper; distributing
it properly needs an Apple Developer ID and notarisation, which this project does not include.

### Putting it beside the battery icon

macOS decides menu bar order. Hold **⌘** and drag the StorageBar item next to the battery icon.
On recent macOS versions you can also manage items in System Settings → Menu Bar. StorageBar cannot
and does not modify Apple's battery indicator.

### Launch at login

Preferences → Launch at login. If macOS reports "requires approval", approve StorageBar in
System Settings → General → Login Items. Ad-hoc signed builds may need that approval.

## Tests

```bash
DD=/tmp/StorageBar-dd
xcodebuild -project StorageBar.xcodeproj -scheme StorageBar -derivedDataPath $DD -only-testing:StorageBarTests test
xcodebuild -project StorageBar.xcodeproj -scheme StorageBar -derivedDataPath $DD -only-testing:StorageBarUITests test
xcodebuild -project StorageBar.xcodeproj -scheme StorageBar -derivedDataPath $DD analyze
```

- Unit tests (Swift Testing, 49): metric calculations, byte and percent formatting, display
  formats, thresholds and alert de-duplication, preferences persistence, monitor refresh/error
  behaviour, notification and login-item handling, app wiring.
- UI tests (XCUITest, 3): status item shows a storage value; popup shows all actions; Preferences
  opens. They need Accessibility permission for the test runner and a **visible menu bar**. If the
  menu bar is auto-hidden, the two popup tests are reported as *skipped*, not passed.

## Metrics

| Shown | Definition |
|---|---|
| Available (headline) | `volumeAvailableCapacityForImportantUsage`: free plus purgeable space, as Finder and System Settings report it. Falls back to raw free space if unavailable. |
| Used | Total − Available |
| Percent | Available or Used ÷ Total, rounded to a whole percent |
| Purgeable (popup, if > 0) | Available − raw free space |

Sizes use decimal units (1 GB = 10⁹ bytes) like Finder, rounded down so free space is never
overstated. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Privacy

Reads volume capacity only. It does not scan files, request Full Disk Access, use the network,
or collect any data. Preferences are stored locally in `UserDefaults`.

## Project layout

See `CLAUDE.md` and `docs/ARCHITECTURE.md` (which also lists the ECC agents and skills used).
