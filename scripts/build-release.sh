#!/usr/bin/env bash
# Builds StorageBar.app (Release) and packages it as a DMG in ./dist.
#
#   scripts/build-release.sh                 local build, ad-hoc signed, NOT notarised
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" DEVELOPMENT_TEAM=TEAMID \
#   NOTARY_KEY_PATH=AuthKey.p8 NOTARY_KEY_ID=... NOTARY_ISSUER_ID=... \
#     scripts/build-release.sh               Developer ID signed, notarised, stapled
#
# Output names make the trust level obvious:
#   dist/StorageBar.dmg                         signed + notarised + stapled (publishable)
#   dist/StorageBar-<version>-LOCAL-UNSIGNED.dmg  ad-hoc signed development artefact (do not publish)
#
# Credentials come only from the environment; nothing is stored in the repository.
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT=StorageBar.xcodeproj
SCHEME=StorageBar
DIST=${DIST_DIR:-dist}
# Build outside ~/Documents and other iCloud-synced folders: file-provider xattrs break codesign.
WORK=${WORK_DIR:-$(mktemp -d /tmp/storagebar-build.XXXXXX)}
SIGN_IDENTITY=${SIGN_IDENTITY:-}
NOTARY_KEY_PATH=${NOTARY_KEY_PATH:-}
NOTARY_KEY_ID=${NOTARY_KEY_ID:-}
NOTARY_ISSUER_ID=${NOTARY_ISSUER_ID:-}

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

VERSION=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null \
  | awk '/^ *MARKETING_VERSION = /{print $3; exit}')
[[ -n "$VERSION" ]] || die "could not read MARKETING_VERSION"
[[ -z "${EXPECTED_VERSION:-}" || "$EXPECTED_VERSION" == "$VERSION" ]] \
  || die "version mismatch: project is $VERSION, expected $EXPECTED_VERSION"

SIGNED=false
[[ -n "$SIGN_IDENTITY" ]] && SIGNED=true
NOTARIZE=false
if $SIGNED && [[ -n "$NOTARY_KEY_PATH" && -n "$NOTARY_KEY_ID" && -n "$NOTARY_ISSUER_ID" ]]; then NOTARIZE=true; fi
if [[ "${REQUIRE_NOTARIZATION:-0}" == 1 ]] && ! $NOTARIZE; then
  die "REQUIRE_NOTARIZATION=1 but signing identity or notarisation credentials are missing"
fi

log "Building StorageBar $VERSION (Release, arm64) in $WORK"
BUILD_ARGS=(-project "$PROJECT" -scheme "$SCHEME" -configuration Release -derivedDataPath "$WORK/dd")
if $SIGNED; then
  BUILD_ARGS+=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$SIGN_IDENTITY" ENABLE_HARDENED_RUNTIME=YES
    OTHER_CODE_SIGN_FLAGS=--timestamp "DEVELOPMENT_TEAM=${DEVELOPMENT_TEAM:-}")
fi
xcodebuild "${BUILD_ARGS[@]}" build > "$WORK/build.log" 2>&1 || { tail -30 "$WORK/build.log"; die "build failed"; }
APP="$WORK/dd/Build/Products/Release/StorageBar.app"
[[ -d "$APP" ]] || die "StorageBar.app not found after build"

log "Verifying the app bundle"
PLIST="$APP/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")" == "$VERSION" ]] || die "bundle version mismatch"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$PLIST")" == true ]] || die "LSUIElement is not set"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")" == com.ahsan.StorageBar ]] || die "unexpected bundle id"
[[ "$(lipo -archs "$APP/Contents/MacOS/StorageBar")" == arm64 ]] || die "binary is not arm64"
[[ -f "$APP/Contents/Resources/Assets.car" ]] || die "app icon assets missing"
codesign --verify --deep --strict "$APP" || die "app signature does not verify"
if $SIGNED; then
  DETAILS=$(codesign -dvv "$APP" 2>&1)
  grep -q "flags=.*runtime" <<<"$DETAILS" || die "hardened runtime not enabled"
  grep -q "^Authority=Developer ID Application" <<<"$DETAILS" || die "app is not signed with a Developer ID Application certificate"
  if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
    grep -q "^TeamIdentifier=$DEVELOPMENT_TEAM$" <<<"$DETAILS" || die "app is signed by an unexpected team"
  fi
fi

log "Packaging the disk image"
mkdir -p "$DIST"
if $NOTARIZE; then DMG="$DIST/StorageBar.dmg"; else DMG="$DIST/StorageBar-$VERSION-LOCAL-UNSIGNED.dmg"; fi
rm -f "$DMG" "$DMG.sha256"
STAGE="$WORK/stage"
mkdir -p "$STAGE"
ditto --noextattr --noqtn "$APP" "$STAGE/StorageBar.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname StorageBar -srcfolder "$STAGE" -format UDZO -ov "$DMG"
if $SIGNED; then codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"; fi

if $NOTARIZE; then
  log "Submitting to Apple notarisation (this can take a few minutes)"
  xcrun notarytool submit "$DMG" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER_ID" --wait | tee "$WORK/notary.log"
  grep -q "status: Accepted" "$WORK/notary.log" || die "notarisation was not accepted"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
fi

log "Verifying the disk image"
hdiutil verify -quiet "$DMG"
MNT="$WORK/mnt"
mkdir -p "$MNT"
trap 'hdiutil detach -quiet "$MNT" 2>/dev/null || true' EXIT
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MNT" "$DMG"
[[ -d "$MNT/StorageBar.app" ]] || die "app missing inside the DMG"
[[ -L "$MNT/Applications" ]] || die "Applications shortcut missing inside the DMG"
codesign --verify --deep --strict "$MNT/StorageBar.app" || die "signature inside the DMG does not verify"
if $NOTARIZE; then
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
  spctl --assess --type execute --verbose=2 "$MNT/StorageBar.app"
fi
hdiutil detach -quiet "$MNT"
trap - EXIT

( cd "$DIST" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256" )

log "Done"
echo "  artefact : $DMG"
echo "  checksum : $(cut -d' ' -f1 "$DMG.sha256")"
if $NOTARIZE; then
  echo "  trust    : Developer ID signed, notarised and stapled"
else
  echo "  trust    : LOCAL DEVELOPMENT ARTEFACT - ad-hoc signed, NOT notarised. Do not distribute."
fi
