#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DEPS_DIR="$ROOT_DIR/.deps"
FRAMEWORK_DIR="$DEPS_DIR/TVVLCKit.xcframework"
if [ -f "$FRAMEWORK_DIR/tvos-arm64/TVVLCKit.framework/TVVLCKit" ]; then
    printf 'TVVLCKit is already installed in %s\n' "$FRAMEWORK_DIR"
    exit 0
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM
curl -fL --retry 3 -o "$TMP_DIR/TVVLCKit.tar.xz" \
    'https://download.videolan.org/cocoapods/prod/TVVLCKit-3.7.3-319ed2c0-79128878.tar.xz'
printf '%s  %s\n' 'b5f90c226ed54d9dc1c03901c60dc7749b74a53caace2c3047e4c0b7a063e46c' "$TMP_DIR/TVVLCKit.tar.xz" | shasum -a 256 -c -
tar -xJf "$TMP_DIR/TVVLCKit.tar.xz" -C "$TMP_DIR" \
    --exclude='*/dSYMs/*' \
    TVVLCKit-binary/TVVLCKit.xcframework/tvos-arm64 \
    TVVLCKit-binary/TVVLCKit.xcframework/Info.plist \
    TVVLCKit-binary/COPYING.txt
mkdir -p "$DEPS_DIR"
mv "$TMP_DIR/TVVLCKit-binary/TVVLCKit.xcframework" "$FRAMEWORK_DIR"
cp "$TMP_DIR/TVVLCKit-binary/COPYING.txt" "$DEPS_DIR/TVVLCKit-LICENSE.txt"
python3 - "$FRAMEWORK_DIR/Info.plist" <<'PY'
import plistlib
import sys

path = sys.argv[1]
with open(path, 'rb') as source:
    info = plistlib.load(source)
info['AvailableLibraries'] = [
    {key: value for key, value in entry.items() if key != 'DebugSymbolsPath'}
    for entry in info['AvailableLibraries']
    if entry.get('SupportedPlatform') == 'tvos' and not entry.get('SupportedPlatformVariant')
]
with open(path, 'wb') as destination:
    plistlib.dump(info, destination)
PY
printf 'TVVLCKit device dependency installed in %s\n' "$FRAMEWORK_DIR"
