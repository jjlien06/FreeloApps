#!/bin/bash
# Builds the SPM executable and assembles a signed SnipText.app in dist/.
# Signing with the stable Apple Development identity keeps the Screen Recording
# (TCC) grant valid across rebuilds; ad-hoc signing would reset it every build.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=${1:-release}
# The first Apple Development certificate in the keychain (override with SIGN_IDENTITY);
# ad-hoc signing ("-") when there is none, which works but loses permissions on rebuild.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2; exit}')}"
IDENTITY="${IDENTITY:--}"
APP=dist/SnipText.app

swift build -c "$CONFIG" --arch arm64

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/SnipText" "$APP/Contents/MacOS/"
cp Support/Info.plist "$APP/Contents/"
# SPM resource bundles (e.g. KeyboardShortcuts localizations) are looked up
# relative to Bundle.main.resourceURL.
find ".build/$CONFIG" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$APP/Contents/Resources/" \;

codesign --force --options runtime --sign "$IDENTITY" "$APP"
echo "Built $APP"
