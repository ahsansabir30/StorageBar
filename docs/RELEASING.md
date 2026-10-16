# Releasing StorageBar

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

## GitHub Environment and secrets

The release job runs in an Environment named `release`. Create it (Settings › Environments), add
yourself as a **required reviewer**, and restrict it to the `main` branch, so a release cannot start
without your approval. Also protect `main` and add a tag protection rule for `v*`.

Store the secrets **in that Environment** (Settings › Environments › release), or with the CLI
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
