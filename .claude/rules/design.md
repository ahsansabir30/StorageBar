# Design decisions (StorageBar)

A deliberately small set of rules. Prefer semantic system styles over constants.

## Principles
- Native first: system controls (`Form(.grouped)`, `Picker`, `Toggle`), system fonts, SF Symbols, semantic colours. No custom background on the popup: the `NSPopover` supplies the system material. No gradients, shadows, cards, or glass effects of our own.
- One focal point per surface. Popup: the available-space figure. Everything else is `.secondary` and smaller.
- Every element earns its place; no explanatory paragraphs. One short sentence maximum for error/permission notes.
- No animation. State changes are immediate (also satisfies Reduce Motion).

## Type scale (all system font)
| Role | Style |
|---|---|
| Headline figure | `.system(size: 34, weight: .semibold)`, `.monospacedDigit()`; unit in `.title3` `.secondary` |
| Titles | `.headline` |
| Labels, rows | `.body` (default) |
| Supporting lines | `.subheadline`, `.secondary` |
| Metadata, captions | `.caption`, `.secondary` (never `.tertiary`: contrast) |

Numbers that change use `.monospacedDigit()`.

## Spacing and shape
- Popup: width 300, 16 pt horizontal margins, 14 pt between groups, 8-12 pt within groups.
- Menu-style rows: 8 pt horizontal / 5 pt vertical padding, 6 pt continuous corner radius, hover fill `Color.primary.opacity(0.08)`. Rows extend 8 pt into the margin (`.padding(.horizontal, -8)` on the group) so highlights match system menus.
- Capacity bar: 8 pt capsule, `.quaternary` track, accent fill; orange at warning, red at critical.

## Icons
SF Symbols only, default weight, one 18 pt column for row icons, `.secondary` colour. Menu bar uses `internaldrive`.

## Accessibility
- Combine read-only groups into one element with a full spoken sentence; hide decorative bars.
- Controls keep their own elements; each has an `accessibilityIdentifier`.
- The status item button has a spoken label ("275.1 GB available") via `DisplayFormat.spokenText`.
- The popup is an NSMenu custom-view item (keeps an auto-hidden menu bar revealed, closes on Esc/outside click); menu items cannot take key equivalents, so rows show no ⌘ hints.

## Preferences structure
General (launch at login, refresh) · Appearance (menu bar format, disk icon) · Notifications (alerts, warn threshold). Add a setting only if most users would change it.

## Verifying visuals
Screen capture is unavailable to tooling by default. Use `RenderPreviews` (`TEST_RUNNER_STORAGEBAR_RENDER=1`) to render views offscreen in light and dark, and say that renders are not screenshots of the live menu bar.
