#!/usr/bin/env python3
"""Chuan doan findImage treo tren may roothide (chay TRUC TIEP tren iPhone).

Muc dich: thay vi goi findImage() tran (socket recv() block vinh vien khi
daemon cham/chet), script nay goi tung tang daemon rieng le, moi tang co
socket timeout, do elapsed, va KHONG bao gio treo qua `timeout` giay.

Cach dung (tren iPhone, qua SSH):
    python3 diag-findimage-roothide.py /duong/to/template.png [threshold] [timeout_moi_tang]
    Vi du:
    python3 diag-findimage-roothide.py /var/mobile/Library/ZXTouch/scripts/myscript.bdl/btn.png 0.8 30

Doc output:
    - Tang nao in "TIMEOUT" nghia la daemon khong tra loi trong `timeout` giay
      -> dung do la diem ket (xem Phase 3 trong bao cao audit).
    - Tang nao tra loi cham (>10s) nhung co ket qua -> NCC nang, can cap scale/fetch.
    - "Template image not found" ngay lap tuc -> sai duong dan (roothide prefix),
      KHONG phai treo.

Luu y: script tu dat socket timeout (client goc khong co timeout), nen no
khong lam anh huong script khac. Chay xong thi socket tro ve blocking.
"""

import os
import socket
import sys
import time

sys.path.insert(0, "/var/mobile/Library/ZXTouch/coreutils/ScriptRuntime")
# thu them share path neu chua copy vao site-packages
for _p in ("/usr/share/zxtouch/python",):
    if os.path.isdir(_p) and _p not in sys.path:
        sys.path.insert(0, _p)

from zxtouch.client import zxtouch  # noqa: E402
from zxtouch import prelude  # noqa: E402


def timed_call(label, timeout, fn, *args, **kwargs):
    dev = prelude.get_device()
    dev.s.settimeout(timeout)
    t0 = time.time()
    try:
        ok, res = fn(*args, **kwargs)
        dt = time.time() - t0
        print("[%s] ok=%s elapsed=%.2fs -> %r" % (label, ok, dt, res))
        return ok, res, dt
    except socket.timeout:
        dt = time.time() - t0
        print("[%s] TIMEOUT sau %.2fs (daemon khong tra loi - DIEM KET)" % (label, dt))
        return None, None, dt
    except Exception as e:
        dt = time.time() - t0
        print("[%s] EXCEPTION sau %.2fs: %s: %s" % (label, dt, type(e).__name__, e))
        return False, str(e), dt
    finally:
        try:
            dev.s.settimeout(None)
        except Exception:
            pass


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    tpl = sys.argv[1]
    threshold = float(sys.argv[2]) if len(sys.argv) > 2 else 0.8
    timeout = float(sys.argv[3]) if len(sys.argv) > 3 else 30.0

    print("== moi truong ==")
    print("python:", sys.executable if hasattr(sys, "executable") else "?")
    print("template:", tpl, "exists=", os.path.exists(tpl),
          "size=", os.path.getsize(tpl) if os.path.exists(tpl) else "-")
    print("/var/jb exists=", os.path.exists("/var/jb"),
          "| /var/jb/usr/bin/python3=", os.path.exists("/var/jb/usr/bin/python3"))
    print("threshold=", threshold, "timeout_moi_tang=", timeout)

    print("== ket noi daemon :6000 ==")
    dev = prelude.get_device()
    dev.s.settimeout(10)
    try:
        print("ping:", dev.ping())
        print("screen:", dev.get_screen_size(), dev.get_screen_orientation())
    except Exception as e:
        print("KHONG ket noi duoc daemon :6000:", e)
        return 1
    finally:
        dev.s.settimeout(None)

    print("== tang 1: image_match don (TASK_TEMPLATE_MATCH) ==")
    timed_call("single", timeout, dev.image_match, tpl, threshold, 2, 0.8)

    print("== tang 2: region full-screen (TASK_IMAGE_REGION) ==")
    try:
        ok, sz = dev.get_screen_size()
        w, h = int(float(sz["width"])), int(float(sz["height"]))
    except Exception:
        w, h = 0, 0, None
    if w and h:
        timed_call("region", timeout, dev.find_image_in_region,
                   tpl, [0, 0, w, h], threshold)
    else:
        print("[region] bo qua (khong lay duoc kich thuoc man hinh)")

    print("== tang 3: multi-match (TASK_IMAGE_MULTI, max=5) ==")
    timed_call("multi", timeout, dev.image_match_multi, tpl, threshold, 5)

    print("== tang 4: prelude.findImage end-to-end (socket timeout %ds) ==" % int(timeout))
    dev.s.settimeout(timeout)
    t0 = time.time()
    try:
        out = prelude.findImage(tpl, threshold=threshold)
        print("[findImage] elapsed=%.2fs -> %d match: %r" % (time.time() - t0, len(out), out))
    except socket.timeout:
        print("[findImage] TIMEOUT sau %.2fs" % (time.time() - t0))
    except Exception as e:
        print("[findImage] EXCEPTION: %s: %s" % (type(e).__name__, e))
    finally:
        try:
            dev.s.settimeout(None)
        except Exception:
            pass

    print("== xong (neu thay TIMEOUT o tang nao, gui log nay kem template size + doi may/iOS) ==")
    return 0


if __name__ == "__main__":
    sys.exit(main())
