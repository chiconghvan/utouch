"""Unit tests for zxtouch.prelude + runner (no jailbreak device needed).

Run:  python -m pytest tools/tests/test_prelude.py -q
"""
import json
import os
import re
import sys
import types
from pathlib import Path

import pytest

PY_MOD = Path(__file__).resolve().parents[2] / "layout" / "usr" / "share" / "zxtouch" / "python"
sys.path.insert(0, str(PY_MOD))

from zxtouch import prelude  # noqa: E402


class FakeDevice:
    def __init__(self):
        self.calls = []
        self.ocr_items = []
        self.pick = {"red": 255, "green": 0, "blue": 0}
        # Daemon formats numbers as float strings ('1242.000000') — see
        # tapText('Files') ValueError regression.
        self.screen = {"width": "1242.000000", "height": "2208.000000"}

    # raw client API surface used by prelude
    def touch(self, t, finger, x, y):
        self.calls.append(("touch", t, finger, x, y))

    def touch_with_list(self, lst):
        self.calls.append(("multi", list(lst)))

    def accurate_usleep(self, us):
        self.calls.append(("usleep", us))
        return (True, "")

    def pick_color(self, x, y):
        self.calls.append(("pick", x, y))
        return (True, dict(self.pick))

    def search_color(self, *a):
        self.calls.append(("search", a))
        return (True, {"x": "10", "y": "20", "red": "255", "green": "0", "blue": "0"})

    def image_match(self, *a):
        self.calls.append(("image", a))
        return (True, {"x": "5.00", "y": "6.00", "width": "10.00", "height": "10.00"})

    def ocr(self, region, **kwargs):
        self.calls.append(("ocr", region, kwargs))
        return (True, list(self.ocr_items))

    def show_toast(self, *a):
        self.calls.append(("toast", a))
        return (True, "")

    def show_alert_box(self, *a):
        self.calls.append(("alert", a))
        return (True, "")

    def prompt_input(self, *a):
        self.calls.append(("prompt", a))
        return (True, ["hello"])

    def switch_to_app(self, bid):
        self.calls.append(("app", bid))
        return (True, "")

    def insert_text(self, t):
        self.calls.append(("insert", t))
        return (True, "")

    def get_text_from_clipboard(self):
        return (True, ["clip"])

    def set_clipboard_text(self, t):
        self.calls.append(("setclip", t))
        return (True, "")

    def get_screen_size(self):
        return (True, dict(self.screen))

    def get_device_info(self):
        return (True, {"name": "iPhone", "system_name": "iOS",
                       "system_version": "16.0", "model": "iPhone",
                       "identifier_for_vendor": "x"})

    def get_battery_info(self):
        return (True, ["2", "88"])

    def start_touch_recording(self):
        return (True, "")

    def stop_touch_recording(self):
        return (True, "")

    def run_shell_command(self, c):
        self.calls.append(("shell", c))
        return (True, "")

    # Phase-2 native methods
    def screenshot(self, name, region=None):
        self.calls.append(("screenshot", name, region))
        return (True, "/var/mobile/Library/ZXTouch/images/" + name)

    def dialog_choice(self, title, options):
        self.calls.append(("choice", title, options))
        return (True, 1)

    def show_overlay(self, data):
        self.calls.append(("overlay_show", data))
        return (True, "")

    def update_overlay(self, k, v):
        self.calls.append(("overlay_update", k, v))
        return (True, "")

    def hide_overlay(self):
        self.calls.append(("overlay_hide",))
        return (True, "")

    def show_keyboard(self):
        self.calls.append(("keyboard_show",))
        return (True, "")

    def hide_keyboard(self):
        self.calls.append(("keyboard_hide",))
        return (True, "")

    def keyboard_visible(self):
        self.calls.append(("keyboard_visible",))
        return (True, True)

    def app_kill(self, bid):
        self.calls.append(("kill", bid))
        return (True, "")

    def app_state(self, bid):
        self.calls.append(("state", bid))
        return (True, 2)

    def open_url(self, url):
        self.calls.append(("openurl", url))
        return (True, "")

    def app_clear(self, bid):
        self.calls.append(("clear", bid))
        return (True, 3)

    def key_press(self, name, action="down"):
        self.calls.append(("key", name, action))

    def vibrate(self):
        self.calls.append(("vibrate",))

    def debug_mark(self, op, coords, duration=1.5):
        self.calls.append(("debug", op, tuple(coords), duration))
        return (True, "")

    def find_colors_multi(self, *a):
        raise RuntimeError("old daemon")

    def find_colors_pattern(self, *a):
        raise RuntimeError("old daemon")

    def find_image_in_region(self, *a):
        raise RuntimeError("old daemon")

    def image_match_multi(self, *a):
        raise RuntimeError("old daemon")

    def record_play_events(self, events):
        raise RuntimeError("old daemon")

    def record_save(self, name, events):
        raise RuntimeError("old daemon")

    def record_load(self, name):
        raise RuntimeError("old daemon")

    # Crane (TASK_CRANE=47, JSON protocol)
    def crane(self, op, **params):
        self.calls.append(("crane", op, params))
        canned = {
            "list": [{"bundleId": "com.foo", "containers": [
                {"id": "c1", "name": "Main", "active": True}]}],
            "switch": {"ok": True, "active": "c1"},
            "create": {"ok": True, "id": "c2"},
            "delete": {"ok": True},
            "wipe": {"ok": True},
            "rename": {"ok": True},
            "clearData": {"ok": True, "cleared": 5},
            "backup": {"ok": True, "path": "/var/mobile/Library/ZXTouch/crane-backups/f.tar.gz"},
            "restore": {"ok": True},
            "size": {"total": 100, "caches": 60, "webkit": 30, "preferences": 10},
        }
        return (True, canned[op])

    def disconnect(self):
        self.calls.append(("disconnect",))


def use_fake():
    prelude.disconnect()
    return prelude.set_device(FakeDevice())


def test_tap_sends_down_up():
    d = use_fake()
    prelude.setDebugVisual(False)
    prelude.tap(200, 300)
    prelude.setDebugVisual(True)
    kinds = [c[0] for c in d.calls]
    assert kinds == ["touch", "touch"]
    assert d.calls[0][1] == 1 and d.calls[1][1] == 0  # DOWN then UP


