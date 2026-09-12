"""IOSControl-style globals for ZXTouch Python scripts.

Phase 1: pure-Python helpers over the existing socket tasks (:6000).
No new ObjC TASK_* required for functions implemented here.

Usage (manual run, e.g. over SSH):
    from zxtouch.prelude import *
    tap(200, 300)

When scripts are launched from SpringBoard via ``python -m zxtouch.runner``,
all public names in ``__all__`` are pre-injected into ``__main__`` so user
scripts can call ``tap(...)`` with zero boilerplate. Old-style scripts
(``from zxtouch.client import zxtouch; device = zxtouch(...)``) keep working.

Naming: every function has a Lua-style camelCase name (matching
docs/IDE/ioscontrol.md) plus a snake_case alias. Both point to the same impl.
"""

import base64
import hashlib
import json
import math
import os
import random
import time

from zxtouch.client import zxtouch
from zxtouch import touchtypes

TOUCH_DOWN = touchtypes.TOUCH_DOWN
TOUCH_MOVE = touchtypes.TOUCH_MOVE
TOUCH_UP = touchtypes.TOUCH_UP

_DEVICE = None
_DEVICE_IP = "127.0.0.1"

# ---------------------------------------------------------------- Debug visual
# Vẽ debug trực tiếp lên màn hình iPhone (module native DebugOverlay,
# TASK_DEBUG_MARK=48 — giống module Toast: fire-and-forget, không chặn touch).
#  * OCR / findImage (có match) -> hình chữ nhật (bounding box) đỏ
#  * tap / longPress            -> vòng tròn đỏ (r=60px, >=20pt sau convert)
#  * swipe                      -> đoạn thẳng đỏ + 2 đầu mút
# Mặc định BẬT để user thấy runtime chạm vào đâu; tắt bằng
# setDebugVisual(False). Daemon cũ chưa có task 48 -> tự bỏ qua, script
# vẫn chạy bình thường.
_DEBUG_VISUAL = True
_DEBUG_DURATION = 1.5
_DEBUG_TAP_RADIUS = 60


def setDebugVisual(enabled=True, duration=1.5):
    """Bật/tắt vẽ debug lên màn hình iPhone.

    :param enabled: True = vẽ bbox/circle/line đỏ, False = tắt hẳn.
    :param duration: số giây mỗi hình tồn tại (0.3..5, mặc định 1.5).
    """
    global _DEBUG_VISUAL, _DEBUG_DURATION
    _DEBUG_VISUAL = bool(enabled)
    try:
        _DEBUG_DURATION = float(duration)
    except (TypeError, ValueError):
        _DEBUG_DURATION = 1.5
    if _DEBUG_DURATION < 0.3:
        _DEBUG_DURATION = 0.3
    elif _DEBUG_DURATION > 5.0:
        _DEBUG_DURATION = 5.0
    return _DEBUG_VISUAL


def clearDebugVisual():
    """Xóa ngay mọi hình debug đang hiển thị."""
    try:
        get_device().debug_mark("clear", ())
    except Exception:
        pass
    return True


def _dbg_rect(x, y, w, h):
    if not _DEBUG_VISUAL:
        return
    try:
        get_device().debug_mark("rect", (x, y, w, h), _DEBUG_DURATION)
    except Exception:
        pass


def _dbg_circle(x, y, r=None):
    if not _DEBUG_VISUAL:
        return
    try:
        get_device().debug_mark("circle", (x, y, r or _DEBUG_TAP_RADIUS),
                                _DEBUG_DURATION)
    except Exception:
        pass


def _dbg_line(x1, y1, x2, y2):
    if not _DEBUG_VISUAL:
        return
    try:
        get_device().debug_mark("line", (x1, y1, x2, y2), _DEBUG_DURATION)
    except Exception:
        pass

# All IOSControl-parity funcs are implemented natively (socket tasks 30-47)
# with local fallbacks where noted. No stubs remain.


def get_device(ip=None):
    """Return the shared device connection (lazy, with retries)."""
    global _DEVICE, _DEVICE_IP
    if ip is not None:
        _DEVICE_IP = str(ip)
    if _DEVICE is None:
        last_err = None
        for _ in range(3):
            try:
                _DEVICE = zxtouch(_DEVICE_IP)
                break
            except Exception as e:  # e.g. daemon not up yet
                last_err = e
                time.sleep(0.5)
        if _DEVICE is None:
            raise RuntimeError("Cannot connect to ZXTouch daemon at %s:6000: %s" % (_DEVICE_IP, last_err))
    return _DEVICE


