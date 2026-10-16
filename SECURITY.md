# Security policy

## Reporting a vulnerability
Please report suspected vulnerabilities privately through GitHub:
**Security › Report a vulnerability** on https://github.com/ahsansabir30/StorageBar.
Do not open a public issue for security problems. Include the version, macOS version and steps to reproduce.

## What StorageBar does and does not do
- Reads the capacity of the startup volume. Nothing else on disk.
- No network access (no network entitlement, no networking code), no telemetry, no accounts.
- App Sandbox is the only entitlement. No Full Disk Access, no helper tools, no auto-updater.
- Optional notifications and launch at login are off until you enable them.

## Verifying a download
Releases are only published when they are Developer ID signed and notarised (see `docs/RELEASING.md`).
Check the SHA-256 file, `spctl --assess` and `codesign -dv` as described there. The build is
reproducible: `scripts/verify-reproducible.sh` shows two builds are byte-identical.

**Current status:** no signed or notarised release has been published yet. Builds you make
yourself from source are ad-hoc signed and meant for your own Mac.

## Supported versions
Only the latest release receives fixes.