def test_swipe_interpolates():
    d = use_fake()
    prelude.setDebugVisual(False)
    prelude.swipe(0, 0, 100, 0, 0.04)
    prelude.setDebugVisual(True)
    assert d.calls[0][0] == "touch"
    assert any(c[0] == "touch" and c[1] == 2 for c in d.calls)  # has MOVE


def test_aliases_same_impl():
    assert prelude.touch_down is prelude.touchDown
    assert prelude.get_color is prelude.getColor
    assert prelude.tap_image is prelude.tapImage


def test_get_color_int():
    use_fake()
    assert prelude.getColor(1, 1) == 0xFF0000
    assert prelude.get_color(1, 1) == 0xFF0000


def test_find_text_filters():
    d = use_fake()
    d.ocr_items = [{"text": "hello world", "x": "1", "y": "2", "width": "3", "height": "4"},
                   {"text": "other", "x": "5", "y": "6", "width": "7", "height": "8"}]
    assert len(prelude.findText("hello")) == 1
    assert prelude.findText("zzz") == []


def test_ocr_lang_is_normalized_and_forwarded():
    d = use_fake()
    d.ocr_items = [{"text": "Người", "x": "1", "y": "2", "width": "3", "height": "4"}]

    def last_ocr_call():
        return [call for call in d.calls if call[0] == "ocr"][-1]

    assert prelude.findText("Người", lang="vi")
    assert last_ocr_call()[2]["languages"] == ["vi-VN"]

    prelude.ocrText(0, 0, 100, 100, lang=("vi", "en"))
    assert last_ocr_call()[2]["languages"] == ["vi-VN", "en-US"]

    prelude.ocrFind("Người", lang="vi-VN")
    assert last_ocr_call()[2]["languages"] == ["vi-VN"]


def test_ocr_lang_propagates_through_wrappers():
    d = use_fake()
    d.ocr_items = [{"text": "Settings", "x": "1", "y": "2", "width": "3", "height": "4"}]

    def last_ocr_call():
        return [call for call in d.calls if call[0] == "ocr"][-1]

    assert prelude.waitForText("Settings", timeout=0.1, lang="en")
    assert last_ocr_call()[2]["languages"] == ["en-US"]
    assert prelude.tapText("Settings", timeout=0.1, lang="en")
    assert last_ocr_call()[2]["languages"] == ["en-US"]
    assert prelude.swipeUntilText("Settings", maxSwipes=0, lang="en")
    assert last_ocr_call()[2]["languages"] == ["en-US"]


def test_ocr_find_unpacks_like_lua():
    # Lua idiom `local x, y, text = findText("Login")` maps to ocrFind in
    # Python: unpackable triple, falsy when absent.
    d = use_fake()
    d.ocr_items = [{"text": "Files", "x": "100", "y": "200", "width": "60", "height": "20"}]
    x, y, text = prelude.ocrFind("Files")
    assert (x, y) == (130, 210)
    assert text == "Files"
    assert prelude.ocrFind("Files")  # truthy when found
    assert prelude.ocr_find("files")  # case-insensitive + alias
    x, y, text = prelude.ocrFind("zzz")
    assert (x, y, text) == (None, None, None)
    assert not prelude.ocrFind("zzz")  # falsy like Lua nil
    assert prelude.ocrFind("zzz")[:2] == (None, None)


def test_tap_text_index_is_one_based():
    # docs/IDE/ioscontrol.md: index 1 = first. 0 stays accepted as first.
    d = use_fake()
    d.ocr_items = [
        {"text": "Files", "x": "10", "y": "300", "width": "50", "height": "20"},
        {"text": "Files", "x": "10", "y": "100", "width": "50", "height": "20"},
    ]
    m1 = prelude.tapText("Files", timeout=0.1, index=1)
    assert m1["y"] == "100"  # topmost first
    taps = [c for c in d.calls if c[0] == "touch"]
    assert taps  # center of topmost box: (35, 110)
    assert (taps[0][3], taps[0][4]) == (35, 110)
    m2 = prelude.tapText("Files", timeout=0.1, index=2)
    assert m2["y"] == "300"
    m0 = prelude.tapText("Files", timeout=0.1, index=0)
    assert m0["y"] == "100"  # legacy 0 == first
    assert prelude.tapText("Files", timeout=0.1, index=5) is None


def test_tap_image_taps_center():
    d = use_fake()
    m = prelude.tapImage("a.png", timeout=1)
    assert m == {"x": "5.00", "y": "6.00", "width": "10.00", "height": "10.00"}
    assert any(c[0] == "touch" for c in d.calls)


def test_float_string_device_numbers():
    # Regression: daemon replies like '1242.000000', int() on that crashes.
    use_fake()
    assert prelude.screenSize() == {"width": 1242, "height": 2208}
    assert prelude.getColor(1, 1) == 0xFF0000
    assert prelude.findColor(0xFF0000) == [(10, 20)]
    m = prelude.tapText("hello", timeout=0.1)
    assert m is None or isinstance(m, dict)  # must not raise ValueError
    assert prelude._num("1242.000000") == 1242
    assert prelude._num(7) == 7


def test_native_wiring():
    d = use_fake()
    assert prelude.screenshot("a.jpg") == "/var/mobile/Library/ZXTouch/images/a.jpg"
    assert prelude.dialogChoice("T", "a", "b") == 1
    assert prelude.showOverlay({"fps": 60}) is True
    assert prelude.updateOverlay("fps", 30) is True
    assert prelude.hideOverlay() is True
    assert prelude.appKill("com.foo") is True
    assert prelude.appState("com.foo") == 2
    assert prelude.openURL("https://x") is True
    assert prelude.appClear("com.foo") == 3
    prelude.keyDown("home")
    prelude.keyUp("home")
    assert ("key", "home", "down") in d.calls
    assert ("key", "home", "up") in d.calls
    prelude.vibrate()
    assert ("vibrate",) in d.calls


