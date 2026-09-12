#!/bin/sh
# Rebuild APT metadata for docs/ (GitHub Pages Sileo source).
# Layout served at https://<user>.github.io/<repo>/ :
#   docs/Packages[.gz]  docs/Release  docs/debs/*.deb  docs/index.html
#
# Usage: sh scripts/apt/update-repo.sh [incoming-debs-dir]
#   Copies *.deb from the incoming dir into docs/debs/ (existing files with
#   the same name are overwritten), then regenerates Packages + Release.
# Requires: dpkg-scanpackages (dpkg-dev), gzip, coreutils hashes.
set -eu

REPO_DIR="docs"
POOL="$REPO_DIR/debs"
mkdir -p "$POOL"

if [ "${1:-}" != "" ]; then
  for f in "$1"/*.deb; do
    [ -e "$f" ] || continue
    cp -f "$f" "$POOL/"
    echo "pooled: $(basename "$f")"
  done
fi

if ! ls "$POOL"/*.deb >/dev/null 2>&1; then
  echo "ERROR: no .deb files in $POOL" >&2
  exit 1
fi

command -v dpkg-scanpackages >/dev/null 2>&1 || {
  echo "ERROR: dpkg-scanpackages not found (install dpkg-dev)." >&2
  exit 1
}

cd "$REPO_DIR"
dpkg-scanpackages --multiversion debs /dev/null > Packages
gzip -9kf Packages
if command -v bzip2 >/dev/null 2>&1; then
  bzip2 -9kf Packages
fi

FILES="Packages"
[ -f Packages.gz ] && FILES="$FILES Packages.gz"
[ -f Packages.bz2 ] && FILES="$FILES Packages.bz2"

DATE="$(date -u '+%a, %d %b %Y %H:%M:%S UTC')"
{
  echo "Origin: utouch"
  echo "Label: utouch APT"
  echo "Suite: stable"
  echo "Codename: ios"
  echo "Version: 1.0"
  echo "Architectures: iphoneos-arm64"
  echo "Components: main"
  echo "Description: ZXTouch rootless repo (iOS 15-17)"
  echo "Date: $DATE"
  for algo in md5sum sha1sum sha256sum; do
    case "$algo" in
      md5sum) echo "MD5Sum:" ;;
      sha1sum) echo "SHA1:" ;;
      sha256sum) echo "SHA256:" ;;
    esac
    for f in $FILES; do
      # shellcheck disable=SC2086
      set -- $($algo "$f")
      printf ' %s %16s %s\n' "$1" "$(wc -c < "$f" | tr -d ' ')" "$f"
    done
  done
} > Release

echo "==> $(ls debs/*.deb | wc -l | tr -d ' ') debs, $(grep -c '^Package:' Packages) stanzas"
echo "==> wrote Packages${FILES#Packages} + Release"
