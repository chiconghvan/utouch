# Bundled noVNC client

`index.html` loads `./novnc/core/rfb.js` (served by the dashboard as
`/novnc/*`, no token needed) and opens a raw WebSocket to
TrollVNC at `ws://<iphone-ip>:5801/websockify` for the live screen + Pure-VNC
input (left=touch, right=Home, middle=Power/Wake).

Source: https://github.com/novnc/noVNC v1.6.0 (`core/` + `vendor/pako/`,
MPL-2.0 — see https://github.com/novnc/noVNC/blob/master/LICENSE.md).
`vendor/pako` is required at runtime (`core/inflator.js` imports it).
Do not hand-edit files under `core/` or `vendor/`; to upgrade, replace both
directories from a newer noVNC release.