def test_type_text_sends_each_character_with_human_delay(monkeypatch):
    d = use_fake()
    delays = []
    monkeypatch.setattr(prelude.time, "sleep", delays.append)
    monkeypatch.setattr(prelude.random, "uniform", lambda low, high: (low + high) / 2)

    assert prelude.typeText("a b!") is True
    assert [c[1] for c in d.calls if c[0] == "insert"] == ["a", " ", "b", "!"]
    assert len(delays) == 3
    assert all(0.10 <= delay <= 0.52 for delay in delays)
    assert delays[1] > delays[0]  # whitespace adds a short thinking pause
    assert prelude.type_text is prelude.typeText


def test_type_text_rejects_non_string():
    use_fake()
    with pytest.raises(TypeError):
        prelude.typeText(123)


def test_fallbacks_against_old_daemon():
    d = use_fake()  # FakeDevice raises for multi/region/record-device paths
    assert prelude.findColor(0xFF0000) == [(10, 20)]  # legacy single-point
    assert prelude.findImage("a.png") == {"x": "5.00", "y": "6.00", "width": "10.00", "height": "10.00"}
    evs = [{"type": "tap", "x": 1, "y": 2}]
    prelude.recordPlay(evs)  # local replay
    assert any(c[0] == "touch" for c in d.calls)


def test_crane_namespace():
    d = use_fake()
    apps = prelude.crane.list("com.foo")
    assert apps[0]["containers"][0]["name"] == "Main"
    assert prelude.crane.list()[0]["bundleId"] == "com.foo"
    assert prelude.crane.switch("com.foo", "Main")["active"] == "c1"
    assert prelude.crane.create("com.foo", "Acc2")["id"] == "c2"
    assert prelude.crane.delete("com.foo", "Acc2")["ok"] is True
    assert prelude.crane.wipe("com.foo", "Acc2")["ok"] is True
    assert prelude.crane.rename("com.foo", "A", "B")["ok"] is True
    assert prelude.crane.clearData("com.foo")["cleared"] == 5
    assert prelude.crane.clear_data("com.foo", "Main")["cleared"] == 5
    assert prelude.crane.backup("com.foo")["path"].endswith(".tar.gz")
    assert prelude.crane.restore("com.foo", "/tmp/f.tar.gz")["ok"] is True
    assert prelude.crane.size("com.foo")["total"] == 100
    assert ("crane", "switch", {"bundleId": "com.foo", "name": "Main"}) in d.calls


def test_client_crane_payload_format():
    import base64
    import json
    from zxtouch import client as client_mod
    from zxtouch import tasktypes, datahandler

    sent = []

    class FakeSock:
        def send(self, data):
            sent.append(data)

        def recv(self, n):
            body = base64.b64encode(json.dumps({"ok": True}).encode()).decode()
            return ("0;;" + body + "\r\n").encode()

    dev = client_mod.zxtouch.__new__(client_mod.zxtouch)
    dev.s = FakeSock()
    ok, res = dev.crane_switch("com.foo", "Main")
    assert ok and res == {"ok": True}
    raw = sent[0].decode()
    assert raw.startswith("47")  # TASK_CRANE
    payload = json.loads(base64.b64decode(raw[2:-2].split(";;")[0]).decode())
    assert payload == {"bundleId": "com.foo", "name": "Main", "op": "switch"}
    assert tasktypes.TASK_CRANE == 47
    # datahandler round-trips the reply form
    assert datahandler.decode_socket_data(sent[0].__class__(raw.encode()))[0] in (True, False)


def test_runner_injects_and_disconnects(tmp_path):
    import zxtouch.runner as runner
    script = tmp_path / "s.py"
    script.write_text("tap(10, 20)\nlog('hi')\n", encoding="utf-8")
    prelude.disconnect()
    d = prelude.set_device(FakeDevice())
    rc = runner.main(["runner", str(script)])
    assert rc == 0
    assert any(c[0] == "touch" for c in d.calls)
    assert ("disconnect",) in d.calls or prelude._DEVICE is None


# ------------------------------------------------------------- httpGet/httpPost

class _HttpFixture:
    """Tiny local server so the HTTP paths are tested without internet.

    Records the request headers the prelude actually sent, which is how the
    User-Agent regression (Cloudflare 403 "error code: 1010") stays caught.
    """

    def __init__(self):
        import http.server
        import threading

        outer = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def _respond(self):
                outer.requests.append({
                    "method": self.command,
                    "path": self.path,
                    "headers": {k.lower(): v for k, v in self.headers.items()},
                })
                code, body = outer.reply_for(self.path)
                raw = body.encode()
                self.send_response(code)
                self.send_header("Content-Type", "text/plain")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

            do_GET = _respond
            do_POST = _respond

        self.server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
        self.port = self.server.server_address[1]
        self.requests = []
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def reply_for(self, path):
        if path.startswith("/403"):
            return 403, "error code: 1010"
        if path.startswith("/tok"):
            return 200, '{"token":"159244"}'
        return 200, "pong"

    def url(self, suffix=""):
        return "http://127.0.0.1:%d/%s" % (self.port, suffix)

    def close(self):
        self.server.shutdown()
        self.server.server_close()


@pytest.fixture
def http_srv():
    srv = _HttpFixture()
    try:
        yield srv
    finally:
        srv.close()


@pytest.fixture
def urllib_only(monkeypatch):
    """Force the urllib fallback: Procursus installs Python without requests."""
    monkeypatch.setattr(prelude, "_load_requests", lambda: None)


@pytest.fixture
def fake_requests(monkeypatch):
    """Stand in for the requests module, backed by urllib under the hood."""
    import urllib.error
    import urllib.request

    class R:
        def __init__(self, raw, code, url):
            self.text = raw.decode("utf-8", "replace")
            self.status_code = code
            self.url = url
            self.headers = {}

    def request(method, url, data=None, headers=None, timeout=None):
        req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return R(resp.read(), resp.getcode(), resp.geturl())
        except urllib.error.HTTPError as e:
            return R(e.read() or b"", e.code, url)

    monkeypatch.setattr(prelude, "_load_requests", lambda: types.SimpleNamespace(request=request))


