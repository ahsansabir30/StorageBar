# StorageBar architecture

## Overview

```
StorageBarApp (@main)
 └─ AppDelegate ── StatusItemController ── NSStatusItem (autosaveName "StorageBar"; title/icon from AppModel)
                      ├─ NSMenu with one custom-view item ── PopupView (SwiftUI)
                      └─ NSWindow ── PreferencesView
        views read ──▶ AppModel (composition root)
                             ├─ Preferences        UserDefaults-backed settings
                             ├─ StorageMonitor     polling + state (@MainActor @Observable)
                             │    └─ StorageProviding ◀── VolumeStorageProvider (URLResourceValues)
                             ├─ LowStorageAlerter  AlertGate + Notifying ◀── SystemNotifier (UNUserNotificationCenter)
                             └─ LoginItemControlling ◀── SystemLoginItem (SMAppService.mainApp)
```

**Why `NSStatusItem` instead of `MenuBarExtra`:** `MenuBarExtra` cannot be given a name, so macOS keys the item's position/visibility under the generic `Item-0` shared with other apps; it offers no control over popup dismissal (the popup is an `NSMenu` custom-view item because a real menu keeps an auto-hidden menu bar revealed while open, which a popover does not, and it closes natively on outside clicks and Esc). macOS still owns ordering: users ⌘-drag the item, and AppKit persists the position under the autosave name.

`Core/` holds all logic and compiles without UI. Views are thin. OS services sit behind three
protocols (`StorageProviding`, `Notifying`, `LoginItemControlling`) so tests use fakes.

## Data flow

1. `StorageMonitor.start(every:)` runs one `Task`: `refresh()`, then `Task.sleep(for:tolerance:)`.
2. `refresh()` awaits `provider.snapshot()` (off the main thread; one `resourceValues` call on `/`),
   publishes `snapshot`/`lastError`, releases its re-entrancy guard, then calls `onSnapshot`.
3. `onSnapshot` → `LowStorageAlerter.handle` → `AlertGate` decides → `Notifying.post`.
4. SwiftUI re-renders only views that read the changed properties (Observation).

Other refresh triggers: Refresh button, popup open (`.task`), wake from sleep
(`NSWorkspace.didWakeNotification`), interval change in Preferences.

## Metric definitions

| Name | Source / formula |
|---|---|
| Total | `volumeTotalCapacity` of `/` (the startup volume) |
| Free (raw) | `volumeAvailableCapacity`: blocks free right now |
| Available | `volumeAvailableCapacityForImportantUsage` (free + purgeable); falls back to Free; clamped to 0…Total |
| Purgeable | Available − Free (shown only if > 0) |
| Used | Total − Available |
| Available % / Used % | Available (or Used) ÷ Total, rounded; 0 when Total is 0 |

APFS: the startup volume's capacity keys describe the shared container, so System and Data
volumes are not summed and nothing is double-counted. No files are enumerated and no Full Disk
Access is needed.

## Alerts

`StorageThresholds`: warning is user-set (5–30 %, default 10); critical = warning ÷ 2 (default 5).
`AlertGate` notifies only when the level rises above the last notified level, and re-arms only after
available space recovers to ≥ warning + 1 point (hysteresis; recovery is tracked even while alerts
are off). If the system declines to deliver, the gate rolls back so the next refresh retries.
Permission is requested only when the user switches notifications on.

## Failure behaviour

A failed read keeps the last good snapshot (menu bar does not blank), sets `lastError`, and the
popup shows a warning. With no snapshot yet the label shows `-- GB`. Overlapping refreshes coalesce.

## Platform and security

macOS 15+, arm64, `LSUIElement` (no Dock icon), single instance (a second launch only reveals the popup), App Sandbox with no extra entitlements,
hardened runtime, ad-hoc signed. No network, telemetry, private APIs, or file scanning.
`INFOPLIST_KEY_*` build settings generate the Info.plist; there is no hand-written plist.

