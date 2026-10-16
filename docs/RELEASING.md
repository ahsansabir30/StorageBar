# Releasing StorageBar

## Two release paths

- **Unsigned pre-release** (`prerelease.yml`, available now, free): publishes `StorageBar-X.Y.Z-unsigned.dmg`
  with a SHA-256 file and a GitHub build-provenance attestation under tag `unsigned-vX.Y.Z`. Users approve
  it once via System Settings › Privacy & Security › Open Anyway. Run it from Actions › *Unsigned
  pre-release*, entering the version.
- **Signed and notarised release** (`release.yml`): needs the Apple Developer Program (see below).

## Current status

| Capability | State |
|---|---|
| Reproducible Release build and DMG (`scripts/build-release.sh`) | Working, tested locally |
| Ad-hoc signed **local** DMG (`…-LOCAL-UNSIGNED.dmg`) | Working. **Not for distribution** |
| Developer ID signing | **Blocked: no Developer ID certificate exists on the build machine or in GitHub secrets** |
| Notarisation and stapling | **Blocked on the same credentials.** Script and workflow are written but have never run against Apple's service |
| `release.yml` workflow | Written; untested end to end for the same reason |

Until the steps below are done, nothing should be published as a download, and users must not be told
to bypass Gatekeeper.

## What you need (one-time)

1. **Apple Developer Program membership** (paid). Notarisation and Developer ID certificates require it.
2. A **Developer ID Application** certificate. Create it in Xcode › Settings › Accounts › Manage
   Certificates, or at developer.apple.com › Certificates. Export it from Keychain Access as a `.p12`
   with a strong password.
3. An **App Store Connect API key** for notarisation (Users and Access › Integrations › Team Keys,
   role *Developer*). Download the `.p8` once; note the **Key ID** and **Issuer ID**.
4. Your **Team ID** (developer.apple.com › Membership).

Keep the `.p12`, its password and the `.p8` out of the repository and out of chat. They go only into
GitHub secrets or your keychain.

## Repository protections (already configured)

- Ruleset **Protect main**: changes only by pull request, the `build-and-test` check must pass, no
  force-push, no deletion. No bypass actors.
- Ruleset **Protect release tags**: `v*` tags cannot be moved or deleted.
- Environment **release**: required reviewer `ahsansabir30`, deployable from `main` only. The release
  job waits for that approval before any step (and any secret) is available.
- Actions: only GitHub-owned actions are allowed and every `uses:` must be pinned to a commit SHA.
  Dependabot proposes weekly updates to those pins. Secret scanning, push protection, Dependabot
  alerts/security updates and private vulnerability reporting are on.

## GitHub secrets

Store the secrets **in the `release` Environment** (Settings › Environments › release), or with the CLI
(prompts for the value; add `--env release`):

```bash
base64 -i DeveloperID.p12 | gh secret set DEVELOPER_ID_CERT_BASE64 --env release
gh secret set DEVELOPER_ID_CERT_PASSWORD --env release
gh secret set DEVELOPER_ID_IDENTITY --env release   # e.g. Developer ID Application: Your Name (TEAMID)
gh secret set APPLE_TEAM_ID --env release
base64 -i AuthKey_XXXX.p8 | gh secret set NOTARY_KEY_BASE64 --env release
gh secret set NOTARY_KEY_ID --env release
gh secret set NOTARY_ISSUER_ID --env release
```

## Cutting a release

1. Update `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in the app target; merge to `main` via PR.
2. Actions › **Release** › Run workflow on `main`, entering the same version (e.g. `1.0.0`).
3. The workflow: checks secrets and that the tag is new, runs unit tests, imports the certificate into
   a temporary keychain, builds with the hardened runtime, signs, packages the DMG, signs the DMG,
   submits it to Apple notarisation and waits, staples the ticket, verifies with `spctl`, writes a
   SHA-256 file, then creates release `v<version>` with `StorageBar.dmg` and its checksum.
   Any failure stops before anything is published. The keychain and key files are deleted afterwards.

## Reproducing the build

`scripts/verify-reproducible.sh` builds twice in different directories and requires identical bundles.
To check a published app against the source, check out the release tag, run
`scripts/build-release.sh` without credentials, and compare the `Contents/MacOS/StorageBar` hash of the
unsigned build with the app inside the DMG (ignore the code signature itself, which differs by
design: `codesign --remove-signature` on a copy of each before hashing).

## Verifying a release by hand

```bash
shasum -a 256 -c StorageBar.dmg.sha256
spctl --assess --type open --context context:primary-signature -v StorageBar.dmg
xcrun stapler validate StorageBar.dmg
# after copying the app out of the DMG:
spctl --assess --type execute -v /Applications/StorageBar.app
codesign -dv --verbose=4 /Applications/StorageBar.app   # expect Authority=Developer ID Application…
```

## Local development artefact

`scripts/build-release.sh` with no credentials writes `dist/StorageBar-<version>-LOCAL-UNSIGNED.dmg`.
It is ad-hoc signed, runs on the Mac that built it, and triggers Gatekeeper elsewhere. It exists to
test packaging and installation, not to be shared.