def test_httpget_sends_browser_user_agent(http_srv, urllib_only):
    # The 403 regression: urllib's default "Python-urllib/3.x" UA is blocked by
    # Cloudflare, so the old httpGet aborted scripts on 2fa.live-style APIs.
    resp = prelude.httpGet(http_srv.url("tok"))
    assert resp.status == 200
    assert "Mozilla/5.0" in http_srv.requests[0]["headers"]["user-agent"]
    assert "Python-urllib" not in http_srv.requests[0]["headers"]["user-agent"]


def test_httpget_body_is_string_with_status(http_srv, urllib_only):
    resp = prelude.httpGet(http_srv.url("tok"))
    assert isinstance(resp, str) and resp == '{"token":"159244"}'
    assert json.loads(resp)["token"] == "159244"  # old call sites keep working
    assert resp.ok is True
    assert (resp + "!").endswith("!")


def test_httpget_does_not_raise_on_http_error(http_srv, urllib_only):
    # Before the fix this raised HTTPError and killed the whole script run.
    resp = prelude.httpGet(http_srv.url("403"))
    assert resp.status == 403
    assert resp.ok is False
    assert "1010" in resp
    assert not resp.ok and not resp.startswith("ok")


def test_httpget_returns_falsy_on_connection_failure(monkeypatch):
    monkeypatch.setattr(prelude, "_load_requests", lambda: None)
    resp = prelude.httpGet("http://127.0.0.1:1/nope", None, 2)
    assert not resp and resp.status == 0  # Lua-like nil check


def test_httpget_custom_headers_win(http_srv, urllib_only):
    prelude.httpGet(http_srv.url("tok"), {"User-Agent": "utouch-test/1", "X-Key": "abc"})
    h = http_srv.requests[0]["headers"]
    assert h["user-agent"] == "utouch-test/1" and h["x-key"] == "abc"


def test_httppost_sends_body_and_never_raises(http_srv, urllib_only):
    resp = prelude.httpPost(http_srv.url("login"), json.dumps({"a": 1}),
                            {"Content-Type": "application/json"})
    assert resp == "pong" and resp.status == 200
    assert http_srv.requests[-1]["method"] == "POST"
    bad = prelude.httpPost(http_srv.url("403"), "x")
    assert bad.status == 403 and "1010" in bad


def test_httpget_works_with_requests_installed(http_srv, fake_requests):
    # Both backends share one contract: string body, .status, no exceptions.
    ok = prelude.httpGet(http_srv.url("tok"))
    assert ok == '{"token":"159244"}' and ok.status == 200 and ok.ok
    err = prelude.httpGet(http_srv.url("403"))
    assert err.status == 403 and not err.ok and "1010" in err


def test_http_response_names_are_exported():
    assert "HttpResponse" in prelude.__all__
    assert "httpGet" in prelude.__all__ and "http_post" in prelude.__all__


# ------------------------------------------------------- sec-util (network/radio/proxy)

class ShellDevice:
    """Fake daemon whose run_shell_command honours the '>out 2>&1' redirect.

    Mirrors the real TASK_RUN_SHELL contract: output is dropped by the daemon,
    so _shellCapture must redirect to a file and read it back.
    """

    def __init__(self, replies=None):
        self.replies = replies or {}
        self.calls = []

    def run_shell_command(self, cmd):
        self.calls.append(cmd)
        for needle, out in self.replies.items():
            if needle in cmd:
                # _shellCapture emits "<cmd> ><file> 2>&1"; take the file from
                # the first redirect, not the 2>&1 that follows it.
                m = re.search(r">\s*(\S+)\s+2>&1\s*$", cmd)
                if not m:
                    return (True, "")
                try:
                    with open(m.group(1), "w", encoding="utf-8") as f:
                        f.write(out)
                except OSError:
                    pass
                return (True, "")
        return (True, "")

    def accurate_usleep(self, us):
        return (True, "")

    def get_screen_size(self):
        return (True, {"width": "100", "height": "200"})


def test_shellcapture_forwards_redirect_and_reads_back():
    dev = ShellDevice({"ipconfig": "10.0.0.5\n"})
    prelude.set_device(dev)
    try:
        ok, out = prelude._shellCapture("/usr/sbin/ipconfig getifaddr en0")
        assert ok and out == "10.0.0.5"
        assert any("ipconfig" in c and c.rstrip().endswith("2>&1") for c in dev.calls)
    finally:
        prelude.disconnect()


def test_shellcapture_rejects_double_quotes():
    # The daemon wraps commands in sh -c "..."; a quote would break out of it.
    ok, why = prelude._shellCapture('echo "hi"')
    assert not ok and "double quote" in why


def test_wifiinfo_uses_shell_ip_and_keeps_ssid_none():
    dev = ShellDevice({"ipconfig": "192.168.1.77\n"})
    prelude.set_device(dev)
    try:
        info = prelude.wifiInfo()
        assert info["ip"] == "192.168.1.77" and info["ssid"] is None
    finally:
        prelude.disconnect()


def test_wifiinfo_falls_back_when_shell_unusable():
    class DeadShell(ShellDevice):
        def run_shell_command(self, cmd):
            return (False, "daemon unreachable")

    prelude.set_device(DeadShell())
    try:
        info = prelude.wifiInfo()  # UDP-socket fallback; must not raise
        assert isinstance(info["ip"], str) and "ssid" in info
    finally:
        prelude.disconnect()


def test_rootpython_blocks_bad_interpreter_and_metacharacters(monkeypatch):
    monkeypatch.setattr(prelude.sys, "executable", "relative/python.exe")
    ok, why = prelude._rootPython(["pref-set", "/x.plist", "k", "1"])
    assert not ok and "interpreter" in why
    monkeypatch.setattr(prelude.sys, "executable", "/bin/python3")
    ok, why = prelude._rootPython(["pref-set", "/x.plist", "k", "1; rm -rf /"])
    assert not ok and "metacharacter" in why


