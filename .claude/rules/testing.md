# Testing standards (StorageBar)

Complements ECC's `tdd-workflow` skill; see CLAUDE.md for commands.

## Process
- Logic changes start with a failing test (Red), minimal fix (Green), then refactor. Bug fixes begin with a regression test that fails first.
- All unit tests must pass and `xcodebuild analyze` must be clean before committing Swift changes.
- Report results exactly: passed, failed, skipped. A skipped test is never "passed"; unrun tests are never "verified".

## Unit tests (`StorageBarTests`, Swift Testing)
- Framework: Swift Testing (`@Test`, `#expect`, `@Suite` via `struct`), parameterised with `arguments:` for boundary tables. XCTest only where Swift Testing cannot (UI tests).
- Cover: metric calculations, byte/percent formatting, display formats, threshold boundaries and alert dedupe/hysteresis, preferences persistence and corrupt-value fallback, monitor success/failure/coalescing/polling, notification gating, permission and login-item handling.
- Isolate with fakes: `actor` fakes for `StorageProviding`/`Notifying`, throwaway `UserDefaults(suiteName: UUID)` for preferences. Never touch `UserDefaults.standard`, the real notification center or the login item.
- One real-system test is allowed for the volume provider (`/` plausibility, bad path throws); it asserts invariants, never exact values.
- Avoid timing flakiness: poll with a deadline instead of fixed sleeps; use the smallest intervals the test needs.
- Every test must be able to fail: assert outcomes, not just that code ran.

## UI tests (`StorageBarUITests`, XCTest/XCUITest)
- Launch the real app; locate the status item by `accessibilityIdentifier` (`menuBarLabel`) and popup actions by their ids.
- Need Accessibility access and a visible menu bar. When the status item is not hittable (auto-hidden bar), skip with `XCTSkipUnless` and a reason; never loosen assertions to pass.
- Keep UI tests few and about user-visible flows: status item shows a storage value, popup exposes all actions, Preferences opens.

## Not automatable here
- System notification permission prompts, Login Items approval, and visual appearance in light/dark need manual verification; record what was and was not checked.
