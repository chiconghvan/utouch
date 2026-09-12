# Vendored TrollVNC (single-.deb plan)

TrollVNC (`owngoal-dev/TrollVNC`, **GPLv2**) is bundled into the same rootless
`.deb` as ZXTouch — no separate install, no source build.

## How it works

1. `fetch-trollvnc.sh` downloads the upstream `packages-rootless` `.deb`
   for the pinned `TROLLVNC_VERSION` and extracts into this repo:
   - `layout/usr/bin/trollvncserver` (+ `layout/usr/lib/trollvnc/*.dylib`)
     → `/var/jb/usr/bin/trollvncserver` on device (Theos rootless prefix).
   - `layout/usr/share/trollvnc/webclients/` → TrollVNC `-H 5801` docroot.
   - `zxtouch/zxtouch/http/novnc/` → served by the dashboard itself as
     `/novnc/*` (token auth) so `index.html` can `import ./novnc/core/rfb.js`.
2. `layout/Library/LaunchDaemons/com.zjx.trollvnc.plist` starts
   `trollvncserver -p 5901 -H 5801 ...` at boot (`RunAtLoad + KeepAlive`).
3. `postinst` loads the daemon (or warns if the binary is missing, e.g. a
   source checkout without running the fetch script).
4. CI (`.github/workflows/build.yml`) runs the fetch script, then syncs
   `zxtouch/zxtouch/http/index.html + novnc/` into the staged
   `layout/Applications/zxtouch.app/` after the Xcode step overwrites it.

## Pin / upgrade

```sh
sh vendor/trollvnc/fetch-trollvnc.sh 3.2-272
# or: TROLLVNC_VERSION=3.2-272 sh vendor/trollvnc/fetch-trollvnc.sh
```

## License

TrollVNC is GPLv2. The built `.deb` ships its `COPYING` under
`/var/jb/usr/share/doc/trollvnc/`. If you redistribute the `.deb` you must
comply with GPLv2 (source offer for the TrollVNC portion).