## Energy

Idle cost is one suspended task. Sleep tolerance is 10 % of the interval so wakeups can coalesce.
No timers, no UI polling, one notification observer (wake). The default 60 s interval and
the options (30 s…15 min) are user-controlled.

Measured (Release build, M4 MacBook Pro, idle, `ps` sampled every 10 s for ~1 minute): CPU 0.0 %
in six of seven samples (one 0.7 % sample), resident memory 78–86 MB (includes shared
SwiftUI/AppKit pages). `ps` is coarse; no Instruments energy trace was taken, so no energy-impact
figure is claimed.

## UI design

See `.claude/rules/design.md` for the type scale, spacing and component rules. Verification of visuals
uses offscreen renders (`RenderPreviews`), not screenshots of the live menu bar; screen capture is
blocked for tooling on this setup.

## Security properties (enforced in the build)
- Entitlements: App Sandbox only. `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` in Release keeps Xcode
  from adding `get-task-allow`; `build-release.sh` fails if any other entitlement appears.
- No networking symbols linked; no `STORAGEBAR_FAKE_FREE_PERCENT` or `XCTestConfigurationFilePath`
  strings in Release (both hooks are `#if DEBUG`).
- Reproducible Release link (`-Wl,-reproducible -Wl,-S`): two builds from different directories give
  byte-identical bundles (`scripts/verify-reproducible.sh`, run in CI).
- Debug builds use bundle id `com.ahsan.StorageBar.debug`, so tests and previews never touch the
  real app's sandbox container or settings.

## Known limitations

- Not notarised / Developer ID signed; runs on the building Mac. Login-item registration may
  require manual approval for ad-hoc signed builds.
- Redesigned visuals were inspected as offscreen renders only (light/dark, normal/low/critical/error). The live status item, the system popup material, hover/focus states and VoiceOver output were not observed.
- Popup UI tests are skipped when the menu bar is auto-hidden; notification permission prompts,
  Login Items approval, and light/dark appearance were not exercised automatically.
- No app icon asset (menu bar utilities have no Dock icon; Finder shows a generic icon).
- Timestamped snapshots always differ, so the label re-evaluates once per refresh. The
  performance review judged this negligible; not optimised.

## Development workflow (ECC)

ECC (`ecc@ecc`) is a user-level plugin; nothing is copied into the repo. Used on this project:

| Kind | Name | Used for |
|---|---|---|
| Command/skill | `ecc:plan` | Requirements, risks, phased plan; waited for confirmation |
| Agent | `ecc:swift-reviewer` | Review of Swift sources and tests (found alert-gate, polling-guard and test-gap issues; fixed with regression tests, low items noted) |
| Agent | `ecc:security-reviewer` | Privacy/sandbox/entitlement review (no Critical/High/Medium findings) |
| Agent | `ecc:performance-optimizer` | Analysis-only energy/CPU review (nothing worth changing) |
| Skills | `ecc:swiftui-patterns`, `ecc:liquid-glass-design` | Read for the UI redesign. Liquid Glass APIs were deliberately not applied: the `MenuBarExtra` window already supplies the system material, and custom glass would be the "approximation" the design brief rules out |
| Agent | `ecc:swift-reviewer` (2nd pass) | Redesign review: found the VoiceOver summary dropping state, the 1000 GB rounding edge, optional-shortcut helper |
| Agent | `ecc:a11y-architect` | Accessibility audit of the redesign: state conveyed by colour only, keyboard focus visibility, decorative text read aloud (fixed) |

Available and referenced in `CLAUDE.md` but not invoked: `tdd-workflow`, `tdd-guide`, `swiftui-patterns`,
`swift-concurrency-6-2`, `swift-protocol-di-testing`, `swift-build-resolver`, `/build-fix`,
`/code-review`, `doc-updater`, `verification-loop`. TDD was followed by hand: tests were written
alongside the logic, and regression tests were added for each review finding.
