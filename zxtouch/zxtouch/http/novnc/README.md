# Bundled noVNC client

`index.html` loads `./novnc/core/rfb.js` (served by the dashboard as
`/novnc/*` with the same `?token=` auth) and opens a raw WebSocket to
TrollVNC at `ws://<iphone-ip>:5801/websockify` for the live screen + Pure-VNC
input (left=touch, right=Home, middle=Power/Wake).

This directory is populated at package time by
`vendor/trollvnc/fetch-trollvnc.sh` (copied from TrollVNC's
`webclients/novnc/`). It is intentionally empty in a fresh checkout —
the dashboard shows a fallback message and the `:5801` URL if missing.
