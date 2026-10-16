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
reproducible for a given Xcode version: `scripts/verify-reproducible.sh` shows two builds with the same
toolchain are byte-identical. Builds from different Xcode versions differ, so compare using the Xcode
version named in the release notes.

**Current status:** published downloads are **unsigned pre-releases** (no Apple Developer ID, not
notarised). Verify them with the SHA-256 file and `gh attestation verify <dmg> -R ahsansabir30/StorageBar`, which proves the file was built by this repository's workflow.
macOS asks for a one-time *Open Anyway* approval; never disable Gatekeeper.

## Supported versions
Only the latest release receives fixes.
