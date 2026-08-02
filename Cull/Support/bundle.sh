#!/bin/bash
# Builds the SPM executable and assembles a signed Cull.app in dist/.
# Signing with the stable Apple Development identity keeps the folder-access
# (TCC) grants for Desktop/Documents/Downloads valid across rebuilds; ad-hoc
# signing would reset them every build.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=${1:-release}
IDENTITY=BA606FC1DB56F821AE3ECB50D1E682259FCE6DD3
APP=dist/Cull.app

swift build -c "$CONFIG" --arch arm64

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/Cull" "$APP/Contents/MacOS/"
cp Support/Info.plist "$APP/Contents/"

codesign --force --options runtime --sign "$IDENTITY" "$APP"
echo "Built $APP"