def test_rootpython_parses_zxok_and_zxerr(monkeypatch):
    monkeypatch.setattr(prelude.sys, "executable", "/bin/python3")
    captured = {"cmd": "", "out": ""}

    def fake_capture(cmd, timeout=15):
        captured["cmd"] = cmd
        return True, captured["out"]

    monkeypatch.setattr(prelude, "_shellCapture", fake_capture)

    captured["out"] = "ZXOK 1"
    assert prelude._rootPython(["pref-set", "/x.plist", "k", "1"]) == (True, "1")
    assert captured["cmd"].endswith("pref-set /x.plist k 1")

    captured["out"] = "ZXERR FileNotFoundError"
    ok, why = prelude._rootPython(["pref-set", "/x.plist", "k", "1"])
    assert not ok and "FileNotFoundError" in why

    captured["out"] = ""  # silent helper == inconclusive, never a success
    ok, _ = prelude._rootPython(["pref-set", "/x.plist", "k", "1"])
    assert not ok


def test_helper_writes_and_verifies_real_plists(tmp_path):
    # End-to-end on the shipped helper source: no device, real plistlib.
    import plistlib
    import subprocess

    helper = prelude._utilHelperDir()
    assert open(helper, encoding="utf-8").read() == prelude._UTIL_HELPER

    radio = str(tmp_path / "commcenter.plist")
    with open(radio, "wb") as f:
        plistlib.dump({"preflightAirplaneModeEnabled": 0, "KeepMe": {"a": 1}}, f)
    p = subprocess.run([sys.executable, helper, "pref-set", radio,
                        "preflightAirplaneModeEnabled", "1"],
                       capture_output=True, text=True, timeout=60)
    assert p.returncode == 0 and "ZXOK 1" in p.stdout, p.stdout + p.stderr
    with open(radio, "rb") as f:
        d = plistlib.load(f)
    assert d["preflightAirplaneModeEnabled"] == 1
    assert d["KeepMe"] == {"a": 1}  # unrelated keys survive

    prefs = str(tmp_path / "preferences.plist")
    with open(prefs, "wb") as f:
        plistlib.dump({"Global": {"Services": {"x": 1}}, "UserDefined": {"y": 2}}, f)
    p = subprocess.run([sys.executable, helper, "proxy-set", prefs, "160.25.77.31", "8770"],
                       capture_output=True, text=True, timeout=60)
    assert p.returncode == 0, p.stdout + p.stderr
    with open(prefs, "rb") as f:
        d = plistlib.load(f)
    assert d["Global"]["Proxy"]["HTTPProxy"] == "160.25.77.31"
    assert d["Global"]["Proxy"]["HTTPPort"] == 8770
    assert d["Global"]["Services"] == {"x": 1} and d["UserDefined"] == {"y": 2}

    p = subprocess.run([sys.executable, helper, "proxy-clear", prefs],
                       capture_output=True, text=True, timeout=60)
    assert p.returncode == 0, p.stdout + p.stderr
    with open(prefs, "rb") as f:
        d = plistlib.load(f)
    assert "Proxy" not in d["Global"] and d["Global"]["Services"] == {"x": 1}

    missing = str(tmp_path / "nope.plist")
    p = subprocess.run([sys.executable, helper, "pref-set", missing, "k", "1"],
                       capture_output=True, text=True, timeout=60)
    assert p.returncode == 1 and "ZXERR" in (p.stdout + p.stderr)  # reported, not a crash


def test_proxy_input_validation():
    # Rejections happen before any daemon round-trip: no device needed.
    assert prelude.setProxySystem("bad host", 80) is False
    assert prelude.setProxySystem("1.2.3.4; rm", 80) is False
    assert prelude.setProxySystem("1.2.3.4", 0) is False
    assert prelude.setProxySystem("1.2.3.4", 70000) is False
    assert prelude.setProxySystem("1.2.3.4", "abc") is False


def test_util_toggles_fail_soft_without_device(monkeypatch, capsys):
    # No daemon reachable: every toggle returns False, logs a reason and does
    # NOT raise — the httpGet lesson: a script must survive a failed call.
    monkeypatch.setattr(prelude, "_shellCapture",
                        lambda cmd, timeout=15: (False, "daemon unreachable"))
    assert prelude.setAirplaneMode(True) is False
    assert prelude.setCellularData(False) is False
    assert prelude.setProxySystem("1.2.3.4", 8080) is False
    assert prelude.clearProxySystem() is False
    assert "daemon unreachable" in capsys.readouterr().out


def test_getip_validates_lookup(monkeypatch):
    monkeypatch.setattr(prelude, "httpGet",
                        lambda url, headers=None, timeout=15: prelude.HttpResponse("203.0.113.9", 200))
    assert prelude.getIP() == "203.0.113.9"
    monkeypatch.setattr(prelude, "httpGet",
                        lambda url, headers=None, timeout=15: prelude.HttpResponse("<html>blocked</html>", 403))
    assert prelude.getIP() == ""  # never raises, never returns HTML


def test_util_exports_and_aliases():
    for name in ["wifiInfo", "getIP", "setAirplaneMode", "setCellularData",
                 "setProxySystem", "clearProxySystem",
                 "wifi_info", "get_ip", "set_airplane_mode", "set_cellular_data",
                 "set_proxy_system", "clear_proxy_system"]:
        assert name in prelude.__all__, name
        assert callable(getattr(prelude, name)), name


def test_log_accepts_multiple_values(capsys):
    # log("10", "20", "30", 50, x, y) prints space-separated.
    assert prelude.log("10", "20", "30", 50, 60, 70) is True
    out = capsys.readouterr().out
    assert out.strip() == "10 20 30 50 60 70"
    assert prelude.log("done") is True
    assert capsys.readouterr().out.strip() == "done"


def test_debug_visual_tap_swipe_ocr_image():
    # Debug overlay đỏ: tap -> circle, swipe -> line, OCR/image -> rect.
    # Daemon cũ (không có debug_mark) cũng không được làm crash script.
    d = use_fake()
    prelude.setDebugVisual(True, 1.5)
    prelude.tap(100, 200)
    assert ("debug", "circle", (100, 200, 60), 1.5) in d.calls
    prelude.swipe(10, 20, 30, 40, 0.04)
    assert ("debug", "line", (10, 20, 30, 40), 1.5) in d.calls
    d.ocr_items = [{"text": "Notes", "x": "400", "y": "1100",
                    "width": "100", "height": "40"}]
    matches = prelude.findText("notes")
    assert len(matches) == 1
    assert ("debug", "rect", (400, 1100, 100, 40), 1.5) in d.calls
    m = prelude.tapText("notes", timeout=0.1)
    assert m["text"] == "Notes"
    # tapText -> findText (rect) + tap (circle)
    assert any(c[0] == "debug" and c[1] == "circle" for c in d.calls)
    # Tắt debug: không còn gọi native nữa.
    prelude.setDebugVisual(False)
    n = len(d.calls)
    prelude.tap(1, 2)
    assert len([c for c in d.calls[n:] if c[0] == "debug"]) == 0
    prelude.setDebugVisual(True)