def set_device(device):
    """Override the shared device (tests / advanced use)."""
    global _DEVICE
    _DEVICE = device
    return device


def disconnect():
    global _DEVICE
    if _DEVICE is not None:
        try:
            _DEVICE.disconnect()
        except Exception:
            pass
        _DEVICE = None


# ---------------------------------------------------------------- Touch

def tap(x, y, finger=1):
    """Tap at coordinates (DOWN + short hold + UP)."""
    _dbg_circle(x, y)
    d = get_device()
    d.touch(TOUCH_DOWN, finger, x, y)
    time.sleep(0.05)
    d.touch(TOUCH_UP, finger, x, y)


def touchDown(fid, x, y):
    get_device().touch(TOUCH_DOWN, fid, x, y)


def touchMove(fid, x, y):
    get_device().touch(TOUCH_MOVE, fid, x, y)


def touchUp(fid, x, y):
    get_device().touch(TOUCH_UP, fid, x, y)


def swipe(x1, y1, x2, y2, duration=0.5):
    """Swipe from point A to B over ``duration`` seconds."""
    _dbg_line(x1, y1, x2, y2)
    d = get_device()
    steps = max(2, int(duration / 0.02))
    d.touch(TOUCH_DOWN, 1, x1, y1)
    for i in range(1, steps + 1):
        t = i / steps
        d.touch(TOUCH_MOVE, 1, x1 + (x2 - x1) * t, y1 + (y2 - y1) * t)
        time.sleep(duration / steps)
    d.touch(TOUCH_UP, 1, x2, y2)


def longPress(x, y, duration=1.0):
    _dbg_circle(x, y)
    d = get_device()
    d.touch(TOUCH_DOWN, 1, x, y)
    time.sleep(duration)
    d.touch(TOUCH_UP, 1, x, y)


def pinch(x, y, scale=0.5, duration=0.5):
    """Pinch gesture. scale<1 zooms in, scale>1 zooms out."""
    d = get_device()
    r0, r1 = 50.0, 50.0 * scale
    _dbg_circle(x - r0, y)
    _dbg_circle(x + r0, y)
    steps = max(2, int(duration / 0.02))
    d.touch_with_list([
        {"type": TOUCH_DOWN, "finger_index": 1, "x": x - r0, "y": y},
        {"type": TOUCH_DOWN, "finger_index": 2, "x": x + r0, "y": y},
    ])
    for i in range(1, steps + 1):
        t = i / steps
        r = r0 + (r1 - r0) * t
        d.touch_with_list([
            {"type": TOUCH_MOVE, "finger_index": 1, "x": x - r, "y": y},
            {"type": TOUCH_MOVE, "finger_index": 2, "x": x + r, "y": y},
        ])
        time.sleep(duration / steps)
    d.touch_with_list([
        {"type": TOUCH_UP, "finger_index": 1, "x": x - r1, "y": y},
        {"type": TOUCH_UP, "finger_index": 2, "x": x + r1, "y": y},
    ])


def rotate(x, y, angle=90.0, duration=0.5):
    """Rotate two fingers around (x, y) by ``angle`` degrees."""
    _dbg_circle(x, y)
    d = get_device()
    r = 50.0
    a1 = math.radians(angle)
    steps = max(2, int(duration / 0.02))
    d.touch_with_list([
        {"type": TOUCH_DOWN, "finger_index": 1, "x": x + r, "y": y},
        {"type": TOUCH_DOWN, "finger_index": 2, "x": x - r, "y": y},
    ])
    for i in range(1, steps + 1):
        t = i / steps
        a, b = a1 * t, math.pi + a1 * t
        d.touch_with_list([
            {"type": TOUCH_MOVE, "finger_index": 1,
             "x": x + r * math.cos(a), "y": y + r * math.sin(a)},
            {"type": TOUCH_MOVE, "finger_index": 2,
             "x": x + r * math.cos(b), "y": y + r * math.sin(b)},
        ])
        time.sleep(duration / steps)
    d.touch_with_list([
        {"type": TOUCH_UP, "finger_index": 1,
         "x": x + r * math.cos(a1), "y": y + r * math.sin(a1)},
        {"type": TOUCH_UP, "finger_index": 2,
         "x": x - r * math.cos(a1), "y": y - r * math.sin(a1)},
    ])


# ---------------------------------------------------------------- Color

