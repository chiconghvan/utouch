# No boilerplate needed when launched from the app/panel:
# runner (python -m zxtouch.runner) pre-injects tap/sleep/toast/...
# Old style (from zxtouch.client import zxtouch; device = ...) still works.
tap(200, 300)
sleep(0.5)
toast("Tapped (200, 300)", 2)
log("done")