def test_keyboard_helpers_report_and_control_visibility():
    d = use_fake()
    assert prelude.showKeyboard() is True
    assert prelude.hideKeyboard() is True
    assert prelude.keyboardVisible() is True
    assert ("keyboard_show",) in d.calls
    assert ("keyboard_hide",) in d.calls
    assert ("keyboard_visible",) in d.calls


def test_debug_visual_old_daemon_still_allows_tap():
    # Daemon cũ không có debug_mark -> nuốt lỗi, tap vẫn chạy.
    prelude.disconnect()
    class OldDaemon(FakeDevice):
        def debug_mark(self, *a, **k):
            raise RuntimeError("old daemon")
    old = prelude.set_device(OldDaemon())
    prelude.tap(5, 6)  # must not raise
    assert any(c[0] == "touch" for c in old.calls)
    prelude.setDebugVisual(True)


def test_plus_model_rendered_coords_pass_through_unchanged():
    # Regression (iPhone 7 Plus, 0.3.4): OCR/screenshot/screenSize speak
    # RENDERED pixels (1242x2208); the daemon normalizes touches by the same
    # space. Python must forward OCR centers to touch byte-identical —
    # no hidden rescale/clamp (a y=1952 must NOT become <=1920 here).
    d = use_fake()
    d.screen = {"width": "1242.000000", "height": "2208.000000"}
    d.ocr_items = [{"text": "Continue", "x": "600", "y": "1930",
                    "width": "54", "height": "44"}]  # center = (627, 1952)
    prelude.setDebugVisual(False)
    m = prelude.tapText("Continue", timeout=0.1)
    prelude.setDebugVisual(True)
    assert m is not None
    touches = [c for c in d.calls if c[0] == "touch"]
    assert (touches[0][3], touches[0][4]) == (627, 1952)
    assert (touches[1][3], touches[1][4]) == (627, 1952)


def test_client_debug_mark_wire_format():
    from zxtouch import client as client_mod
    sent = []

    class FakeSock:
        def send(self, data):
            sent.append(data)

        def recv(self, n):
            return b"0\r\n"

    dev = client_mod.zxtouch.__new__(client_mod.zxtouch)
    dev.s = FakeSock()
    ok, _ = dev.debug_mark("rect", (1, 2, 3, 4), 1.5)
    assert ok
    raw = sent[0].decode()
    assert raw.startswith("48")  # TASK_DEBUG_MARK
    assert "rect" in raw and "1,2,3,4" in raw


def test_touch_with_list_accepts_floats():
    # pinch()/rotate() build float coords; '{:05d}'.format(float) raises.
    from zxtouch import client as client_mod

    sent = []

    class FakeSock:
        def send(self, data):
            sent.append(data)

        def recv(self, n):
            return b"0\r\n"

    dev = client_mod.zxtouch.__new__(client_mod.zxtouch)
    dev.s = FakeSock()
    dev.touch_with_list([
        {"type": 1, "finger_index": 1, "x": 150.5, "y": 400.25},
        {"type": 1, "finger_index": 2, "x": 250.75, "y": 400.0},
    ])
    assert sent  # must not raise ValueError


def test_find_colors_multi_float_screen_size():
    # get_screen_size replies like '1242.000000'; int() on that crashes.
    from zxtouch import client as client_mod

    sent = []

    class FakeSock:
        def send(self, data):
            sent.append(data)

        def recv(self, n):
            if not hasattr(self, "n"):
                self.n = 0
            self.n += 1
            if self.n == 1:
                return b"0;;1242.000000;;2208.000000\r\n"
            return b"0;;10,20\r\n"

    dev = client_mod.zxtouch.__new__(client_mod.zxtouch)
    dev.s = FakeSock()
    ok, pts = dev.find_colors_multi("FF0000")
    assert ok and pts == [(10, 20)]  # must not raise ValueError


# ---------------------------------------------------------------- Lua tables (A3 + jsonDecode/jsonEncode)

def test_luadict_field_access_and_nil_like_missing():
    t = prelude.LuaDict({"width": 750, "height": 1334})
    assert t.width == 750 and t["height"] == 1334     # both syntaxes
    assert t.missing is None                          # like Lua nil
    assert t.get("missing", "d") == "d"
    t.extra = 1
    assert t["extra"] == 1
    del t.extra
    assert "extra" not in t
    assert t == {"width": 750, "height": 1334}        # still a plain-equal dict
    assert json.loads(prelude.jsonEncode(t)) == t
    d = {"a": 1}                                      # a real dict is NOT fooled
    try:
        d.a
    except AttributeError:
        pass
    else:
        raise AssertionError("plain dict gained attribute access?")


def test_luadict_key_colliding_with_method_stays_subscriptable():
    t = prelude.LuaDict({"get": "value"})
    assert t["get"] == "value"          # subscript wins for colliding keys
    assert callable(dict.get)           # attribute side keeps the method


def test_jsondecode_lua_field_access():
    # docs/IDE/ioscontrol.md shape the user reported:
    #   local config = jsonDecode(raw); log(config.loops); log(config.delay)
    raw = '{"loops": 3, "delay": 0.5, "nested": {"a": {"b": 1}}}'
    cfg = prelude.jsonDecode(raw)
    assert cfg.loops == 3
    assert cfg.delay == 0.5
    assert cfg.nested.a.b == 1          # every level is a LuaDict
    assert isinstance(cfg, dict)        # and still a plain-compatible dict


def test_jsondecode_missing_field_is_nil_like():
    cfg = prelude.jsonDecode('{"a": 1}')
    assert cfg.haha is None


