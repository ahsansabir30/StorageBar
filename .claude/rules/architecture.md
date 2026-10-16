# Architecture standards (StorageBar)

Full description and metric definitions: `docs/ARCHITECTURE.md`.

## Layers and dependencies
- `Core/` (logic, no SwiftUI/AppKit UI types) <- `Views/` (SwiftUI) <- `StorageBarApp`. Dependencies point inward only; `Core/` never imports `Views/`.
- `AppModel` is the single composition root: constructs services, injects dependencies, starts polling. It contains wiring, not business rules.
- System boundaries sit behind small protocols so tests can substitute fakes: `StorageProviding`, `Notifying`, `LoginItemControlling`. Add a protocol only where a real boundary (OS service) exists. No protocols for pure functions.
- No third-party packages. Justify in the PR/commit message and `docs/ARCHITECTURE.md` before adding any.

## Storage monitoring
- Read capacity with `URLResourceValues` on the startup volume only. Never enumerate directories, never touch user files, never request Full Disk Access.
- Metrics (see `StorageSnapshot`): available = important-usage capacity (free + purgeable), fallback free; used = total - available. Do not sum System and Data APFS volumes.
- Failure keeps the last good snapshot and sets `lastError`; the menu bar must not flicker or blank on transient errors.
- Refresh triggers: interval loop, manual button, popup open, wake from sleep. Overlapping refreshes coalesce.

## State & persistence
- `Preferences` is the only `UserDefaults` consumer; values validated on read (invalid -> default) and clamped on write.
- Launch-at-login state is owned by `SMAppService`; read it, don't mirror it into defaults.
- Notification dedupe state is in memory (`AlertGate`); no persistence needed.

## Performance & energy
- Idle cost must be near zero: one sleeping task, sleep tolerance >= 10%, no timers, no polling of UI, no observers beyond wake.
- Keep observed surface small: views read only the properties they render.
- No network, no telemetry, no logging of volume data. Measure (`ps`, Instruments) before claiming numbers.

## Platform
- macOS 15+, arm64, App Sandbox with no extra entitlements, hardened runtime, `LSUIElement`.
- No private APIs and no attempts to modify system UI such as the battery indicator.