def _num(v):
    """int() for device values: daemon formats numbers as '1242.000000'."""
    try:
        return int(float(v))
    except (TypeError, ValueError):
        return int(v)


def _color_to_rgb(color):
    if isinstance(color, int):
        return ((color >> 16) & 0xFF, (color >> 8) & 0xFF, color & 0xFF)
    s = str(color).strip().lstrip("#")
    if s.lower().startswith("0x"):
        s = s[2:]
    if len(s) == 6:
        return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16))
    raise ValueError("Unsupported color format: %r (use 0xRRGGBB)" % (color,))


def _rgb_to_int(r, g, b):
    return (int(r) << 16) | (int(g) << 8) | int(b)


def getColor(x, y):
    """Return pixel color as 0xRRGGBB int."""
    ok, res = get_device().pick_color(x, y)
    if not ok:
        raise RuntimeError("getColor failed: %s" % (res,))
    return _rgb_to_int(_num(res["red"]), _num(res["green"]), _num(res["blue"]))


def getColors(locations):
    """Return list of 0xRRGGBB ints for [(x, y), ...]."""
    return [getColor(x, y) for (x, y) in locations]


def _default_region():
    ok, res = get_device().get_screen_size()
    if not ok:
        raise RuntimeError("get_screen_size failed: %s" % (res,))
    return (0, 0, _num(res["width"]), _num(res["height"]))


def findColor(color, count=1, region=None, tolerance=0):
    """Find pixels matching ``color``. Returns list of (x, y).

    Uses native TASK_COLOR_MULTI when available; falls back to the
    single-point searcher against older daemons.
    """
    if int(count) > 1 or region is not None:
        try:
            ok, res = get_device().find_colors_multi(color, count, region, tolerance)
            if ok:
                return res
        except Exception:
            pass
    r, g, b = _color_to_rgb(color)
    t = int(tolerance)
    if region is None:
        region = _default_region()
    out = []
    for _ in range(max(1, int(count))):
        ok, res = get_device().search_color(
            region, r - t, r + t, g - t, g + t, b - t, b + t)
        if not ok:
            break
        out.append((_num(res["x"]), _num(res["y"])))
        if len(out) >= 1:  # legacy native returns first match; avoid infinite loop
            break
    return out


def findColors(pattern, count=1, region=None, tolerance=10):
    """Multi-color pattern match: [(color, dx, dy), ...].

    Uses native TASK_COLOR_PATTERN when available; falls back to a naive
    anchor+verify loop (slower, one round-trip per check).
    """
    if not pattern:
        return []
    try:
        ok, res = get_device().find_colors_pattern(pattern, tolerance, region)
        if ok:
            return [res]
    except Exception:
        pass
    anchor_color = pattern[0][0]
    for (ax, ay) in findColor(anchor_color, count=1, region=region):
        ok_all = True
        for c, dx, dy in pattern[1:]:
            er, eg, eb = _color_to_rgb(c)
            try:
                got = getColor(ax + dx, ay + dy)
            except Exception:
                ok_all = False
                break
            gr, gg, gb = _color_to_rgb(got)
            if abs(gr - er) > tolerance or abs(gg - eg) > tolerance or abs(gb - eb) > tolerance:
                ok_all = False
                break
        if ok_all:
            return [(ax, ay)]
    return []


def waitForColor(x, y, color, timeout=10.0, interval=0.3, tolerance=0):
    """Poll until pixel matches ``color`` or timeout. Returns bool."""
    want = _color_to_rgb(color)
    end = time.time() + timeout
    while time.time() <= end:
        try:
            got = _color_to_rgb(getColor(x, y))
        except Exception:
            got = None
        if got is not None and all(abs(a - b) <= tolerance for a, b in zip(got, want)):
            return True
        time.sleep(interval)
    return False


# ---------------------------------------------------------------- Image / OCR

