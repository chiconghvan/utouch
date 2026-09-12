# TrollVNC integration (single-.deb, no separate install)

TrollVNC (`owngoal-dev/TrollVNC`, **GPLv2**) provides the VNC server behind the
dashboard's Live Screen dock. Two parts:

- **noVNC web client** — vendored in git at `zxtouch/zxtouch/http/novnc/`
  (novnc/noVNC v1.6.0 `core/`, MPL-2.0), served by the dashboard as `/novnc/*`.
- **`trollvncserver` binary** — bundled into the `.deb` only when a rootless
  `.deb` is supplied (upstream GitHub Releases carry no `.deb` assets).

## TrollVNC server on device (required for stream)

Install **one** of these on the iPhone, then enable the server with
VNC port `5901` + HTTP port `5801` (dashboard Connect → `ws://<ip>:5801`):

1. TrollVNC from Havoc (`havoc.app/search/TrollVNC`), or
2. Fork `owngoal-dev/TrollVNC` → Actions → “Build TrollVNC” → install the
   `packages-rootless` artifact.

## Bundling the binary (from source, default in CI)

`vendor/TrollVNC` is a git submodule pinned at upstream tag `v3.2-272`.
`build-and-stage.sh` compiles its rootless `.deb` with Theos and stages
`trollvncserver` + `webclients/` into `layout/` (see script header).
CI runs it automatically — no manual step, no separate install on device.

## Bundling the binary (from a local .deb, fallback)

`fetch-trollvnc.sh` extracts a supplied rootless `.deb` into this repo:

- `layout/usr/bin/trollvncserver` (+ `layout/usr/lib/trollvnc/*.dylib`)
  → `/var/jb/usr/bin/trollvncserver` on device (Theos rootless prefix).
- `layout/usr/share/trollvnc/webclients/` → TrollVNC `-H 5801` docroot.

```sh
TROLLVNC_DEB=/path/to/trollvnc-rootless.deb sh vendor/trollvnc/fetch-trollvnc.sh
```

With the binary present, `layout/Library/LaunchDaemons/com.zjx.trollvnc.plist`
starts `trollvncserver -p 5901 -H 5801 ...` at boot; `postinst` loads it
(or warns if the binary is missing). CI (`.github/workflows/build.yml`) runs
the fetch script (warn-only when no `.deb` is available), then syncs
`zxtouch/zxtouch/http/index.html + novnc/` into the staged
`layout/Applications/zxtouch.app/` after the Xcode step overwrites it.

## License

TrollVNC is GPLv2. The built `.deb` ships its `COPYING` under
`/var/jb/usr/share/doc/trollvnc/`. If you redistribute the `.deb` you must
comply with GPLv2 (source offer for the TrollVNC portion).