def test_jsonencode_handles_tuple_set_and_utf8():
    assert prelude.jsonEncode((1, 2)) == "[1, 2]"
    assert prelude.jsonEncode([(10, 20), (30, 40)]) == "[[10, 20], [30, 40]]"
    assert prelude.jsonEncode({7}) == "[7]"
    assert prelude.jsonEncode({"mức": "xin chào"}) == '{"mức": "xin chào"}'  # no \u escapes
    assert prelude.jsonEncode(prelude.LuaDict({"a": [1, 2]})) == '{"a": [1, 2]}'


def test_json_roundtrip():
    raw = '{"loops": 3, "delay": 0.5, "nested": {"a": {"b": 1}}, "list": [1, "x", null]}'
    cfg = prelude.jsonDecode(raw)
    assert prelude.jsonDecode(prelude.jsonEncode(cfg)) == cfg


def test_screen_size_and_matches_are_lua_tables():
    d = use_fake()
    s = prelude.screenSize()
    assert s.width == 1242 and s.height == 2208      # docs example uses s.width
    assert s == {"width": 1242, "height": 2208}      # old contract kept
    info = prelude.deviceInfo()
    assert info.name == "iPhone"
    d.ocr_items = [{"text": "Files", "x": "1", "y": "2", "width": "3", "height": "4"}]
    m = prelude.findText("Files")[0]
    assert m.x == "1" and m["text"] == "Files"       # attr + subscript alike
    im = prelude.findImage("a.png")
    assert im.x == "5.00" and im["y"] == "6.00"
    assert im == {"x": "5.00", "y": "6.00", "width": "10.00", "height": "10.00"}


def test_lua_helpers_are_exported():
    for name in ("LuaDict", "zxRange", "zxUnpackMatch", "zxConcat"):
        assert name in prelude.__all__, name
    injected = prelude.install({})
    for name in ("LuaDict", "zxRange", "zxUnpackMatch", "zxConcat"):
        assert name in injected, name


# ---------------------------------------------------------------- zx* runtime helpers (A1/A2/concat)

def test_zxrange_matches_lua_numeric_for():
    assert list(prelude.zxRange(10, 1, -1)) == [10, 9, 8, 7, 6, 5, 4, 3, 2, 1]
    assert list(prelude.zxRange(10, 1, -3)) == [10, 7, 4, 1]
    assert list(prelude.zxRange(1, 10, 2)) == [1, 3, 5, 7, 9]
    assert list(prelude.zxRange(1, 3)) == [1, 2, 3]
    assert list(prelude.zxRange(3, 3)) == [3]
    with pytest.raises(ValueError):
        list(prelude.zxRange(1, 5, 0))


def test_zxunpackmatch_shapes():
    m = {"x": "5", "y": "6", "width": "10", "height": "10"}
    assert prelude.zxUnpackMatch(m) == (True, 10, 11)      # centre, like tapImage taps
    assert prelude.zxUnpackMatch(None) == (False, None, None)
    assert prelude.zxUnpackMatch(False) == (False, None, None)
    assert prelude.zxUnpackMatch(True) == (True, None, None)
    assert prelude.zxUnpackMatch([(10, 20), (30, 40)]) == (True, 10, 20)
    assert prelude.zxUnpackMatch([]) == (False, None, None)
    use_fake()
    ok, x, y = prelude.zxUnpackMatch(prelude.tapImage("a.png", timeout=1))
    assert (ok, x, y) == (True, 10, 11)                    # FakeDevice match (5+10/2, 6+10/2)


def test_zxconcat_lua_coercion():
    assert prelude.zxConcat("Loops: ", 3) == "Loops: 3"
    assert prelude.zxConcat("Delay: ", 0.5, "s") == "Delay: 0.5s"
    assert prelude.zxConcat("f=", 2.0) == "f=2"            # Lua prints 2, not 2.0
    assert prelude.zxConcat("t=", True, " f=", False) == "t=true f=false"
    assert prelude.zxConcat("x", None) == "xnil"


# ---------------------------------------------------------------- A4/A5 honest fallbacks

def test_find_color_fallback_logs_warning(capsys):
    d = use_fake()                     # FakeDevice: find_colors_multi raises (old daemon)
    got = prelude.findColor(0xFF0000, count=5)
    assert got == [(10, 20)]            # legacy searcher can only answer its first hit
    out = capsys.readouterr().out
    assert "findColor" in out and "1/5" in out   # ...and says so, no silent shortfall


def test_search_color_clamps_bounds():
    d = use_fake()
    prelude.findColor(0x0a0a0a, tolerance=10)
    call = [c for c in d.calls if c[0] == "search"][-1][1]
    # region, then three (min,max) pairs; r-t was -6 before the clamp
    assert call[1:] == (0, 20, 0, 20, 0, 20)
    prelude.findColor(0xf5f5f5, tolerance=20)
    call = [c for c in d.calls if c[0] == "search"][-1][1]
    assert call[1:] == (225, 255, 225, 255, 225, 255)     # upper clamp too (0xf5=245, +20>255)


def test_find_image_multi_reports_count(capsys):
    class MultiDev:
        def get_screen_size(self):
            return (True, {"width": "750", "height": "1334"})

        def image_match_multi(self, path, threshold, count):
            return (True, [{"x": "1", "y": "2", "width": "4", "height": "4"},
                           {"x": "5", "y": "6", "width": "4", "height": "4"}])

        def debug_mark(self, *a, **k):
            return (True, "")

    prelude.set_device(MultiDev())
    try:
        m = prelude.findImage("a.png", count=4)
        assert m == {"x": "1", "y": "2", "width": "4", "height": "4"}  # one-match contract
        assert m.x == "1"                                             # Lua-style access
        out = capsys.readouterr().out
        assert "2/4" in out                                  # no silent discard of extra matches
    finally:
        prelude.disconnect()


# ---------------------------------------------------------------- .bdl image paths

