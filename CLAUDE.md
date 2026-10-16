# StorageBar

Native macOS menu bar utility that shows free space on the startup volume (e.g. `128 GB`).
Click for a popup (name, total, used, available, % used, usage bar, last refresh, Refresh,
Open Storage Settings, Preferences, Quit). Optional low-storage notifications and launch at login.
Targets macOS 15+ on Apple Silicon (arm64). Swift 6, SwiftUI views hosted by an AppKit `NSStatusItem` + `NSMenu`. No third-party
dependencies, no network, no telemetry, no private APIs, no Full Disk Access, no file scanning.

## Commands

Xcode (`/Applications/Xcode.app`) is the build system. Build output goes **outside `~/Documents`**
(file-provider xattrs break `codesign`), e.g. `-derivedDataPath /tmp/StorageBar-dd`.

```bash
DD=/tmp/StorageBar-dd
xcodebuild -project StorageBar.xcodeproj -scheme StorageBar -derivedDataPath $DD build
xcodebuild -project StorageBar.xcodeproj -scheme StorageBar -derivedDataPath $DD -only-testing:StorageBarTests test
xcodebuild -project StorageBar.xcodeproj -scheme StorageBar -derivedDataPath $DD -only-testing:StorageBarUITests test
xcodebuild -project StorageBar.xcodeproj -scheme StorageBar -derivedDataPath $DD analyze
xcodebuild -project StorageBar.xcodeproj -scheme StorageBar -configuration Release -derivedDataPath $DD build
```

Redirect `test` output to a file and grep it; the hosted app logs heavily. UI tests need
Accessibility permission for the runner and a visible (not auto-hidden) menu bar, otherwise the
popup tests skip. Report skipped tests as skipped, never as passed.

## Layout

```
StorageBar/            app target (Xcode folder-synchronised group: new files are picked up automatically)
  Core/                logic with no UI: snapshot + provider, formatting, thresholds, preferences,
                       monitor, system services (notifications, login item)
  Views/               SwiftUI: PopupView, PreferencesView
  AppModel.swift       composition root (wiring only)
  StatusItemController.swift  NSStatusItem (autosaveName "StorageBar"), NSMenu hosting the SwiftUI popup, Preferences window
  StorageBarApp.swift  @main + AppDelegate (single-instance guard, reopen reveals popup)
  AppInfo.swift        About panel, repo URL, licence
  Assets.xcassets      app icon (regenerate with scripts/make-icon.swift)
StorageBarTests/       Swift Testing unit tests (hosted by the app)
StorageBarUITests/     XCUITest against the launched app
Config/                entitlements (sandbox only)
docs/ARCHITECTURE.md   design and metric definitions
docs/RELEASING.md      signing, notarisation, release process
scripts/               build-release.sh (DMG), make-icon.swift
.github/workflows/     ci.yml, prerelease.yml (unsigned), release.yml (signed; needs Apple credentials)
.claude/rules/         swift.md, architecture.md, testing.md, design.md (UI decisions)
```

Settings live in `project.pbxproj`; `LSUIElement` is set via `INFOPLIST_KEY_LSUIElement` (no Info.plist
file). Edit the pbxproj by hand only for build settings/targets; never list source files in it.

## Rules that matter most

- Metric definitions are fixed (see `StorageSnapshot` doc comment): headline = available for
  important usage (free + purgeable), used = total - available. Change them only with tests.
- Core types stay free of SwiftUI/AppKit so they unit-test without a UI.
- Zero work between refreshes: one sleeping `Task`, tolerance on the sleep, no timers, no scanning.
- Sandbox stays on with no extra entitlements. Adding any entitlement needs a stated reason.
- Notifications and login item are opt-in and permission-based; never prompt at launch.
- Tests first for logic changes (Red, Green, Refactor). All unit tests must pass before commit.
- UI changes follow `.claude/rules/design.md`: native controls, one focal figure, no custom materials or animation.
- Detailed standards: `.claude/rules/*.md`. Do not duplicate them here or restate ECC's rules.

## Git

Branch from `main` (`feature/…`, `fix/…`), open a PR, merge when CI is green; never force-push `main`.
Push only after unit tests and `analyze` pass. Commits use the GitHub noreply address, not a personal email.

Conventional Commits (`feat:`, `fix:`, `test:`, `docs:`, `refactor:`, `chore:`), small focused
commits, imperative subject under 72 chars, body explains why. Never commit `build/`, derived
data, or `*.xcuserstate`. Run unit tests and `analyze` before committing Swift changes.

## ECC (installed plugin `ecc@ecc`; do not re-install or copy its content here)

Use what exists, only when it fits the task:
- Plan: `/plan` (waits for confirmation); `planner` / `architect` agents for larger changes.
- Implement: `tdd-workflow` skill, `tdd-guide` agent; `swiftui-patterns`, `swift-concurrency-6-2`,
  `swift-protocol-di-testing` skills for patterns.
- Review: `/code-review`, `swift-reviewer` agent for Swift diffs, `security-reviewer` for
  privacy/sandbox changes, `performance-optimizer` for energy questions (analysis only).
- Build failures: `/build-fix` or `swift-build-resolver` agent.
- Docs: `doc-updater` agent. Final gate: `verification-loop` skill.
