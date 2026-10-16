# Swift & SwiftUI standards (StorageBar)

Complements ECC's general coding rules; only StorageBar-specific points here.

## Language
- Swift 6 language mode with `SWIFT_STRICT_CONCURRENCY = complete`. The build must have zero Swift warnings.
- Prefer value types (`struct`/`enum`). Classes only for observable state or identity (`Preferences`, `StorageMonitor`, `AppModel`).
- No force unwraps/`try!`/`fatalError` outside tests; the one allowed literal-URL force unwrap is a compile-time constant.
- Make illegal states unrepresentable: enums with raw values for persisted choices; clamp numeric input at the type (`StorageThresholds`).
- Access control: default internal; mark helpers `private`. No public API in an app target.
- Comments explain *why* or define a metric. No restating code, no commented-out code.

## SwiftUI
- State: `@Observable` classes held by `@State` at the App root; views take `let model` and read what they render. `@Bindable` only where a binding is needed.
- Views are small, declarative and free of logic: formatting and decisions live in `Core/` and are unit-tested.
- Native controls and system fonts/colors only (`.headline`, `.secondary`, `Form`/`.grouped`, SF Symbols). Support light/dark automatically; never hard-code colors except semantic status (orange/red).
- Every interactive element gets an `accessibilityIdentifier`; custom drawn views get an accessibility label and value.
- Menu bar label must stay compact: one short `Text`, optional SF Symbol.

## Concurrency
- UI-facing types are `@MainActor`. Blocking-capable work (`StorageProviding.snapshot()`) is `async` and non-isolated; never block the main thread.
- Long-lived work is one structured `Task` owned by its creator, cancelled on replacement/stop, capturing `self` weakly.
- Use `Task.sleep(for:tolerance:)`, never `Timer` or `DispatchSource`, for polling.
- Types crossing isolation boundaries are `Sendable` (snapshots are plain structs).

## Errors
- Domain errors are enums conforming to `LocalizedError` with user-presentable text.
- Never swallow errors silently: either surface (`lastError`), retain last good state and expose the failure, or document why ignoring is safe at the call site.
- Use `try?` only for best-effort cleanup or optional system calls where failure has no user impact.
