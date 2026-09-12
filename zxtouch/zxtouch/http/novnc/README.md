# Bundled noVNC client

`index.html` loads `./novnc/core/rfb.js` (served by the dashboard as
`/novnc/*`, no token needed) and opens a raw WebSocket to
TrollVNC at `ws://<iphone-ip>:5801/websockify` for the live screen + Pure-VNC
input (left=touch, right=Home, middle=Power/Wake).

Source: https://github.com/novnc/noVNC v1.6.0 (`core/` only, MPL-2.0 —
see https://github.com/novnc/noVNC/blob/master/LICENSE.md).
Do not hand-edit files under `core/`; to upgrade, replace the directory
with `core/` from a newer noVNC release.
