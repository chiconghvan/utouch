#!/bin/bash
# Build TrollVNC from source (vendor/TrollVNC submodule, pinned tag) with
# Theos, then stage what our single .deb needs into layout/:
#   layout/usr/bin/trollvncserver                  (single static binary)
#   layout/usr/share/trollvnc/webclients/           (noVNC web root for :5801)
# TrollVNC links everything statically (.a in vendor/TrollVNC/lib), so no
# .dylib shipping is needed. The same binary is used for our rootless AND
# roothide variants (Theos rebases install paths at OUR packaging time).
#
# Requires (CI macOS): THEOS env, GNU make (brew install make -> gmake),
# dpkg-deb (brew install dpkg), Xcode iOS SDK (Theos sdks).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TVNC="$ROOT/vendor/TrollVNC"
: "${THEOS:?THEOS must be set (export THEOS=<path-to-theos>)}"
command -v gmake >/dev/null 2>&1 || { echo "ERROR: gmake missing (brew install make)." >&2; exit 1; }
command -v dpkg-deb >/dev/null 2>&1 || { echo "ERROR: dpkg-deb missing (brew install dpkg)." >&2; exit 1; }
[ -f "$TVNC/Makefile" ] || { echo "ERROR: submodule empty - run: git submodule update --init vendor/TrollVNC" >&2; exit 1; }

cd "$TVNC"
# shellcheck disable=SC1091
source devkit/rootless.sh   # exports THEOS_PACKAGE_SCHEME=rootless
FINALPACKAGE=1 gmake clean package

DEB="$(ls -t packages/*.deb | head -1)"
echo "==> built $DEB"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
dpkg-deb -x "$DEB" "$STAGE"

BIN="$STAGE/var/jb/usr/bin/trollvncserver"
WEB="$STAGE/var/jb/usr/share/trollvnc/webclients"
[ -x "$BIN" ] || { echo "ERROR: trollvncserver missing in $DEB" >&2; exit 1; }
[ -d "$WEB" ] || { echo "ERROR: webclients missing in $DEB" >&2; exit 1; }

mkdir -p "$ROOT/layout/usr/bin" "$ROOT/layout/usr/share/trollvnc"
cp -f "$BIN" "$ROOT/layout/usr/bin/trollvncserver"
chmod 0755 "$ROOT/layout/usr/bin/trollvncserver"
rm -rf "$ROOT/layout/usr/share/trollvnc/webclients"
cp -R "$WEB" "$ROOT/layout/usr/share/trollvnc/webclients"
echo "==> staged: layout/usr/bin/trollvncserver + layout/usr/share/trollvnc/webclients/"
