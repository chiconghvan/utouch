#!/bin/bash
# Build TrollVNC from source (vendor/TrollVNC submodule, pinned tag) with
# Theos, then stage what our .deb needs into layout/:
#   layout/usr/bin/trollvncserver                  (single static binary)
#   layout/usr/share/trollvnc/webclients/           (noVNC web root for :5801)
# TrollVNC links everything statically (.a in vendor/TrollVNC/lib), so no
# .dylib shipping is needed.
#
# Dual-build: pass --scheme=rootless or --scheme=roothide (default rootless).
# Each scheme gets its own binary because entitlements/install paths differ;
# CI builds once per scheme and stages before the matching `make package`.
# Theos rebases layout/ install paths at OUR packaging time on top.
#
# Requires (CI macOS): THEOS env, GNU make (brew install make -> gmake),
# dpkg-deb (brew install dpkg), Xcode iOS SDK (Theos sdks).
set -euo pipefail

SCHEME="rootless"
for arg in "$@"; do
    case "$arg" in
        --scheme=*) SCHEME="${arg#--scheme=}" ;;
        *) echo "ERROR: unknown argument $arg (usage: $0 [--scheme=rootless|roothide])" >&2; exit 1 ;;
    esac
done
case "$SCHEME" in
    rootless|roothide) ;;
    *) echo "ERROR: --scheme must be rootless or roothide" >&2; exit 1 ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TVNC="$ROOT/vendor/TrollVNC"
: "${THEOS:?THEOS must be set (export THEOS=<path-to-theos>)}"
command -v gmake >/dev/null 2>&1 || { echo "ERROR: gmake missing (brew install make)." >&2; exit 1; }
command -v dpkg-deb >/dev/null 2>&1 || { echo "ERROR: dpkg-deb missing (brew install dpkg)." >&2; exit 1; }
[ -f "$TVNC/Makefile" ] || { echo "ERROR: submodule empty - run: git submodule update --init vendor/TrollVNC" >&2; exit 1; }

cd "$TVNC"
# shellcheck disable=SC1091
source "devkit/${SCHEME}.sh"   # exports THEOS_PACKAGE_SCHEME=rootless|roothide
FINALPACKAGE=1 gmake clean package

DEB="$(ls -t packages/*.deb | head -1)"
echo "==> built $DEB (scheme=$SCHEME)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
dpkg-deb -x "$DEB" "$STAGE"

if [ "$SCHEME" = "roothide" ]; then
    # Roothide dpkg uses the live (randomized) jbroot, not /var/jb.
    BIN="$(find "$STAGE" -name trollvncserver -type f | head -1)"
    WEB="$(find "$STAGE" -path '*trollvnc/webclients' -type d | head -1)"
else
    BIN="$STAGE/var/jb/usr/bin/trollvncserver"
    WEB="$STAGE/var/jb/usr/share/trollvnc/webclients"
fi
[ -n "$BIN" ] && [ -x "$BIN" ] || { echo "ERROR: trollvncserver missing in $DEB" >&2; exit 1; }
[ -n "$WEB" ] && [ -d "$WEB" ] || { echo "ERROR: webclients missing in $DEB" >&2; exit 1; }

mkdir -p "$ROOT/layout/usr/bin" "$ROOT/layout/usr/share/trollvnc"
cp -f "$BIN" "$ROOT/layout/usr/bin/trollvncserver"
chmod 0755 "$ROOT/layout/usr/bin/trollvncserver"
rm -rf "$ROOT/layout/usr/share/trollvnc/webclients"
cp -R "$WEB" "$ROOT/layout/usr/share/trollvnc/webclients"
echo "==> staged: layout/usr/bin/trollvncserver + layout/usr/share/trollvnc/webclients/"
