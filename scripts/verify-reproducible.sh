#!/usr/bin/env bash
# Proves the Release build is reproducible: builds StorageBar twice from the same source in two
# different directories and requires every file in the app bundle to be byte-identical.
# A user (or CI) can therefore check that a published binary corresponds to the public source.
#
# Usage: scripts/verify-reproducible.sh
set -euo pipefail
cd "$(dirname "$0")/.."

WORK=$(mktemp -d /tmp/storagebar-repro.XXXXXX)
for n in one two; do
  echo "==> build $n"
  xcodebuild -project StorageBar.xcodeproj -scheme StorageBar -configuration Release \
    -derivedDataPath "$WORK/$n" build > "$WORK/$n.log" 2>&1 || { tail -20 "$WORK/$n.log"; exit 1; }
  ( cd "$WORK/$n/Build/Products/Release" && find StorageBar.app -type f | sort | xargs shasum -a 256 ) > "$WORK/$n.manifest"
done

if diff "$WORK/one.manifest" "$WORK/two.manifest" > "$WORK/diff.txt"; then
  echo "OK: two independent builds are byte-identical"
  grep "MacOS/StorageBar" "$WORK/one.manifest"
else
  echo "FAIL: builds differ"; cat "$WORK/diff.txt"; exit 1
fi
