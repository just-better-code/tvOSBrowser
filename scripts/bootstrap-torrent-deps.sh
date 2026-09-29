#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DEPS_DIR="$ROOT_DIR/.deps"
LIB_DIR="$DEPS_DIR/libtorrent.xcframework"
BOOST_DIR="$DEPS_DIR/boost-1.69.0"

if [ -f "$LIB_DIR/tvos-arm64/libtorrent.a" ] && [ -f "$LIB_DIR/tvos-arm64_x86_64-simulator/libtorrent.a" ] && [ -d "$BOOST_DIR/boost" ]; then
    printf 'Torrent dependencies already installed in %s\n' "$DEPS_DIR"
    exit 0
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

curl -fL --retry 3 -o "$TMP_DIR/libtorrent.zip" \
    'https://github.com/danylokos/libtorrent-Apple/releases/download/1.2.17/libtorrent.xcframework.zip'
printf '%s  %s\n' '083cbdc454a8d8dfd13bf925fc9df73dd9b70fab5a2b6f78105c79f1eec8cdf4' "$TMP_DIR/libtorrent.zip" | shasum -a 256 -c -
unzip -q "$TMP_DIR/libtorrent.zip" 'libtorrent.xcframework/tvos-arm64/*' 'libtorrent.xcframework/tvos-arm64_x86_64-simulator/*' 'libtorrent.xcframework/Info.plist' -d "$TMP_DIR"
mkdir -p "$LIB_DIR"
cp -R "$TMP_DIR/libtorrent.xcframework/tvos-arm64" "$LIB_DIR/"
cp -R "$TMP_DIR/libtorrent.xcframework/tvos-arm64_x86_64-simulator" "$LIB_DIR/"
cp "$TMP_DIR/libtorrent.xcframework/Info.plist" "$LIB_DIR/"
python3 - "$LIB_DIR/Info.plist" <<'PY'
import plistlib
import sys

path = sys.argv[1]
with open(path, 'rb') as source:
    info = plistlib.load(source)
info['AvailableLibraries'] = [entry for entry in info['AvailableLibraries'] if entry.get('SupportedPlatform') == 'tvos']
with open(path, 'wb') as destination:
    plistlib.dump(info, destination)
PY

curl -fL --retry 3 -o "$TMP_DIR/boost.tar.gz" \
    'https://archives.boost.io/release/1.69.0/source/boost_1_69_0.tar.gz'
printf '%s  %s\n' '9a2c2819310839ea373f42d69e733c339b4e9a19deab6bfec448281554aa4dbb' "$TMP_DIR/boost.tar.gz" | shasum -a 256 -c -
mkdir -p "$BOOST_DIR"
tar -xzf "$TMP_DIR/boost.tar.gz" -C "$BOOST_DIR" --strip-components=1 boost_1_69_0/boost

printf 'Torrent dependencies installed in %s\n' "$DEPS_DIR"