def findImage(path, count=1, threshold=0.8, region=None):
    """Find template image. Returns dict {x,y,width,height} or None.

    Uses native TASK_IMAGE_REGION / TASK_IMAGE_MULTI when a region or
    count>1 is requested; falls back to full-screen single match.
    """
    if region is not None:
        try:
            ok, res = get_device().find_image_in_region(path, region, threshold)
            if ok:
                _dbg_rect(_num(res.get("x", 0)), _num(res.get("y", 0)),
                          _num(res.get("width", 0)), _num(res.get("height", 0)))
                return res
        except Exception:
            pass
    if int(count) > 1:
        try:
            ok, res = get_device().image_match_multi(path, threshold, count)
            if ok and res:
                _dbg_rect(_num(res[0].get("x", 0)), _num(res[0].get("y", 0)),
                          _num(res[0].get("width", 0)), _num(res[0].get("height", 0)))
                return res[0]
        except Exception:
            pass
    ok, res = get_device().image_match(path, threshold, 2, 0.8)
    if not ok:
        return None
    _dbg_rect(_num(res.get("x", 0)), _num(res.get("y", 0)),
              _num(res.get("width", 0)), _num(res.get("height", 0)))
    return res


def waitForImage(path, timeout=10.0, threshold=0.8, interval=0.5):
    end = time.time() + timeout
    while time.time() <= end:
        m = findImage(path, threshold=threshold)
        if m:
            return m
        time.sleep(interval)
    return None


def screenshot(name, region=None):
    """Take a screenshot on device. Returns the device-side file path."""
    ok, res = get_device().screenshot(name, region)
    if not ok:
        raise RuntimeError("screenshot failed: %s" % (res,))
    return res


def deleteScreenshot(name):
    """Delete screenshot file (local rm; falls back to device shell)."""
    try:
        os.remove(name)
        return True
    except OSError:
        try:
            ok, _ = get_device().run_shell_command("rm -f '%s'" % name.replace("'", "'\\''"))
            return bool(ok)
        except Exception:
            return False


def convertBase64(path):
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode("ascii")


def ocrText(x, y, w, h):
    """OCR region -> joined text string."""
    ok, items = get_device().ocr((x, y, w, h))
    if not ok:
        raise RuntimeError("ocrText failed: %s" % (items,))
    return "\n".join(i.get("text", "") for i in items)


def findText(text, region=None, case_sensitive=False):
    """OCR full screen (or region) -> list of matches containing ``text``.

    Each match is a dict ``{text, x, y, width, height}`` in device pixels
    (same unit as :func:`tap`). Matches are NOT sorted; use :func:`ocrFind`
    for the Lua-style ``x, y, text`` single result, or :func:`tapText` to
    tap the Nth match (top-bottom, left-right).
    """
    if region is None:
        region = _default_region()
    ok, items = get_device().ocr(region)
    if not ok:
        return []
    needle = str(text) if case_sensitive else str(text).lower()
    out = []
    for i in items:
        hay = str(i.get("text", "")) if case_sensitive else str(i.get("text", "")).lower()
        if needle in hay:
            out.append(i)
    # Debug: vẽ bbox đỏ cho tối đa 10 match để user thấy OCR bắt được chữ nào.
    for m in out[:10]:
        _dbg_rect(_num(m.get("x", 0)), _num(m.get("y", 0)),
                  _num(m.get("width", 0)), _num(m.get("height", 0)))
    return out


