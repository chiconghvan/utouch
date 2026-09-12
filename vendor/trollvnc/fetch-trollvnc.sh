#!/bin/sh
# Vendor TrollVNC (rootless) + noVNC client into this repo's single .deb.
# Usage: sh vendor/trollvnc/fetch-trollvnc.sh [VERSION]
#   - Downloads TrollVNC packages-rootless artifact from GitHub Releases
#     (GPLv2 - see vendor/trollvnc/README.md, COPYING shipped in .deb).
#   - Extracts trollvncserver + libs into layout/usr/... (Theos rootless
#     scheme prefixes /var/jb on device).
#   - Extracts noVNC webclients into layout/usr/share/trollvnc/webclients/
#     AND copies novnc/core/rfb.js (+deps) into zxtouch/zxtouch/http/novnc/
#     so the dashboard can `import ./novnc/core/rfb.js` with token auth.
#   - Syncs zxtouch/zxtouch/http/index.html into the staged app later via CI
#     (see .github/workflows/build.yml "Sync dashboard" step).
set -eu
VERSION="${1:-${TROLLVNC_VERSION:-3.2-272}}"
REPO="${TROLLVNC_REPO:-owngoal-dev/TrollVNC}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> TrollVNC $VERSION from $REPO"
# Release asset naming follows TrollVNC "Build TrollVNC" workflow
# (packages-rootless). Adjust grep if upstream renames assets.
URL="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/tags/v$VERSION" \
  | grep -o "https://[^\" ]*rootless[^\" ]*\.deb" | head -1)"
if [ -z "$URL" ]; then
  echo "ERROR: no rootless .deb found for v$VERSION. Set TROLLVNC_VERSION explicitly." >&2
  exit 1
fi
curl -fsSL -o "$TMP/trollvnc.deb" "$URL"
dpkg-deb -x "$TMP/trollvnc.deb" "$TMP/tvnc"

# Binary + libs (paths inside the TrollVNC deb are already jb-rooted or absolute;
# normalize to layout/ which Theos treats as jbroot-relative for rootless).
mkdir -p "$ROOT/layout/usr/bin" "$ROOT/layout/usr/lib/trollvnc" \
         "$ROOT/layout/usr/share/trollvnc/webclients"
for f in "$TMP/tvnc/var/jb/usr/bin/trollvncserver" "$TMP/tvnc/usr/bin/trollvncserver"; do
  if [ -x "$f" ]; then cp -f "$f" "$ROOT/layout/usr/bin/trollvncserver"; chmod 0755 "$ROOT/layout/usr/bin/trollvncserver"; break
  fi
done
if [ ! -x "$ROOT/layout/usr/bin/trollvncserver" ]; then
  echo "ERROR: trollvncserver binary not found in $URL" >&2; exit 1
fi
# Bundled dylibs (vncserver, turbojpeg, png, ssl, crypto, sasl2, lzo2)
for d in "$TMP/tvnc/var/jb/usr/lib" "$TMP/tvnc/usr/lib" "$TMP/tvnc/var/jb/usr/lib/trollvnc"; do
  if [ -d "$d" ]; then cp -Rf "$d/"*.dylib "$ROOT/layout/usr/lib/trollvnc/" 2>/dev/null || true; fi
done
# noVNC webclients for :5801 (+ dashboard bundle copy for :8080/novnc/*)
for d in "$TMP/tvnc/var/jb/usr/share/trollvnc/webclients" "$TMP/tvnc/usr/share/trollvnc/webclients"; do
  if [ -d "$d" ]; then cp -Rf "$d/"* "$ROOT/layout/usr/share/trollvnc/webclients/"; break
  fi
done
if [ -d "$ROOT/layout/usr/share/trollvnc/webclients/novnc/core" ]; then
  mkdir -p "$ROOT/zxtouch/zxtouch/http/novnc"
  cp -Rf "$ROOT/layout/usr/share/trollvnc/webclients/novnc/"* "$ROOT/zxtouch/zxtouch/http/novnc/"
  echo "==> noVNC copied to zxtouch/zxtouch/http/novnc/"
else
  echo "WARNING: webclients/novnc not found - dashboard falls back to :5801 iframe." >&2
fi
# GPLv2 attribution must ship inside the single .deb
for f in "$TMP/tvnc/COPYING" "$TMP/tvnc/usr/share/doc/trollvnc/copyright"; do
  if [ -f "$f" ]; then mkdir -p "$ROOT/layout/usr/share/doc/trollvnc"; cp -f "$f" "$ROOT/layout/usr/share/doc/trollvnc/"; break; fi
done
echo "==> vendored OK: layout/usr/bin/trollvncserver + webclients"
