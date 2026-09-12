#!/bin/sh
# Vendor TrollVNC (rootless) into this repo's single .deb.
# NOTE (verified 2026-09-12): upstream GitHub Releases ship NO .deb assets
# (TrollVNC is distributed via Havoc / self-built CI artifacts), so this
# script prefers an explicit local .deb and otherwise warns:
#   TROLLVNC_DEB=/path/to/trollvnc-rootless.deb sh vendor/trollvnc/fetch-trollvnc.sh
#   sh vendor/trollvnc/fetch-trollvnc.sh /path/to/trollvnc-rootless.deb
#   sh vendor/trollvnc/fetch-trollvnc.sh 3.2-272   # tries GitHub release assets
# The noVNC web client used by the dashboard is vendored separately in git
# at zxtouch/zxtouch/http/novnc/ (novnc/noVNC, MPL-2.0) and needs no download.
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ -n "${TROLLVNC_DEB:-}" ]; then
  DEB="$TROLLVNC_DEB"
elif [ "${1:-}" != "" ] && [ -f "$1" ]; then
  DEB="$1"
else
  VERSION="${1:-${TROLLVNC_VERSION:-3.2-272}}"
  REPO="${TROLLVNC_REPO:-owngoal-dev/TrollVNC}"
  echo "==> looking for TrollVNC rootless .deb in $REPO release v$VERSION ..."
  URL="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/tags/v$VERSION" \
    | grep -o "https://[^\" ]*rootless[^\" ]*\.deb" | head -1)"
  if [ -z "$URL" ]; then
    echo "WARNING: no rootless .deb asset in upstream release v$VERSION." >&2
    echo "  TrollVNC server will NOT be bundled. Install TrollVNC on the" >&2
    echo "  device separately (Havoc, or fork + 'Build TrollVNC' workflow)," >&2
    echo "  enable it with VNC :5901 + HTTP :5801, then dashboard Connect works." >&2
    echo "  To bundle: TROLLVNC_DEB=<rootless.deb> sh vendor/trollvnc/fetch-trollvnc.sh" >&2
    exit 0
  fi
  curl -fsSL -o "$TMP/trollvnc.deb" "$URL"
  DEB="$TMP/trollvnc.deb"
fi
echo "==> vendoring $DEB"
dpkg-deb -x "$DEB" "$TMP/tvnc"

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
