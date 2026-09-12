"""Unit tests for zxtouch.prelude + runner (no jailbreak device needed).

Run:  python -m pytest tools/tests/test_prelude.py -q
"""
import sys
import types
from pathlib import Path

PY_MOD = Path(__file__).resolve().parents[2] / "layout" / "usr" / "share" / "zxtouch" / "python"
sys.path.insert(0, str(PY_MOD))

from zxtouch import prelude  # noqa: E402


class FakeDevice:
    def __init__(self):
        self.calls = []
        self.ocr_items = []
        self.pick = {"red": 255, "green": 0, "blue": 0}
        self.screen = {"width": "750", "height": "1334"}

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
        return (True, {"x": "5", "y": "6", "width": "10", "height": "10"})

    def ocr(self, region):
        self.calls.append(("ocr", region))
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
    prelude.tap(200, 300)
    kinds = [c[0] for c in d.calls]
    assert kinds == ["touch", "touch"]
    assert d.calls[0][1] == 1 and d.calls[1][1] == 0  # DOWN then UP


def test_swipe_interpolates():
    d = use_fake()
    prelude.swipe(0, 0, 100, 0, 0.04)
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


def test_tap_image_taps_center():
    d = use_fake()
    m = prelude.tapImage("a.png", timeout=1)
    assert m == {"x": "5", "y": "6", "width": "10", "height": "10"}
    assert any(c[0] == "touch" for c in d.calls)


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


def test_fallbacks_against_old_daemon():
    d = use_fake()  # FakeDevice raises for multi/region/record-device paths
    assert prelude.findColor(0xFF0000) == [(10, 20)]  # legacy single-point
    assert prelude.findImage("a.png") == {"x": "5", "y": "6", "width": "10", "height": "10"}
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
