<p align="center"><img src="docs/images/icon.png" width="96" alt="StorageBar icon"></p>

# StorageBar

A tiny native macOS menu bar app that shows how much free space your startup disk has, for example
`[disk] 274 GB`. Click it for details. No account, no network access, no telemetry.

<p align="center">
  <img src="docs/images/popup-light.png" width="300" alt="StorageBar popup, light appearance">
  <img src="docs/images/popup-dark.png" width="300" alt="StorageBar popup, dark appearance">
</p>
<p align="center"><sub>Renders of the real views. The popup is shown without the system menu frame and material.</sub></p>

## For users

### Requirements
macOS 15 (Sequoia) or later on an Apple silicon Mac. Developed and tested on macOS 26 (Tahoe).

### Install
StorageBar is **not signed with an Apple Developer ID and not notarised**, so macOS warns the first time
you open it. That is a one-time approval, and the download can be verified (see below). Only install it
if you trust this repository.

1. Download **StorageBar-x.y.z-unsigned.dmg** from the [Releases page](https://github.com/ahsansabir30/StorageBar/releases)
   (marked *Pre-release*).
2. Open it and drag **StorageBar** into **Applications**.
3. Open StorageBar. macOS says it can't verify the app: click **Done**.
4. Open **System Settings › Privacy & Security**, scroll to **Security**, and click **Open Anyway** next to
   the StorageBar message. Confirm with your password or Touch ID, then open StorageBar again.

Never disable Gatekeeper. If you'd rather not approve an unsigned app, build it yourself (Developers, below).

**Verify the download** (optional, recommended):
```bash
shasum -a 256 -c StorageBar-x.y.z-unsigned.dmg.sha256
gh attestation verify StorageBar-x.y.z-unsigned.dmg -R ahsansabir30/StorageBar
```
The attestation proves the file was built by this repository's workflow from a specific commit. The build is
reproducible *for a given Xcode version*: rebuilding with the same Xcode (named in the release notes) gives
byte-identical output. A different Xcode produces different, but equivalent, code.

### Put it next to the battery
macOS controls menu bar order. Hold **⌘ (Command)** and drag the StorageBar item to where you want it,
for example beside the battery icon. macOS remembers the position. If you use *Automatically hide and
show the menu bar*, move the pointer to the top of the screen first so the bar appears, then ⌘-drag.
Items can also be shown or hidden in System Settings › Menu Bar.

### Use it
- **Click** the item for disk name, available space, used space and percentage, a capacity bar and
  the time of the last update. The popup has Refresh, Storage Settings, Preferences and Quit; About is in Preferences.
- **Low storage:** when free space falls to the critical level (5 % by default), the menu bar icon and value turn red, and the icon shows even if you hid it.
- **Preferences** (from the popup): launch at login, refresh interval (default 1 minute),
  what the menu bar shows (free GB, free %, used %), the disk icon, and optional low-storage alerts
  (warning below 10 %, critical below 5 % by default; macOS asks for notification permission only when
  you turn alerts on).
- **Launch at login:** Preferences › General. If macOS says approval is needed, allow StorageBar in
  System Settings › General › Login Items.

### What the numbers mean
*Available* is free space plus space macOS can reclaim on demand (purgeable), as Finder and System
Settings report it. *Used* is total minus available. StorageBar only reads the startup disk's
capacity. It never looks at your files.

### Uninstall
Quit StorageBar (from its popup), turn off Launch at login if you enabled it, then delete
StorageBar from Applications. Optionally remove its settings:
`~/Library/Containers/com.ahsan.StorageBar`.

### Troubleshooting
| Problem | What to try |
|---|---|
| I can't see the item | The menu bar may be auto-hiding: move the pointer to the top edge. If the bar is crowded, items near the notch can be hidden; ⌘-drag other items away or remove some in System Settings › Menu Bar. Opening StorageBar again from Applications is designed to show its popup (not yet verified on screen). |
| I opened it twice | Only one copy runs; a second launch just shows the popup. |
| Launch at login does nothing | Approve it in System Settings › General › Login Items. |
| No low-storage alerts | Turn them on in Preferences and allow notifications in System Settings › Notifications. |

## For developers

### Requirements
Xcode 16 or later (developed with Xcode 27.1), Swift 6, macOS 15+ deployment target. No dependencies.

### Build and test
Build outside `~/Documents` or other iCloud-synced folders; file-provider attributes make `codesign`
fail.

```bash
DD=/tmp/StorageBar-dd
xcodebuild -project StorageBar.xcodeproj -scheme StorageBar -derivedDataPath $DD build
xcodebuild -project StorageBar.xcodeproj -scheme StorageBar -derivedDataPath $DD -only-testing:StorageBarTests test
xcodebuild -project StorageBar.xcodeproj -scheme StorageBar -derivedDataPath $DD analyze
open $DD/Build/Products/Debug/StorageBar.app
```

UI tests (`-only-testing:StorageBarUITests`) drive the real app. They need Accessibility permission for
the test runner and a visible menu bar; popup tests are *skipped*, not passed, when the bar is
auto-hidden. CI runs build, unit tests and static analysis only.

### Package a DMG
```bash
scripts/build-release.sh
```
Produces `dist/StorageBar-<version>-LOCAL-UNSIGNED.dmg` (ad-hoc signed, **not notarised**, for local
testing only) plus a SHA-256 file. With signing and notarisation credentials in the environment it
produces `dist/StorageBar.dmg`. See [docs/RELEASING.md](docs/RELEASING.md).

### Architecture
`Core/` holds all logic (snapshot, formatting, thresholds, preferences, polling monitor, system
services) with no UI dependencies. `Views/` is SwiftUI. `StatusItemController` owns the `NSStatusItem`,
the menu that hosts the popup, and the Preferences window. Details and metric definitions:
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Engineering and design rules: `CLAUDE.md` and
`.claude/rules/`.

### Git workflow
`main` stays releasable. Make changes on a short-lived branch (`feature/…`, `fix/…`), run the unit
tests and `analyze` locally, open a pull request, and merge once CI is green. Use Conventional Commits
(`feat:`, `fix:`, `docs:` …). Never force-push `main`.

### CI/CD
- `.github/workflows/ci.yml`: on pull requests and pushes to `main`: Release build, unit tests, static
  analysis, and a packaging dry run that uploads the *unsigned* DMG as a short-lived artefact.
- `.github/workflows/prerelease.yml`: manual. Tests, checks reproducibility, builds, attests build provenance
  and publishes an **unsigned pre-release** (tag `unsigned-vX.Y.Z`). No secrets involved.
- `.github/workflows/release.yml`: manual, for the day an Apple Developer ID exists. Signs, notarises,
  staples, verifies, checksums and publishes. It refuses to run, and publishes nothing, if any
  credential is missing.

### Security
See [SECURITY.md](SECURITY.md). `scripts/scan-secrets.py` (run in CI on the full history) fails the build
if any commit contains a credential-shaped string or a key/certificate file; GitHub secret scanning and push
protection are enabled as a second layer. Every build is checked by `scripts/build-release.sh`: the only
entitlement is the App Sandbox (no debugger-attach or network entitlements), no networking code is
linked, and no debug or test hooks are in the Release binary. `scripts/verify-reproducible.sh`
(also run in CI) builds twice in different directories and requires byte-identical output.

### Licence
[MIT](LICENSE).