def _match_center(m):
    """Center point of an OCR match dict (device pixels, ints)."""
    return (_num(m.get("x", 0)) + _num(m.get("width", 0)) // 2,
            _num(m.get("y", 0)) + _num(m.get("height", 0)) // 2)


def _sorted_matches(matches):
    return sorted(matches,
                  key=lambda i: (_num(i.get("y", 0)), _num(i.get("x", 0))))


class OcrFindResult(tuple):
    """``(x, y, text)`` triple that is falsy when nothing matched.

    Behaves like a plain 3-tuple (unpacking, indexing, slicing) but
    ``bool()`` mirrors Lua's ``nil`` check: ``if ocrFind("OK"):`` is False
    when the text was not found.
    """

    __slots__ = ()

    def __new__(cls, x, y, text):
        return super(OcrFindResult, cls).__new__(cls, (x, y, text))

    def __bool__(self):
        return self[0] is not None

    __nonzero__ = __bool__  # Python 2 style guard (harmless on py3)


def ocrFind(text, region=None, case_sensitive=False):
    """Lua-style single result: ``(x, y, matched_text)`` center in pixels.

    Returns the topmost-leftmost match containing ``text``, or
    ``(None, None, None)`` when nothing matches. This is the unpackable
    equivalent of ``local x, y, text = findText("Login")`` in Lua, and of
    ``x, y, text = ocrFind("Login")`` in Python. The result is falsy when
    nothing matched, so ``if ocrFind("OK"):`` works like Lua's nil check.
    """
    matches = findText(text, region=region, case_sensitive=case_sensitive)
    if not matches:
        return OcrFindResult(None, None, None)
    m = _sorted_matches(matches)[0]
    cx, cy = _match_center(m)
    return OcrFindResult(cx, cy, m.get("text", ""))


def waitForText(text, timeout=10.0, interval=0.5, region=None):
    end = time.time() + timeout
    while time.time() <= end:
        if findText(text, region=region):
            return True
        time.sleep(interval)
    return False


def tapImage(path, timeout=10.0, threshold=0.8, region=None):
    """Wait for image and tap its center. Returns match dict or None."""
    m = waitForImage(path, timeout=timeout, threshold=threshold)
    if not m:
        return None
    tap(_num(m["x"]) + _num(m.get("width", 0)) // 2,
        _num(m["y"]) + _num(m.get("height", 0)) // 2)
    return m


def tapText(text, timeout=10.0, index=1, region=None):
    """Wait for OCR text and tap match ``index`` (1-based, top-bottom).

    ``index`` follows docs/IDE/ioscontrol.md: 1 = first (topmost-leftmost),
    2 = second, ... For backward compatibility ``0`` is also accepted as
    the first match. Returns the tapped match dict, or None on timeout.
    The tapped point is printed so Logs show exactly where the tap landed.
    """
    try:
        idx = int(index)
    except (TypeError, ValueError):
        idx = 1
    if idx <= 0:
        idx = 1  # 0 = first match (legacy Python callers)
    want = idx - 1
    end = time.time() + timeout
    while time.time() <= end:
        matches = findText(text, region=region)
        if len(matches) > want:
            m = _sorted_matches(matches)[want]
            cx, cy = _match_center(m)
            print("tapText: %r -> (%d, %d) [%s]" % (text, cx, cy, m.get("text", "")))
            tap(cx, cy)
            return m
        time.sleep(0.5)
    return None


def swipeUntilImage(path, direction="up", maxSwipes=5, threshold=0.8, speed=0.5):
    """Swipe until image found. Returns match dict or None."""
    dirs = {
        "up": (200, 600, 200, 200),
        "down": (200, 200, 200, 600),
        "left": (600, 400, 200, 400),
        "right": (200, 400, 600, 400),
    }
    x1, y1, x2, y2 = dirs.get(direction, dirs["up"])
    for _ in range(maxSwipes):
        m = findImage(path, threshold=threshold)
        if m:
            return m
        swipe(x1, y1, x2, y2, speed)
        time.sleep(0.5)
    return findImage(path, threshold=threshold)


def swipeUntilText(text, direction="up", maxSwipes=5, speed=0.5):
    dirs = {
        "up": (200, 600, 200, 200),
        "down": (200, 200, 200, 600),
        "left": (600, 400, 200, 400),
        "right": (200, 400, 600, 400),
    }
    x1, y1, x2, y2 = dirs.get(direction, dirs["up"])
    for _ in range(maxSwipes):
        if findText(text):
            return True
        swipe(x1, y1, x2, y2, speed)
        time.sleep(0.5)
    return bool(findText(text))


# ---------------------------------------------------------------- Interaction

def dialogInput(title="Input", message="", default=""):
    """Show input dialog -> entered text (empty string on cancel)."""
    ok, res = get_device().prompt_input(title, message, "", default)
    return res if ok else ""


def dialogChoice(title, *options):
    """Show a choice dialog. Returns the selected option index."""
    ok, res = get_device().dialog_choice(title, list(options))
    if not ok:
        raise RuntimeError("dialogChoice failed/cancelled: %s" % (res,))
    return res


def timestamp():
    """Current unix timestamp in milliseconds."""
    return int(time.time() * 1000)


def md5(s):
    if isinstance(s, str):
        s = s.encode("utf-8")
    return hashlib.md5(s).hexdigest()


def showOverlay(data):
    """Show transparent stats overlay. ``data`` is a dict {key: value}."""
    ok, res = get_device().show_overlay(data)
    if not ok:
        raise RuntimeError("showOverlay failed: %s" % (res,))
    return True


def updateOverlay(key, value):
    ok, res = get_device().update_overlay(key, value)
    if not ok:
        raise RuntimeError("updateOverlay failed: %s" % (res,))
    return True


def hideOverlay():
    ok, res = get_device().hide_overlay()
    if not ok:
        raise RuntimeError("hideOverlay failed: %s" % (res,))
    return True


# ---------------------------------------------------------------- App

def appRun(bundleId):
    ok, res = get_device().switch_to_app(bundleId)
    if not ok:
        raise RuntimeError("appRun failed: %s" % (res,))
    return True


def appKill(bundleId):
    ok, res = get_device().app_kill(bundleId)
    if not ok:
        raise RuntimeError("appKill failed: %s" % (res,))
    return True


def appClear(bundleId):
    """Safe-clear app caches (keeps login). Returns cleared entry count."""
    ok, res = get_device().app_clear(bundleId)
    if not ok:
        raise RuntimeError("appClear failed: %s" % (res,))
    return res


def appState(bundleId):
    """Returns 0 (not running), 1 (running) or 2 (frontmost)."""
    ok, res = get_device().app_state(bundleId)
    if not ok:
        raise RuntimeError("appState failed: %s" % (res,))
    return res


def openURL(url):
    ok, res = get_device().open_url(url)
    if not ok:
        raise RuntimeError("openURL failed: %s" % (res,))
    return True


# ---------------------------------------------------------------- Text & input

def inputText(text):
    ok, res = get_device().insert_text(text)
    if not ok:
        raise RuntimeError("inputText failed: %s" % (res,))
    return True


def keyDown(keyType):
    """Press hardware key down: home|volumeUp|volumeDown|power."""
    get_device().key_press(keyType, "down")


def keyUp(keyType):
    """Release hardware key: home|volumeUp|volumeDown|power."""
    get_device().key_press(keyType, "up")


def getClipboard():
    ok, res = get_device().get_text_from_clipboard()
    return res if ok else ""


def setClipboard(text):
    ok, res = get_device().set_clipboard_text(text)
    if not ok:
        raise RuntimeError("setClipboard failed: %s" % (res,))
    return True


# ---------------------------------------------------------------- UI

def toast(message, delay=2):
    from zxtouch import toasttypes
    ok, res = get_device().show_toast(toasttypes.TOAST_MESSAGE, message, delay)
    if not ok:
        raise RuntimeError("toast failed: %s" % (res,))
    return True


def alert(message, title="ZXTouch", duration=0):
    ok, res = get_device().show_alert_box(title, message, duration)
    if not ok:
        raise RuntimeError("alert failed: %s" % (res,))
    return True


def vibrate():
    get_device().vibrate()


def log(*args):
    """Print to the script output log. Accepts multiple values.

    Example: ``log("10", "20", "30", 50, x, y)`` prints them separated
    by spaces, like Lua's multi-arg ``log``.
    """
    print(*args)
    return True


# ---------------------------------------------------------------- Timing / screen

def sleep(seconds):
    time.sleep(seconds)


def usleep(microseconds):
    try:
        get_device().accurate_usleep(int(microseconds))
    except Exception:
        time.sleep(int(microseconds) / 1000000.0)


def randomSleep(mins, maxs):
    time.sleep(random.uniform(mins, maxs))


def screenSize():
    ok, res = get_device().get_screen_size()
    if not ok:
        raise RuntimeError("screenSize failed: %s" % (res,))
    return {"width": _num(res["width"]), "height": _num(res["height"])}


def deviceInfo():
    ok, res = get_device().get_device_info()
    if not ok:
        raise RuntimeError("deviceInfo failed: %s" % (res,))
    try:
        ok2, bat = get_device().get_battery_info()
        if ok2:
            res = dict(res, battery=bat)
    except Exception:
        pass
    return res


# ---------------------------------------------------------------- HTTP / file / json

def httpGet(url, headers=None, timeout=15):
    try:
        import requests
        r = requests.get(url, headers=headers or {}, timeout=timeout)
        return r.text
    except ImportError:
        import urllib.request
        req = urllib.request.Request(url, headers=headers or {})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.read().decode("utf-8", "replace")


def httpPost(url, body=None, headers=None, timeout=15):
    try:
        import requests
        r = requests.post(url, data=body, headers=headers or {}, timeout=timeout)
        return r.text
    except ImportError:
        import urllib.request
        data = body.encode("utf-8") if isinstance(body, str) else body
        req = urllib.request.Request(url, data=data, headers=headers or {})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.read().decode("utf-8", "replace")


def readFile(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def writeFile(path, content):
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    return True


def appendFile(path, content):
    with open(path, "a", encoding="utf-8") as f:
        f.write(content)
    return True


def jsonDecode(s):
    return json.loads(s)


def jsonEncode(obj):
    return json.dumps(obj)


def randomInt(mins, maxs):
    return random.randint(mins, maxs)


def randomFloat(mins, maxs):
    return random.uniform(mins, maxs)


# ---------------------------------------------------------------- Record

def recordStart():
    ok, res = get_device().start_touch_recording()
    if not ok:
        raise RuntimeError("recordStart failed: %s" % (res,))
    return True


def recordStop():
    ok, res = get_device().stop_touch_recording()
    if not ok:
        raise RuntimeError("recordStop failed: %s" % (res,))
    return True


def recordPlay(events, speed=1.0):
    """Replay event list [{type|action, x, y, finger?, delay?}].

    Prefers native on-device replay (one round-trip); falls back to
    local per-event replay against older daemons.
    """
    try:
        ok, res = get_device().record_play_events(events)
        if ok:
            return res
    except Exception:
        pass
    for ev in events:
        kind = str(ev.get("type", ev.get("action", "tap"))).lower()
        if kind in ("sleep", "delay", "wait"):
            time.sleep(float(ev.get("delay", ev.get("seconds", 0.5))) / speed)
        elif kind in ("tap", "touch"):
            tap(_num(ev["x"]), _num(ev["y"]),
                _num(ev.get("finger", ev.get("finger_index", 1))))
        elif kind == "down":
            touchDown(_num(ev.get("finger", 1)), _num(ev["x"]), _num(ev["y"]))
        elif kind == "move":
            touchMove(_num(ev.get("finger", 1)), _num(ev["x"]), _num(ev["y"]))
        elif kind == "up":
            touchUp(_num(ev.get("finger", 1)), _num(ev["x"]), _num(ev["y"]))
        elif kind == "swipe":
            swipe(_num(ev["x1"]), _num(ev["y1"]), _num(ev["x2"]), _num(ev["y2"]),
                  float(ev.get("duration", 0.5)))
        if "delay" in ev and kind not in ("sleep", "delay", "wait"):
            time.sleep(float(ev["delay"]) / speed)


def recordSave(name, events):
    """Save event table (tries on-device storage, falls back to local file)."""
    try:
        ok, res = get_device().record_save(name, events)
        if ok:
            return True
    except Exception:
        pass
    with open(name, "w", encoding="utf-8") as f:
        json.dump(events, f)
    return True


def recordLoad(name):
    """Load event table (tries on-device storage, falls back to local file)."""
    try:
        ok, res = get_device().record_load(name)
        if ok:
            return res
    except Exception:
        pass
    with open(name, "r", encoding="utf-8") as f:
        return json.load(f)


# ---------------------------------------------------------------- Crane

class _CraneNamespace:
    """Crane container management (requires paid Crane tweak, not Lite).

    Lua-style: ``crane.list("com.foo")`` / ``crane.switch(bid, name)``.
    Mirrors docs/IDE/ioscontrol.md sec-crane. After ``switch``, call
    ``appRun(bundleId)`` to launch into the new container.
    """

    def _call(self, op, **params):
        ok, res = get_device().crane(op, **params)
        if not ok:
            raise RuntimeError("crane.%s failed: %s" % (op, res))
        return res

    # list
    def list(self, bundleId=None):
        """List containers (all apps if bundleId is None)."""
        params = {}
        if bundleId:
            params["bundleId"] = bundleId
        return self._call("list", **params)

    # switch
    def switch(self, bundleId, name):
        """Switch active container (name or id)."""
        return self._call("switch", bundleId=bundleId, name=name)

    def create(self, bundleId, name):
        """Create container. Returns {ok, id}."""
        return self._call("create", bundleId=bundleId, name=name)

    def delete(self, bundleId, name):
        return self._call("delete", bundleId=bundleId, name=name)

    def wipe(self, bundleId, name):
        """Full wipe (data + keychain), skeleton repopulated."""
        return self._call("wipe", bundleId=bundleId, name=name)

    def rename(self, bundleId, old, new):
        return self._call("rename", bundleId=bundleId, old=old, new=new)

    def clearData(self, bundleId, container=None):
        """Clear caches, keep login. Returns {ok, cleared}."""
        params = {"bundleId": bundleId}
        if container:
            params["container"] = container
        return self._call("clearData", **params)

    def backup(self, bundleId, container=None, name=None):
        """Backup as tar.gz. Returns {ok, path} (device-side path)."""
        params = {"bundleId": bundleId}
        if container:
            params["container"] = container
        if name:
            params["name"] = name
        return self._call("backup", **params)

    def restore(self, bundleId, path):
        return self._call("restore", bundleId=bundleId, path=path)

    def size(self, bundleId, container=None):
        """Returns {total, caches, webkit, preferences} in bytes."""
        params = {"bundleId": bundleId}
        if container:
            params["container"] = container
        return self._call("size", **params)

    # snake_case aliases
    clear_data = clearData


crane = _CraneNamespace()


# ---------------------------------------------------------------- Aliases (snake_case)

touch_down = touchDown
touch_move = touchMove
touch_up = touchUp
long_press = longPress
get_color = getColor
get_colors = getColors
find_color = findColor
find_colors = findColors
wait_for_color = waitForColor
find_image = findImage
wait_for_image = waitForImage
delete_screenshot = deleteScreenshot
convert_base64 = convertBase64
ocr_text = ocrText
find_text = findText
ocr_find = ocrFind
wait_for_text = waitForText
tap_image = tapImage
tap_text = tapText
swipe_until_image = swipeUntilImage
swipe_until_text = swipeUntilText
dialog_input = dialogInput
dialog_choice = dialogChoice
show_overlay = showOverlay
update_overlay = updateOverlay
hide_overlay = hideOverlay
app_run = appRun
app_kill = appKill
app_clear = appClear
app_state = appState
open_url = openURL
input_text = inputText
key_down = keyDown
key_up = keyUp
get_clipboard = getClipboard
set_clipboard = setClipboard
random_sleep = randomSleep
screen_size = screenSize
device_info = deviceInfo
http_get = httpGet
http_post = httpPost
read_file = readFile
write_file = writeFile
append_file = appendFile
json_decode = jsonDecode
json_encode = jsonEncode
random_int = randomInt
random_float = randomFloat
record_start = recordStart
record_stop = recordStop
record_play = recordPlay
record_save = recordSave
record_load = recordLoad
set_debug_visual = setDebugVisual
clear_debug_visual = clearDebugVisual


def install(namespace=None):
    """Inject all globals into ``namespace`` (default: caller's globals).

    Used by zxtouch.runner. Returns the injected dict.
    """
    import sys
    if namespace is None:
        namespace = sys._getframe(1).f_globals
    for name in __all__:
        namespace[name] = globals()[name]
    return namespace


__all__ = [
    "get_device", "set_device", "disconnect",
    "setDebugVisual", "clearDebugVisual",
    "tap", "touchDown", "touchMove", "touchUp", "swipe", "longPress",
    "pinch", "rotate",
    "getColor", "getColors", "findColor", "findColors", "waitForColor",
    "findImage", "waitForImage", "screenshot", "deleteScreenshot",
    "convertBase64", "ocrText", "findText", "ocrFind", "waitForText", "tapImage",
    "tapText", "swipeUntilImage", "swipeUntilText",
    "dialogInput", "dialogChoice", "timestamp", "md5",
    "showOverlay", "updateOverlay", "hideOverlay",
    "appRun", "appKill", "appClear", "appState", "openURL",
    "inputText", "keyDown", "keyUp", "getClipboard", "setClipboard",
    "toast", "alert", "vibrate", "log",
    "sleep", "usleep", "randomSleep", "screenSize", "deviceInfo",
    "httpGet", "httpPost",
    "readFile", "writeFile", "appendFile", "jsonDecode", "jsonEncode",
    "randomInt", "randomFloat",
    "recordStart", "recordStop", "recordPlay", "recordSave", "recordLoad",
    "crane",
    # snake_case aliases
    "touch_down", "touch_move", "touch_up", "long_press",
    "get_color", "get_colors", "find_color", "find_colors",
    "wait_for_color", "find_image", "wait_for_image", "delete_screenshot",
    "convert_base64", "ocr_text", "find_text", "ocr_find", "wait_for_text",
    "tap_image", "tap_text", "swipe_until_image", "swipe_until_text",
    "dialog_input", "dialog_choice", "show_overlay", "update_overlay",
    "hide_overlay", "app_run", "app_kill", "app_clear", "app_state",
    "open_url", "input_text", "key_down", "key_up",
    "get_clipboard", "set_clipboard",
    "random_sleep", "screen_size", "device_info",
    "http_get", "http_post", "read_file", "write_file", "append_file",
    "json_decode", "json_encode", "random_int", "random_float",
    "record_start", "record_stop", "record_play", "record_save",
    "record_load", "set_debug_visual", "clear_debug_visual",
]