def test_find_image_resolves_name_in_script_bundle(tmp_path):
    # The daemon opens the template relative to its own working directory, so a
    # bare name must be turned into the script's own path before it is sent.
    bundle = tmp_path / "demo.bdl"
    bundle.mkdir()
    (bundle / "home-activ.png").write_bytes(b"\x89PNG\r\n")
    d = use_fake()
    prelude.setScriptDir(str(bundle / "home.py"))
    try:
        prelude.findImage("home-activ.png")
        assert [c for c in d.calls if c[0] == "image"][-1][1] == (
            str(bundle / "home-activ.png"), 0.8, 2, 0.8)
    finally:
        prelude.setScriptDir(None)


def test_find_image_resolves_relative_subdir(tmp_path):
    bundle = tmp_path / "demo.bdl"
    (bundle / "img").mkdir(parents=True)
    (bundle / "img" / "btn.png").write_bytes(b"\x89PNG\r\n")
    d = use_fake()
    prelude.setScriptDir(str(bundle / "home.py"))
    try:
        prelude.findImage("img/btn.png")
        assert [c for c in d.calls if c[0] == "image"][-1][1] == (
            os.path.join(str(bundle), "img/btn.png"), 0.8, 2, 0.8)
    finally:
        prelude.setScriptDir(None)


def test_find_image_leaves_other_paths_alone(tmp_path):
    bundle = tmp_path / "demo.bdl"
    bundle.mkdir()
    d = use_fake()
    prelude.setScriptDir(str(bundle / "home.py"))
    try:
        prelude.findImage("missing.png")            # not shipped with the script
        assert [c for c in d.calls if c[0] == "image"][-1][1] == ("missing.png", 0.8, 2, 0.8)
        prelude.findImage("/var/mobile/abs.png")    # absolute path untouched
        assert [c for c in d.calls if c[0] == "image"][-1][1] == ("/var/mobile/abs.png", 0.8, 2, 0.8)
    finally:
        prelude.setScriptDir(None)
    prelude.findImage("manual.png")                 # outside a run, old behaviour
    assert [c for c in d.calls if c[0] == "image"][-1][1] == ("manual.png", 0.8, 2, 0.8)


def test_tap_image_resolves_in_bundle(tmp_path):
    bundle = tmp_path / "demo.bdl"
    bundle.mkdir()
    (bundle / "btn.png").write_bytes(b"\x89PNG\r\n")
    d = use_fake()
    prelude.setScriptDir(str(bundle / "home.py"))
    try:
        m = prelude.tapImage("btn.png", timeout=0.1)
        assert m == {"x": "5.00", "y": "6.00", "width": "10.00", "height": "10.00"}
        assert ("image", (str(bundle / "btn.png"), 0.8, 2, 0.8)) in d.calls
    finally:
        prelude.setScriptDir(None)


def test_runner_announces_script_dir(tmp_path):
    import zxtouch.runner as runner
    script = tmp_path / "s.py"
    script.write_text("pass\n", encoding="utf-8")
    prelude.disconnect()
    prelude.set_device(FakeDevice())
    try:
        assert runner.main(["runner", str(script)]) == 0
        assert prelude._SCRIPT_DIR == str(tmp_path)
    finally:
        prelude.setScriptDir(None)
        prelude.disconnect()


def test_asset_dir_can_differ_from_script_dir(tmp_path):
    # An editor run stages the code in a scratch bundle of its own, so the assets
    # stay in the bundle the edited tab came from: relative names resolve against
    # the announced asset dir, not against the entry file's folder.
    bundle = tmp_path / "auto-threads.bdl"
    (bundle / "img").mkdir(parents=True)
    (bundle / "threads.png").write_bytes(b"\x89PNG\r\n")
    (bundle / "img" / "btn.png").write_bytes(b"\x89PNG\r\n")
    scratch = tmp_path / "__editor__.bdl"
    scratch.mkdir()
    (scratch / "entry.py").write_text("pass\n", encoding="utf-8")
    d = use_fake()
    try:
        prelude.setAssetDir(str(bundle))
        prelude.findImage("threads.png")
        assert [c for c in d.calls if c[0] == "image"][-1][1] == (
            str(bundle / "threads.png"), 0.8, 2, 0.8)
        prelude.findImage("img/btn.png")
        assert [c for c in d.calls if c[0] == "image"][-1][1] == (
            os.path.join(str(bundle), "img/btn.png"), 0.8, 2, 0.8)
        prelude.findImage("missing.png")            # nowhere in the asset dir
        assert [c for c in d.calls if c[0] == "image"][-1][1] == ("missing.png", 0.8, 2, 0.8)
    finally:
        prelude.setAssetDir(None)
    assert prelude._SCRIPT_DIR is None


def test_runner_prefers_env_asset_dir(tmp_path, monkeypatch):
    import zxtouch.runner as runner
    scratch = tmp_path / "__editor__.bdl"
    scratch.mkdir()
    script = scratch / "entry.py"
    script.write_text("pass\n", encoding="utf-8")
    bundle = tmp_path / "auto-threads.bdl"
    bundle.mkdir()
    prelude.disconnect()
    prelude.set_device(FakeDevice())
    monkeypatch.setenv("ZX_ASSET_DIR", str(bundle))
    try:
        assert runner.main(["runner", str(script)]) == 0
        assert prelude._SCRIPT_DIR == str(bundle)
    finally:
        prelude.setAssetDir(None)
        prelude.disconnect()


# ---------------------------------------------------------------- transpiled-Lua call shapes

def test_find_colors_accepts_lua_lists():
    # Transpiled Lua hands findColors [[c, dx, dy], ...] (lists, not tuples)
    # plus a list region; the client must still build its wire payload and the
    # anchor+verify loop must unpack each entry (FakeDevice's pick_color only
    # answers red, so the green offset fails verification and no match lands).
    d = use_fake()                      # old daemon: pattern task raises, naive path runs
    got = prelude.findColors([[0xFF0000, 0, 0], [0x00FF00, 10, 0]],
                             region=[0, 0, 100, 100])
    assert got == []                    # must not raise TypeError on unpacking
    assert any(c[0] == "search" for c in d.calls)   # anchor search really ran
    match = prelude.findColors([[0xFF0000, 0, 0]], region=[0, 0, 100, 100])
    assert match == [(10, 20)]          # single-anchor pattern verifies clean
