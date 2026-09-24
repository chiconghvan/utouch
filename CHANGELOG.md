# Thay đổi phiên bản

Mẫu thay đổi dạng *Keep a Changelog* cho uTouch / zxtouch, tuân thủ
[Keep a Changelog](https://keepachangelog.com/vi/1.1.0/); số phiên bản theo
[Semantic Versioning](https://semver.org/lang/vi/).

Loại mục: `Đã thêm` (tính năng mới) · `Đã thay đổi` (đổi hành vi sẵn có) ·
`Đã sửa` (khắc phục lỗi) · `Đã loại bỏ` (bỏ hẳn).

## [Unreleased]

## [0.3.52] — 2026-09-24

### Đã thêm
- Chạy `TASK_SETPROXY=53` dưới quyền root qua `sudo zxtouchb`: logic `SCPreferences` tách sang file mới `pccontrol/ZXProxyApply.{h,m}` (chỉ Foundation, forward-declare opaque type nên không cần link framework), `zxtouch-binary` thêm subcommand `-proxy "host;;port"` / `-proxy-clear` in `0` hoặc `-1;;lý do` ra stdout; handler trong tweak (`mobile`) chỉ relay payload qua `sudo -n` + đọc kết quả từ file tạm, giữ nguyên protocol task nên phía Python không đổi. `control` thêm `Depends: sudo`.

### Đã loại bỏ
- Mọi đường plist fallback của proxy trong `prelude.py`: `setProxySystem`/`clearProxySystem` chỉ dùng system API (`_nativeDaemonTask`), helper `_UTIL_HELPER` chỉ còn action `pref-set` (bỏ `proxy-set`/`proxy-clear`/`proxy-svc-set`/`proxy-svc-clear`, hàm `wifi_proxies`, hằng `_UTIL_PROXY_PLIST`); test tương ứng trong `tools/tests/test_prelude.py` chuyển sang `test_proxy_native_only` (fail trả `False`, không gọi shell).

## [0.3.51] — 2026-09-24

### Đã thay đổi
- `TASK_SETPROXY=53` và các action `proxy-svc-set`/`proxy-svc-clear` trong `layout/usr/share/zxtouch/python/zxtouch/prelude.py`: trước đây chỉ tìm Wi-Fi service theo tên `UserDefinedName == "Wi-Fi"` nên có thể bỏ sót service đã đổi tên hoặc dùng tên theo ngôn ngữ hệ thống; nay nhận diện theo `Interface.Hardware == "AirPort"` hoặc `Interface.Type == "IEEE80211"` như `proxyswitcher-ng`, rồi mới fallback sang tên cũ. Chế độ HTTP ghi đồng thời HTTP/HTTPS và xóa toàn bộ khóa `SOCKSEnable`/`SOCKSProxy`/`SOCKSPort` thay vì chỉ tắt SOCKS, tránh cấu hình proxy cũ còn sót; nếu proxy đã khớp chính xác thì bỏ qua vòng `commit + apply` không tạo thay đổi giả.
- Fallback của `setProxySystem(host, port)` trong `prelude.py`: sau khi ghi `proxy-svc-set`, nay kiểm tra `HTTPPort` phải là số nguyên; trước đây một port kiểu chuỗi bị network stack bỏ qua vẫn có thể khiến fallback báo thành công. Đường dùng `SCPreferences` cũng ép kiểu khi so sánh trạng thái để ghi lại cấu hình cũ bằng port chuỗi.

### Đã sửa
- `TASK_SETPROXY=53` trong `pccontrol/ExtTasks.xm`: khai báo đúng kiểu trả về `Boolean` của `SCPreferencesUnlock` thay vì `void`; cấu hình proxy đã đúng hoặc đã rỗng được áp dụng idempotent, còn `proxy-svc-clear` chỉ commit khi dict `Proxies` thực sự còn dữ liệu.
- Tài liệu `setProxySystem` trong `docs/IDE/ioscontrol.md`: cập nhật cách nhận diện Wi-Fi service, thứ tự ưu tiên HTTP/HTTPS, việc loại bỏ khóa SOCKS và kiểm tra kiểu port của đường fallback.

## [0.3.50] — 2026-09-24

### Đã sửa
- Đường fallback `setProxySystem(host, port)` / `clearProxySystem()` trong `layout/usr/share/zxtouch/python/zxtouch/prelude.py`: trước đây gọi action helper `proxy-set`/`proxy-clear` ghi dict `Global` kiểu macOS + bounce `en0` nên iOS lờ đi với traffic Wi-Fi; nay gọi `proxy-svc-set`/`proxy-svc-clear` ghi/xóa `Proxies` của Wi-Fi service trong set hiện tại rồi verify đọc lại, proxy fallback có tác dụng thật.

### Đã thêm
- Hàm `wifi_proxies(data)` + hai action helper `proxy-svc-set`/`proxy-svc-clear` trong `_UTIL_HELPER` (`prelude.py`): tìm Wi-Fi service qua `CurrentSet` → `Sets[...].Network.Service` → `NetworkServices[...].UserDefinedName == "Wi-Fi"`; `proxy-svc-set` ghi `HTTPEnable`/`HTTPProxy`/`HTTPPort`/`HTTPSEnable`/`HTTPSProxy`/`HTTPSPort` (+ `SOCKSEnable=0`, kiểm tra `0 < port < 65536`), `proxy-svc-clear` xóa sạch dict, verify đọc lại (`ZXOK`/`ZXOK cleared`, `fail` khi thiếu set/service hoặc `Proxies` không phải dict).
- Test `tools/tests/test_prelude.py`: `test_helper_proxy_svc_set_and_clear` (set rồi đọc plist kiểm tra đúng service Wi-Fi, service Cellular giữ nguyên, clear, port 0 báo `ZXERR`), `test_helper_proxy_svc_no_wifi_service` (không có Wi-Fi service báo `no Wi-Fi service`); mock fallback chuyển sang `proxy-svc-set`/`proxy-svc-clear`.

### Đã thay đổi
- Tài liệu `docs/IDE/ioscontrol.md` (`setProxySystem`): trước đây ghi fallback là Global plist + bounce `en0`; nay ghi đúng fallback per-service qua root helper + bounce `en0`, kèm troubleshooting (`Could not lock ...` do tweak chạy dưới user `mobile` nên fallback tự chạy, treo `after ~30s` thì chạy `wifiInfo()` để phân biệt kẹt helper với shell daemon treo, máy chỉ có cellular thì trả `False` theo thiết kế vì không có Wi-Fi service).

## [0.3.48] — 2026-09-24

### Đã thêm
- Native task `TASK_SETAIRPLANEMODE=52` (`pccontrol/Task.h`, `ExtTasks.h/.xm`, `Task.xm`): bật/tắt chế độ máy bay qua `RadiosPreferences` (`setAirplaneMode:` + `synchronize`, lookup runtime, đọc lại giá trị để verify thay vì trả `True` khống). Phía Python: `tasktypes.TASK_SETAIRPLANEMODE`, `client.set_airplane_mode_enabled(enabled, delay)`, `prelude.setAirplaneMode` thử native trước rồi fallback plist; helper native dùng chung `_nativeRadioTask`, validate `delay` dùng chung `_coerceDelay`.
- Native task `TASK_SETPROXY=53` (`Task.h`, `ExtTasks.h/.xm`, `Task.xm`, thêm `SystemConfiguration` vào `pccontrol_FRAMEWORKS`): đặt/xóa proxy HTTP/HTTPS của Wi-Fi **service** qua `SCPreferences` (commit + apply để configd nhận ngay, không bounce interface) — cách đúng mà app Settings dùng; code cũ ghi Global plist (kiểu macOS) nên iOS lờ đi với traffic Wi-Fi. Phía Python: `tasktypes.TASK_SETPROXY`, `client.set_proxy(host, port)` / `clear_proxy()`, `prelude.setProxySystem`/`clearProxySystem` thử native trước rồi fallback legacy; helper native tổng quát thành `_nativeDaemonTask`.

### Đã thay đổi
- `setAirplaneMode(enabled, delay)` trong `layout/usr/share/zxtouch/python/zxtouch/prelude.py`: trước đây chỉ đi đường plist (`_toggleRadio` ghi plist + bounce CommCenter); nay thử system API trước (`TASK_SETAIRPLANEMODE` qua `RadiosPreferences`, verify bằng cách đọc lại, `delay` hẹn khôi phục phía daemon và trả về ngay) rồi mới fallback plist khi daemon cũ im lặng hoặc API từ chối.
- `setProxySystem(host, port)` / `clearProxySystem()` trong `prelude.py`: trước đây luôn ghi Global plist + bounce `en0` (iOS lờ đi với traffic Wi-Fi); nay thử `TASK_SETPROXY` trước (ghi proxy vào Wi-Fi service qua `SCPreferences`, commit + apply live, không bounce) rồi mới fallback legacy.
- Gom helper native dùng chung trong `prelude.py`: `_cellularNative` tách thành `_nativeDaemonTask(method, args, timeout)` + `_nativeRadioTask`, validate `delay` dùng chung `_coerceDelay` cho cả `setCellularData`/`setAirplaneMode` — hành vi `setCellularData` giữ nguyên, chỉ hết trùng code.
- Tài liệu `docs/IDE/ioscontrol.md`: thêm ghi chú `delay` không chặn cho `setAirplaneMode` (trả về ngay, hẹn khôi phục nền, native `TASK_SETAIRPLANEMODE` trước + fallback plist) và ghi chú proxy per-service `SCPreferences` live cho `setProxySystem`/`clearProxySystem` (daemon cũ fallback Global plist + bounce `en0`).

## [0.3.47] — 2026-09-24

### Đã thêm
- Native task `TASK_SETCELLULARDATA=51` (`pccontrol/Task.h`, `ExtTasks.h/.xm`, `Task.xm`): bật/tắt dữ liệu di động bằng đúng API hệ thống (`CTCellularDataPlanSetIsEnabled` qua `dlsym`, không phụ thuộc phiên bản iOS lúc build). `delay` được hẹn khôi phục phía daemon (`dispatch_after`) nên vẫn trả lời ngay; thiếu symbol thì báo lỗi để phía Python dùng đường plist cũ. Phía Python: `tasktypes.TASK_SETCELLULARDATA`, `client.set_cellular_data_enabled(enabled, delay)`, `prelude.setCellularData` thử native trước (timeout 10s) rồi mới fallback plist — daemon cũ không biết task 51 thì im lặng, hết timeout là fallback.

### Đã thay đổi
- Log thất bại của `_toggleRadio` (`layout/usr/share/zxtouch/python/zxtouch/prelude.py`) kèm thời gian thực hiện (`after Xs`): trước đây log thất bại không ghi thời gian nên timeout shell ~30s trông giống từ chối tức thì; nay phân biệt được timeout với từ chối nhanh, script vẫn trả `False` và chạy tiếp.
- `setCellularData` kiểm tra `delay` trước khi gọi native: trước đây `delay` sai kiểu/số âm/0 vẫn chuyển xuống daemon; nay log `bad delay ...` và bỏ qua, chỉ chuyển `delay > 0` cho timer khôi phục phía daemon.
- Tài liệu `setCellularData` trong `docs/IDE/ioscontrol.md`: trước đây chỉ nói best-effort plist (ghi plist + bounce CommCenter); nay ghi rõ đường system API trước (`TASK_SETCELLULARDATA`) + fallback plist, kèm cách cô lập lỗi timeout 30s bằng `wifiInfo()` (phân biệt kẹt plist/CommCenter với shell daemon treo, gợi ý xem lỗi `system2` trong Console.app).

## [0.3.46] — 2026-09-24

### Đã thêm
- Bí danh tương thích Lua `true`/`false`/`nil` trong `layout/usr/share/zxtouch/python/zxtouch/prelude.py` (kèm `__all__`): trước đây script chép từ Lua gọi `setCellularData(false, 5)` thì gãy ngay `NameError: name 'false' is not defined` vì Python chỉ có `True`/`False`/`None`; nay chạy được, code mới vẫn nên dùng `True`/`False`/`None`.
- `_toggleRadio` (`setAirplaneMode`, `setCellularData`) nay ghi log mọi kết quả: trước đây đường thành công im lặng, không biết đã ghi hay đã hẹn khôi phục; nay log dòng `...=0/1 written and verified` và `will restore ... in Ns`, thất bại vẫn log lý do và trả `False`.

### Đã thay đổi
- `_shellCapture(cmd, timeout)` ép `timeout` qua socket thiết bị (`dev.set_timeout(timeout)`, khôi phục giá trị cũ sau gọi): trước đây `timeout` chỉ nằm ở chữ ký, lệnh shell kẹt thì treo tới timeout socket mặc định 120s trông như script đứng; nay quá `timeout` thì fail nhanh với `(False, lý do)`.
- `_restoreLater(args, delay)` không bao giờ ném lỗi và chặn tiêm lệnh shell: trước đây `delay` sai kiểu (`"abc"`) hay số âm/0 vẫn đi tiếp, đường dẫn `sys.executable` và tham số chứa `space'"`;|&$()<>'` được nối thẳng vào `sh`; nay delay lỗi thì log `auto-restore: bad delay ...` và bỏ qua, đường dẫn/tham số nguy hiểm thì log `unsafe ...` và bỏ qua, vòng gọi daemon giới hạn 15s rồi khôi phục timeout cũ.
- Tài liệu `docs/IDE/ioscontrol.md` và gợi ý editor (`layout/Applications/zxtouch.app/index.html`, `zxtouch/zxtouch/http/index.html`): trước đây ví dụ chỉ dùng `true`/`false` của Lua khiến người viết Python chép theo là gãy, `delay` không nói rõ có chặn hay không; nay thêm ví dụ Python (`True`/`False`), ghi rõ `delay` trả về ngay và hẹn khôi phục nền, `setCellularData` best-effort (ghi plist + bounce CommCenter, iOS mới có thể bỏ qua nhưng vẫn trả `True`).

### Đã sửa
- Socket kẹt làm "độc" kết nối dùng chung: trước đây `_shellCapture`/`_restoreLater` gặp lỗi socket (ví dụ `socket.timeout`) thì giữ nguyên kết nối, reply muộn của daemon có thể lẫn vào lần gọi sau; nay bắt ngoại lệ, gọi `disconnect()` để lần sau nối mới, đồng thời trả `(False, ...)` / log `not scheduled` thay vì treo hoặc ném.
- `layout/usr/share/zxtouch/python/zxtouch/apispec.py` bỏ sót export `nil`: trước đây `_build_all()` dùng `getattr(prelude, name, None)` + `if obj is None: continue` nên `nil` (vốn là `None`) bị bỏ qua, thiếu spec; nay dùng sentinel `_MISSING` riêng nên mọi tên trong `__all__` đều có spec.

## [0.3.45] — 2026-09-19

### Đã sửa
- Máy roothide: các dịch vụ chạy ngầm (bảng điều khiển, màn hình trực tiếp, nhận diện chữ) có thể không khởi động sau khi cài đặt — nay khâu cài đặt ghi đúng đường dẫn nên cả ba đều chạy, máy từng cài bản lỗi cũng được tự sửa.
- Tìm hình (`findImage`, `waitForImage`, `tapImage`): trước đây máy tìm quá lâu thì script đứng im, không bấm Dừng được; nay mỗi lượt tìm quá 2 phút sẽ tự bỏ qua và nút Dừng luôn dùng được.
- Gỡ hoặc cập nhật bản rootless: trước đây còn sót tiến trình cũ chạy song song bản mới; nay dọn sạch cả ba dịch vụ.

### Đã thêm
- Công cụ `scripts/diag-findimage-roothide.py`: kiểm tra từng bước tìm hình ngay trên máy, bước nào quá lâu sẽ báo rõ thay vì treo.
- Gói rootless gọn hơn: không còn kèm file cài đặt của bản roothide; bản roothide liên kết đủ cả hai đường dẫn Python như bản rootless.

## [0.3.44] — 2026-09-19

### Đã sửa
- CI dựng TrollVNC scheme roothide (`tools/trollvnc/build-and-stage.sh --scheme=roothide` trong `build.yml`) gãy ngay khi bắt đầu với `common.mk: No such file or directory`: script `source vendor/TrollVNC/devkit/roothide.sh` ghi đè `THEOS` sang `$HOME/theos-roothide`/`$GITHUB_WORKSPACE/theos-roothide` vốn không tồn tại (CI chỉ cài Theos fork roothide tại `$THEOS`), trong khi `rootless.sh` còn có fallback về `$GITHUB_WORKSPACE/theos` nên bản rootless vẫn qua. Nay script lưu `_SAVED_THEOS` trước khi source rồi khôi phục `THEOS` và ép `THEOS_PACKAGE_SCHEME="$SCHEME"`, nên cả hai scheme dùng chung bản Theos của CI mà vẫn khác nhau đúng scheme đóng gói.

## [0.3.43] — 2026-09-19

### Đã thêm
- Hỗ trợ đóng gói roothide song song rootless: `tools/trollvnc/build-and-stage.sh` nhận `--scheme=rootless|roothide` (mặc định rootless), CI (`build.yml`) dựng TrollVNC một lần cho mỗi scheme trước `make package` tương ứng thay cho một binary dùng chung như trước; bản roothide đổi nhãn control `Description` thành `(roothide, iOS 15-16)` và kiểm guardrails trong `.deb` (postinst/prerm chứa `jbroot`, prerm nhắc đủ `com.zjx.dashboard`/`com.zjx.trollvnc`/`com.zjx.ocr`).
- Script `layout/DEBIAN/prerm-roothide` mới: trước đây bản roothide không có `prerm` nên nâng cấp/gỡ để bản daemon cũ chạy cạnh bản mới; nay `unload` cả ba plist (`com.zjx.dashboard`, `com.zjx.trollvnc`, `com.zjx.ocr`) qua đường dẫn `jbroot`, rồi `killall`/`killall -9 zxtouch-dashboardd` (SIGTERM để ghi session-close marker trước, SIGKILL dọn bản kẹt).
- Entitlements tường minh cho hai binary theos: `dashboardd/dashboardd.entitlements` và `zxtouch-binary/zxtouchb.entitlements` (bộ `platform-application`, `skip-library-validation`, `no-container`, `no-sandbox`, `storage.AppBundles/AppDataContainers`, riêng `zxtouchb` thêm `get-task-allow`), đấu qua `zxtouch-dashboardd_CODESIGN_FLAGS`/`zxtouchb_CODESIGN_FLAGS` trong Makefile; thay thế `layout/entitlements.plist` chung đã xoá.

### Đã thay đổi
- Tra cứu binary ưu tiên `jbroot()` trước, `/var/jb` chỉ còn là fallback rootless: `ZXCraneManager` trong `pccontrol/CraneBridge.xm` (trước `dlopen` hai đường cố định `/var/jb/usr/lib/libcrane.dylib` → `/usr/lib/libcrane.dylib`) nay `dlopen(jbroot(@"/usr/lib/libcrane.dylib"))` trước rồi mới tới hai đường cũ; `ZXPythonModulePath` trong `pccontrol/ScriptPlayer.xm` sinh wrapper `add_datetime.sh` với `DATE` giải qua `ZXFirstExecutablePath` (`jbroot(/usr/bin/date)`, `jbroot(/bin/date)`, `/var/jb/usr/bin/date`, `/var/jb/bin/date`, `/usr/bin/date`, `/bin/date`) thay cho hằng `/var/jb/usr/bin/date` cố định. `pccontrol/RootlessPath.h` đánh dấu `ROOTLESS_PREFIX` đã lỗi thời cho tra cứu binary (đường `/var/mobile/...` giữ nguyên vì nằm ngoài jbroot).
- `zxtouch/zxtouch/RemoteDashboardServer.m` thêm `ZXJbrootResolve` (import `<roothide.h>` có guard `__has_include`, an toàn khi biên dịch bằng Xcode không có header) và `ZXBundleJbPrefix` (suy prefix từ `[[NSBundle mainBundle] bundlePath]` dạng `$JBROOT/Applications/zxtouch.app` → `$JBROOT`); `ZXJbrootPrefix` thêm hai fast path (dò `jbroot(/Library/LaunchDaemons/com.zjx.trollvnc.plist)` rồi lột 3 cấp, rồi tới bundle prefix) trước nhánh `/var/jb` cũ. Các điểm dùng chuyển sang thứ tự jbroot/bundle trước: `ZXVNCServerBinaryPath` (`trollvncserver`), `ZXVNCLaunchctl` (`bin/launchctl`), `ZXPreludePath` (`usr/share/zxtouch/python/zxtouch/prelude.py`), `dashboardBasePath` (bundle của chính mình → `jbroot(/Applications/zxtouch.app)` → bundle prefix → `/var/jb/Applications/zxtouch.app`), legacy prefs (`jbroot(/var/mobile/Library/Preferences/com.zjx.zxtouch.plist)` trước `/var/jb/...`), và `ZXSettingsKillVNCBestEffort` (`jbroot(/usr/bin/killall)` + bundle prefix trước `/var/jb/usr/bin/killall`).
- Gợi ý editor (`ZXPythonEditorSupport.m`) tìm `prelude.py` qua prefix suy từ bundle (`$JBROOT/usr/share/zxtouch/python/zxtouch/prelude.py`) trước hai đường `/var/jb/...` và `/usr/share/...` như trước, nên target Xcode (không có libroothide) vẫn hoạt động dưới prefix roothide ngẫu nhiên.
- `layout/DEBIAN/postinst-roothide` kill `zxtouch-dashboardd` qua `jbroot /usr/bin/killall` trước, giữ `/usr/bin/killall` làm fallback.

### Đã sửa
- Bản roothide prefix ngẫu nhiên chạy nhầm binary/đường dẫn `/var/jb` cố định (daemon plist, `trollvncserver`, `launchctl`, `killall`, `prelude.py`, app bundle, legacy prefs, `libcrane.dylib`, `date` trong wrapper): nay mọi điểm trên đều giải qua `jbroot()`/bundle prefix trước nên cùng một mã nguồn chạy đúng trên cả rootless (`/var/jb`) lẫn roothide.

## [0.3.42] — 2026-09-18

### Đã sửa
- `findImage(path, count, threshold, region)` khi vừa truyền `region` vừa lấy nhiều kết quả (`count` khác 1 hoặc bỏ `count` để lấy toàn bộ) trong `layout/usr/share/zxtouch/python/zxtouch/prelude.py`: trước đây nhánh có `region` chỉ gọi task region của daemon (luôn trả tối đa 1 hit) rồi bọc thành list, nên `count > 1` trong vùng không bao giờ trả đúng nhiều kết quả, còn đường dự phòng toàn màn hình có thể lọt hit nằm ngoài vùng như thể khớp trong vùng; nay nhánh có `region` đi qua `image_match_multi` toàn màn hình rồi lọc bằng `_match_in_region` mới (giữ hit có tâm nằm trong `{x, y, w, h}`), lấy đủ ngân sách `max(want, 20)` để `want=1` không bị hit tốt nhất ngoài vùng che mất hit trong vùng, hết hit trong vùng thì thử lại một lần bằng `find_image_in_region` (task crop cố gắng hơn), kết quả đơn của task region bị ngoài vùng thì trả `[]`, và daemon cũ không có multi-match thì dự phòng `image_match` đơn nhưng vẫn lọc theo vùng nên không bao giờ trả hit ngoài vùng.

## [0.3.41] — 2026-09-18

### Đã thêm
- Thanh phím phụ dưới trình sửa code trên máy: trước đây gõ các ký tự như ngoặc, hai chấm, Tab hay phím mũi tên phải chuyển bàn phím nhiều lần; nay có sẵn một hàng phím ngay dưới khung soạn thảo để bấm là chèn, kèm các phím di chuyển, xóa dòng, ghi chú. Vào Cài đặt > Extra Keys để bật/tắt từng phím, kéo để đổi thứ tự, bấm Reset để về mặc định.

## [0.3.40] — 2026-09-18

### Đã thêm
- Tham số `region` cho `waitForImage(path, timeout, threshold, interval, region)`, `swipeUntilImage(path, direction, maxSwipes, threshold, speed, region)` và `swipeUntilText(text, direction, maxSwipes, speed, lang, region)` trong `layout/usr/share/zxtouch/python/zxtouch/prelude.py`: khi truyền `{x, y, w, h}` (list/tuple hoặc dict như `findImage`) chỉ quét đúng hình chữ nhật đó, không bao giờ quét toàn màn hình. Trước đây ba hàm này không nhận `region` nên muốn giới hạn vùng tìm phải tự lặp `findImage(..., region)` bằng tay.

### Đã sửa
- `findImage(path, count, threshold, region)` với `region` tường minh mà daemon báo không khớp trong vùng: trước đây rơi xuống tìm toàn màn hình nên có thể trả hit nằm ngoài vùng (ví dụ `y=60` cho vùng `y=2058..2208`) như thể khớp trong vùng; nay trả `[]` ngay. Kết quả region cũng tôn trọng `count` (`[res][:want]`) và giữ nguyên toạ độ daemon trả về vì đã ở không gian toàn màn hình (daemon đã bù gốc vùng), không bù trừ lần nữa.
- Chuẩn hoá `region` qua `_normalize_region` mới trong `layout/usr/share/zxtouch/python/zxtouch/client.py` và `layout/usr/share/zxtouch/python/zxtouch/prelude.py`: dict `{x, y, w, h}` (hoặc `width`/`height`) được bóc thành giá trị số tường minh — trước đây `tuple(dict)`/`",".join(map(str, dict))` gửi nhầm tên khoá `x,y,w,h` xuống socket thành hình chữ nhật sai; list/tuple khác 4 phần tử hoặc kiểu khác (kể cả `set` `{0, 2058, 1242, 150}` trong Python viết tay, thứ tự lặp không xác định) nay ném `ValueError` thay vì tìm nhầm vùng. Áp dụng cho `ocr`, `screenshot`, `find_image_in_region`, `find_colors_multi`, `color_pattern` (client) và `findColor`, `findColors`, `findImage`, `screenshot`, `findText` (prelude).

## [0.3.39] — 2026-09-18

### Đã thêm
- Chạy script tại chỗ, không chuyển app trước: task socket mới `TASK_PLAY_SCRIPT_IN_PLACE = 50` (`pccontrol/Task.h`, `layout/usr/share/zxtouch/python/zxtouch/tasktypes.py`), API Python `zxtouch.play_script_in_place(script_absolute_path)` trong `layout/usr/share/zxtouch/python/zxtouch/client.py`, và cặp hàm `playScriptInPlace` / `playScriptWithSettingsInPlace` trong `pccontrol/Play.h` / `pccontrol/Play.xm` (luôn `setSwitchApp:NO`, bỏ qua cờ `switch_app_before_run_script`). Handler `TASK_PLAY_SCRIPT_IN_PLACE` trong `pccontrol/Task.xm` chạy ngay trên màn hình đang hiển thị. Dashboard (`POST /api/run`, `POST /api/editor/run` trong `zxtouch/zxtouch/RemoteDashboardServer.m`) gửi `"50"+bundlePath` thay cho `"19"+bundlePath`; nút Run của floating panel (`pccontrol/Popup.xm`) và trigger phím cứng (`runConfiguredTriggerAction` trong `pccontrol/Tweak.xm`) gọi bản in-place. Trước đây mọi đường này đi qua `playScript`/`playScriptWithSettings` nên giật về app ghi trong `FrontApp`; từ nay không còn kéo người dùng khỏi màn hình hiện tại.
- Dashboard tự chuyển cổng dự phòng `8688 <-> 8689`: `RemoteDashboardServer.m` mở CORS `Access-Control-Allow-Origin: *` cho JSON (`jsonResponse`), ảnh chụp (`/api/capture-screen`), file (`/api/download`, `/api/logs/download`, assets) và thêm handler `OPTIONS /api/*` trả `204` cho preflight; `GET /api/health` trả thêm `daemonPort`/`fallbackPort`. Web (`layout/Applications/zxtouch.app/index.html`, `zxtouch/zxtouch/http/index.html`) thêm `fetchDashboard` (timeout 10 giây, chỉ failover khi lỗi mạng như `failed to fetch`/`TypeError`, lỗi HTTP 4xx/5xx không chuyển cổng), `downloadViaDashboard`, `DASHBOARD_PEER_PORT`/`dashboardPeerBase` và toast khi chuyển/về cổng chính. Trước đây fetch thẳng cổng hiện tại nên daemon crash/restart là dashboard chết cứng; nay tự thử một lần sang cổng còn lại.

### Đã thay đổi
- `ScriptPlayer` (`playFromRawFile:foregroundApp:err:`, `playFromPythonFile:...` trong `pccontrol/ScriptPlayer.xm`) chỉ `bringAppForeground` khi `ZXShouldSwitchToApp(foregroundApp)` cho phép: bỏ qua chuỗi rỗng, `com.apple.springboard` và mọi bundle-id chứa `zxtouch`. Trước đây `switchAppBeforePlaying=YES` là kéo về ZXTouch/SpringBoard khi `FrontApp` ghi stale; nay các trường hợp đó giữ nguyên màn hình hiện tại.
- Tắt log debug khi chạm: `layout/usr/share/zxtouch/python/zxtouch/client.py` (`touch()`) bỏ `print("[touch-wire] send ...")`, `layout/usr/share/zxtouch/python/zxtouch/prelude.py` (`tapText()`) bỏ `print("tapText: ...")` và đổi mặc định `_DEBUG_TOUCH_LOG` từ `True` thành `False` (`setDebugTouchLog(True)` vẫn bật lại được). Trước đây mỗi lần chạm in một dòng ra console; nay console sạch, chỉ log khi bật debug tường minh.

## [0.3.38] — 2026-09-17

### Đã thay đổi
- `findImage(path, count, threshold, region)` trong `layout/usr/share/zxtouch/python/zxtouch/prelude.py` trả mỗi kết quả dạng `{x, y, width, height, confidence}` thay cho `{..., threshold}` trước đây (`threshold` cũ chỉ lặp lại ngưỡng đã yêu cầu vì daemon chỉ trả hình học). Nay daemon (`pccontrol/TemplateMatch.xm` qua `lastScore`, `pccontrol/ScreenMatch.xm` qua `screenMatchFromRawDataWithScore`, `pccontrol/Task.xm` cho `TASK_IMAGE_MATCH`, `pccontrol/ExtTasks.xm` cho image-region/multi) gắn thêm điểm NCC (0–1, càng cao càng khớp) ở cuối reply một cách cộng thêm để client cũ vẫn đọc được 4 trường đầu; `layout/usr/share/zxtouch/python/zxtouch/client.py` (`_optional_confidence`) tách điểm này thành `float`, thiếu/không parse được thì `None` để tương thích daemon cũ. `findImage` chuẩn hoá qua `_with_confidence` rồi sắp xếp tốt-nhất-trước qua `_sort_by_confidence` (hit không điểm giữ thứ tự cũ ở cuối danh sách), nên `matches[1].confidence`, `zxUnpackMatch` và `tapImage` đều lấy đúng hit tốt nhất. Tài liệu `docs/IDE/ioscontrol.md` và gợi ý dashboard (`layout/Applications/zxtouch.app/index.html`, `zxtouch/zxtouch/http/index.html`) đổi `threshold` thành `confidence` kèm ghi chú sắp xếp.
- Tắt dashboard không còn kéo theo tắt VNC: `ZXRemoteDashboardSetEnabled(NO)`, đường SpringBoard và vòng lặp daemon trong `zxtouch/zxtouch/RemoteDashboardServer.m` giờ chỉ dừng HTTP `:8688`, để nguyên `:5901`. Trước đây cạnh ON→OFF ép `vnc_server_enabled=NO` (park lựa chọn thật) rồi kill `trollvncserver`, còn cạnh OFF→ON mới khôi phục — tắt dashboard để xem là mất luôn VNC cho tới lần bật sau. Từ nay hai công tắc độc lập; lần bật dashboard vẫn chạy migration `ZXVNCRestoreParkedIn` một lần để trả lại lựa chọn đã bị park ở bản cũ.

### Đã sửa
- Spawn `trollvncserver` hết lỗi `EPERM (1)`: `ZXVNCStartServerDirectly` trong `zxtouch/zxtouch/RemoteDashboardServer.m` chỉ đặt cờ `POSIX_SPAWN_SETSIGMASK`, bỏ `POSIX_SPAWN_SETPGROUP`/`POSIX_SPAWN_SETSID` vốn đòi quyền mà daemon mobile không có. Tiến trình con kế thừa process group của cha là đủ vì `SIGCHLD` đã bị bỏ qua nên không sinh zombie.

## [0.3.37] — 2026-09-17

### Đã thay đổi
- `findImage(path, count, threshold, region)` trong `layout/usr/share/zxtouch/python/zxtouch/prelude.py` luôn trả về danh sách các kết quả thay vì một dict đơn/`None`: mỗi kết quả là `{x, y, width, height, threshold}` (`threshold` phản ánh đúng ngưỡng đã yêu cầu, vì daemon chỉ trả hình học qua `TASK_IMAGE_MULTI`/`TASK_TEMPLATE_MATCH`). Không truyền `count` trả toàn bộ kết quả (tối đa `_FIND_IMAGE_DEFAULT_MAX = 20`) nên `len(...)` đếm được số vị trí khớp trên màn hình; truyền `count` giới hạn tối đa `count` kết quả ngay ở phía daemon; không khớp trả `[]`. Trước đây mặc định `count=1`, chỉ trả một dict/`None`, và multi-match bị rút gọn im lặng về kết quả đầu. `waitForImage`/`swipeUntilImage` giờ lấy phần tử đầu của danh sách (`matches[0]`, `None` khi rỗng), `zxUnpackMatch` hiểu match dạng dict để `tapImage` vẫn tap đúng tâm. Kiểu trả về trong `apispec.py`, dashboard web (`layout/Applications/zxtouch.app/index.html`, `zxtouch/zxtouch/http/index.html`) và gợi ý editor (`ZXPythonEditorSupport.m`) đổi từ `object | null` sang `object[]`; tài liệu `docs/IDE/ioscontrol.md` cập nhật chữ ký, ví dụ Lua và mặc định `count` (toàn bộ thay vì 1).

### Đã sửa
- VNC không dựng lại được trên rootless/roothide vì mọi lệnh khôi phục đi qua `system()` — vốn luôn exec `/bin/sh`, thứ không tồn tại trên rootless (chỉ có `/var/jb/bin/sh`) nên luôn trả `127<<8 = 32512` mà không để lại log. Nay `zxtouch/zxtouch/RemoteDashboardServer.m` spawn không qua shell bằng `posix_spawn` với đường dẫn tuyệt đối (không shell, không PATH, không `nohup`): `launchctl` qua `ZXVNCLaunchctl`/`ZXSpawnAndWait`, binary `trollvncserver` qua `ZXVNCServerBinaryPath()` (đọc `ProgramArguments[0]` từ plist đã cài, stdout/stderr append vào `trollvnc.log`), và kill VNC trong Settings qua `sysctl` + `kill()` trực tiếp (fallback spawn `killall` tuyệt đối) thay cho `system("killall ...")`. Kèm dò tiền tố jbroot sống trên roothide qua `ZXJbrootPrefix()` (`/var/jb` → `realpath` → helper `jbroot`) cho cả đường plist lẫn binary/`launchctl`, nên bản roothide không còn trỏ nhầm `/var/jb` cố định.

## [0.3.36] — 2026-09-17

### Đã thay đổi
- Hai host dashboard tách sang hai cổng: daemon `zxtouch-dashboardd` giữ `:8688`, server fallback trong SpringBoard chuyển sang `:8689`. Trước đây cả hai cùng nhắm `:8688` nên bên thua bind thất bại `Address already in use` mỗi 30 giây suốt nhiều giờ trong `dashboardd.log` và ở lại vòng lặp chết, trong khi API lại do bên thắng phục vụ. Cổng được chọn lúc biên dịch (`-DZX_DASHBOARD_DAEMON=1` cho tool; tweak SpringBoard dùng cổng fallback) và URL trong Settings tự dò cổng nào đang thật sự lắng nghe, nên fallback vẫn dùng được khi daemon chết.

### Đã sửa
- Tắt dashboard rồi bật lại làm VNC tắt hẳn: đường OFF ép `vnc_server_enabled=NO` và kill `trollvncserver`, nhưng đường ON chỉ áp lại giá trị đã bị ép, nên VNC nằm nguyên trạng thái tắt cho tới khi người dùng mở Settings gạt lại công tắc (dashboard chỉ hiện "VNC Server is disabled in Settings"). Nay lựa chọn thật của người dùng được park vào `vnc_server_enabled_parked` ngay tại cạnh ON→OFF trong cùng một lần ghi plist và được khôi phục ở cả ba nơi khi dashboard bật lại (Settings, SpringBoard, vòng lặp daemon); gạt công tắc VNC bằng tay thì xoá giá trị park.
- VNC không dựng lại được sau khi server nhận TERM giữa lúc đang tắt: `ZXVNCStartServerDirectly` coi "đang chạy" là "có tiến trình tên `trollvncserver`", nên khi tiến trình cũ còn tên nhưng đã đóng hết listener (dòng cuối `trollvnc.log` là `listenerRun: error in select: Bad file descriptor`) thì mọi lần recover lẫn vòng quét 30 giây của daemon đều thoát im lặng — `POST /api/vnc/recover` trả 503 kèm `started:true` mà không có tiến trình mới nào được exec. Nay điều kiện là cổng `:5901` có trả lời; tiến trình còn sống mà cổng đóng bị SIGKILL trước khi spawn, và nhánh OFF ghi log khi có tiến trình sống sót qua cả SIGKILL.
- Lệnh spawn TrollVNC im lặng khi thất bại: `nohup` cùng các lời gọi `launchctl` trần không có trong PATH của daemon do launchd khởi động, còn lỗi của shell thì không được chuyển đi đâu. Nay lệnh tự đặt `PATH` gồm các thư mục rootless và cả nhóm lệnh được chuyển vào `trollvnc.log`, kèm log mã trả về của `system()`; `kill()` bị từ chối (EPERM) cũng được ghi kèm `errno` thay vì bỏ qua.
- `Disabled` của LaunchDaemon TrollVNC không bao giờ được ghi: đường cũ dựa vào `plutil`, thứ không có trên bản cài rootless, nên việc tắt VNC trông như đã áp dụng trong khi job vẫn loadable. Nay plist được sửa ngay trong tiến trình bằng `NSPropertyListSerialization` và ghi log khi không ghi được (file thuộc root).
- Chạy code từ tab Editor của dashboard làm `findImage("home-activ.png")` trả `None` dù ảnh có trong script: tab Editor dàn code vào bundle tạm `__editor__.bdl` chỉ chứa `info.plist` và `entry.py`, nên tên trần tới daemon không trỏ vào thư mục asset nào và template không load được — ngay cả `threshold=0.1` (vốn trả vị trí tốt nhất khi template load được) cũng vẫn `None`. Nay bundle tạm ghi lại bundle thư viện mà tab được mở từ đó vào `AssetDir` trong `info.plist`, `POST /api/editor/run` nhận `path` qua `bundlePathForRelativePath:`; `ScriptPlayer` đọc `AssetDir` đặt làm thư mục làm việc và xuất `ZX_ASSET_DIR`, `zxtouch.runner` ưu tiên `ZX_ASSET_DIR` khi là thư mục tồn tại, còn `prelude.setAssetDir(directory)` thành khái niệm chung (đường dẫn tương đối giải trong đó, kể cả thư mục con như `img/btn.png`) và `setScriptDir(path)` giữ vai trò tiện ích cho trường hợp asset nằm cạnh file entry. Tài liệu `docs/IDE/ioscontrol.md` nêu quy tắc thư mục asset cho mọi tham số `path` của `findImage`/`waitForImage`/`tapImage`/`swipeUntilImage`.

## [0.3.35] — 2026-09-16

### Đã thêm
- Skill `utool-deploy` (`.commandcode/skills/utool-deploy/SKILL.md`) ghi lại trọn quy trình phát hành của repo: đọc commit kể từ tag gần nhất, viết mục CHANGELOG tiếng Việt kèm link so sánh, bump version ở đủ 9 nguồn khai báo, commit `Release vX.Y.Z`, push `main`, tạo annotated tag rồi để CI dựng `.deb` và publish GitHub Release lẫn APT repo. Skill nằm trong Git để cả repo dùng chung thay vì chỉ ở máy một người.

### Đã sửa
- `findImage` báo `None` cho template đang nằm rõ trên màn hình: tầng quét thô chạy trên mặt phẳng tương quan độ phân giải gốc với bước nhảy `min(tw,th)/8` (8-20 px) và chỉ chấm điểm lại ứng viên khi điểm thô đã vượt ngưỡng, trong khi template nhiều chi tiết chỉ đạt sát ngưỡng trong khoảng hai pixel — bước nhảy vì thế đi thẳng qua đúng vị trí khớp và lượt chấm điểm tinh không bao giờ chạy. Đo trên ảnh chụp 1242x2208: 11 trong 13 template có mặt đúng từng pixel (NCC 1.00) bị báo `None` với điểm 0.47-0.76. Nay tầng thô quét trên ảnh và template đã hạ mẫu (`F = 1..4`, đỉnh đủ rộng để bắt được) và giữ 4 ứng viên khác nhau, mọi ứng viên được chấm điểm lại ở bước 1 vô điều kiện trước khi áp ngưỡng; phép quét theo bước nhảy vẫn là phương án dự phòng khi không dựng được mức thô nào (template quá nhỏ, cấp phát lỗi). `patchNorm` được so với chính biên độ của patch (`1e-6 * patchSqSum`) thay vì hằng số tuyệt đối `1e-6`, nên vá phẳng không còn khuếch đại điểm số vượt 1.0 và kết thúc sớm vòng tìm kiếm; điểm khớp được kẹp trong `[-1, 1]`. Kiểm trên toàn bộ bộ dữ liệu test: 11/11 template trên màn hình khớp đúng pixel (điểm 1.00, lệch 0 px), hai template không có vẫn trả kết quả rỗng, các ca xoay/lật/nhiễu không phát sinh dương tính giả.
- Tài liệu `docs/IDE/ioscontrol.md` khớp lại với code: `findImage` và `swipeUntilImage` mặc định ngưỡng `0.8` (không phải `0.9`), và `swipeUntilImage` mặc định 5 lần vuốt (không phải 10).
- Popup preview ảnh trong pane `Assets` chườm lên tên file đang rê chuột: hộp preview được đo ngay sau khi thẻ `<img>` vừa tạo nên kích thước còn 0 và phép tính vị trí chạy trên hình chữ nhật 14x14; khi bitmap về, hộp phình ra đúng kích thước thật rồi đè lên hàng asset cùng con trỏ chuột (ở pane bên phải còn vượt mép khung nhìn). Nay preview chỉ được đặt vị trí sau khi ảnh load xong và chọn trong bốn phía của hàng asset, nên hộp luôn né tên file đang hover khi khung nhìn còn chỗ. Áp dụng cho cả index.html trên dashboard lẫn bản mirror trong app.

## [0.3.34] — 2026-09-16

### Đã thêm
- Pane `Assets` trong tab Editor, nằm sát phải Monaco và dùng chung chiều cao với editor: liệt kê đệ quy mọi file trong thư mục `.bdl` của script đang mở (kể cả file trong thư mục con như `img/btn.png`). Kéo-thả một asset vào vùng code để chèn đường dẫn tương đối ngay tại vị trí thả, hoặc bấm để chèn tại con trỏ; rê chuột lên asset là ảnh sẽ hiện popup preview. Thêm hai endpoint `GET /api/scripts/assets` (liệt kê file trong bundle, kèm cờ `image`) và `GET /api/scripts/asset` (trả bytes của một asset để hiển thị preview). Cách xử lý thả file sẵn có của Monaco được tắt nên asset chỉ được chèn một lần, qua `executeEdits` ngay tại con trỏ chuột; cả hai endpoint đều đi qua `bundlePathForRelativePath` và kiểm lại tên asset nên không thể thoát ra ngoài thư mục bundle.
- Card `Log Files` trong tab `Device` của dashboard: mỗi log một nút tải về qua `GET /api/logs/download?name=dashboardd|trollvnc|debug` (tải kèm tên file, dạng attachment). Tên log được đối chiếu với danh sách trắng rồi mới ghép vào đường dẫn cố định, nên dữ liệu client gửi lên không đi thẳng vào hệ thống file; log chưa có trả về JSON thay vì file, và client tải bằng blob nên 404 hiện toast chứ không thay cả trang bằng nội dung lỗi.

### Đã thay đổi
- Tab `Assets` cho chọn nhiều file trong một lần: `POST /api/assets` gom toàn bộ part `asset` của body multipart thay vì chỉ part đầu, nên cả lượt chọn được gửi trong một request và phản hồi trả danh sách tên đã lưu ở khoá `files`. Cả lô được kiểm tra trước khi ghi (tên file an toàn, tối đa 25 MB mỗi file) nên một file bị từ chối không để phần còn lại rơi vào trạng thái nửa vời; dropzone hiện số file đã chọn kèm tối đa ba tên, hộp xác nhận và toast đổi theo số lượng file.

### Đã sửa
- `findImage` không tìm được ảnh template nằm cạnh script: daemon mở đường dẫn đúng như client gửi, tính theo thư mục làm việc của chính nó (thư mục của SpringBoard), nên tên trần như `findImage("home-activ.png")` không bao giờ tới được ảnh đi kèm script. `zxtouch.runner` giờ báo thư mục của file script đang chạy qua `prelude.setScriptDir()`, và `findImage()` đổi tên trần thành đường dẫn tuyệt đối khi file đó thật sự tồn tại trong thư mục script — áp dụng cho mọi hàm đi qua `findImage`: `waitForImage`, `tapImage` và `swipeUntilImage`. Đường dẫn tuyệt đối, tên không có trong thư mục script, và lần gọi ngoài lúc chạy script (không có thư mục nào được báo) đều giữ nguyên hành vi cũ. Tài liệu `docs/IDE/ioscontrol.md` cập nhật theo cách tra đường dẫn mới.

## [0.3.33] — 2026-09-16

### Đã thay đổi
- Cổng HTTP của dashboard đổi từ `:8080` sang `:8688`. Cả daemon `zxtouch-dashboardd`, server fallback trong SpringBoard, URL hiện trong Settings lẫn giá trị mặc định trên giao diện web đều lấy từ một hằng số duy nhất `ZXDashboardPort`, nên không còn tình trạng lệch cổng. Địa chỉ mới: `http://<iphone-ip>:8688/`.
- `KeepAlive` của `com.zjx.dashboard` đổi từ `true` sang `SuccessfulExit=false`: daemon tự thoát khi đã có bản khác giữ khoá sẽ không bị launchd dựng lại mỗi 30 giây, nhưng crash (tín hiệu/thoát khác 0) vẫn được restart như cũ.
- Vòng lặp retry của daemon chỉ ghi log tại thời điểm trạng thái cổng đổi (`unavailable` một lần khi mất, `available` một lần khi trở lại) thay vì in lại cùng một dòng mỗi 30 giây.

### Đã sửa
- Daemon dashboard chạy trùng: trước đây một instance sống sót ngoài launchd (khởi động lại qua respring, hoặc job load thất bại rồi được chạy tay) vẫn nằm mãi trong `for (;;)`, mỗi 30 giây lại bind thất bại và ghi `Address already in use` — log ghi nhận liên tục suốt 8 giờ với hai PID cùng lúc, và cả hai cùng điều khiển VNC. Nay `zxtouch-dashboardd` giữ khoá `flock()` trên `/var/mobile/Library/ZXTouch/dashboardd.lock` và thoát ngay nếu đã có instance khác; `postinst`/`postinst-roothide` `killall` bản cũ trước khi `launchctl load`, và thêm `prerm` dừng daemon khi nâng cấp/gỡ.
- Log 500 `"(invalid request)"` sai trên server đang giữ cổng: nguyên nhân là `ZXVNCProbePort()` mở TCP connect rồi `close()` mà không gửi HTTP, khiến GCDWebServer đọc được EOF trước khi có header và ghi 500. Cổng dashboard giờ được kiểm tra bằng `bind()` (`ZXDashboardPortIsTaken`), không tạo kết nối nên không đụng tới server đang chạy; ở đường start thì đọc thẳng `NSPOSIXErrorDomain`/`EADDRINUSE` từ lỗi bind. Cũng nhờ vậy watchdog 3 giây không còn sinh log 500 mỗi lần dò cổng.
- VNC không tự khởi động lại sau khi server đã thoát: `ZXVNCStartServerDirectly` chỉ spawn `trollvncserver` khi `ps -ax | grep -q '[t]rollvncserver'` không khớp, nhưng chính chuỗi lệnh lại mang đường dẫn binary không có ngoặc nên grep khớp luôn tiến trình `sh -c` đang chạy nó, và bản `nohup` vì thế không bao giờ được chạy. Khi launchctl không load nổi job bằng `mobile`, không còn cách nào dựng lại `:5901` sau khi server thoát — recover chỉ chờ hết 8 giây rồi báo `Unable to start VNC server.` trong lúc cổng vẫn đóng. Nay kiểm bằng `ZXVNCServerProcessRunning()` (so khớp `p_comm`) ngay trong C, không thể khớp nhầm shell đang chạy lệnh spawn.
- TrollVNC không còn bắn banner hệ thống mỗi lần client VNC kết nối/ngắt kết nối: truyền `-I off` ở cả hai đường khởi chạy server để `trollvncserver` không gọi `UNUserNotification` (`popBanner`) nữa.
- Upload asset trên dashboard báo `parameter 1 is not of type 'HTMLFormElement'`: `uploadAsset()` là hàm async nên phải chờ hộp thoại xác nhận trước khi dựng body, và `event.currentTarget` đã là `null` khi `new FormData()` chạy. Nay dùng tham chiếu `elements.assetForm` đã lưu thay vì `event.currentTarget`.

## [0.3.32] — 2026-09-16

### Đã thêm
- Log debug cho server dashboard `:8080` tại `/var/mobile/Library/ZXTouch/dashboard-debug.log` (cạnh `ocrd.log`): ghi mỗi lần cổng `:8080` mất kết nối (watchdog 3 giây), mỗi lần một client ngắt kết nối, lỗi bind/accept/socket của GCDWebServer, và backtrace khi crash (signal + uncaught exception). Áp dụng cho cả daemon `zxtouch-dashboardd` lẫn server fallback nhúng trong SpringBoard — nơi launchd không redirect stdout nên trước đây không để lại dấu vết nào. Kèm snapshot phần cứng lúc crash (CPU, RSS/vsize, số thread, RAM trống, thermal, low power) và cảnh báo khi phiên trước kết thúc không sạch.
- Endpoint `GET /api/debug-log` và `POST /api/debug-log/clear` để xem/xoá log debug ngay trên dashboard.

### Đã sửa
- Popup gợi ý autocomplete của editor native tự ẩn khi chạm ra ngoài: trước đây bảng gợi ý chỉ ẩn khi nội dung văn bản thay đổi nên trên iPhone nó vẫn nằm trên màn hình sau khi chạm chỗ khác. Cử chỉ chạm gắn ở view gốc của editor và bỏ qua cú chạm rơi vào chính bảng gợi ý, nên chọn một item trong bảng vẫn hoạt động bình thường.

### Đã loại bỏ
- Nút `Format` trong editor native (bỏ hẳn cùng ivar `formatButton` và method `formatFile`): editor đã tự thụt lề khi gõ `:` hoặc xuống dòng trong ngoặc và tự định dạng văn bản dán vào, nên thao tác định dạng toàn file trùng với những gì việc gõ và `Check` vẫn làm.

## [0.3.31] — 2026-09-16

### Đã thêm
- Ô tìm nhanh trong bảng `Functions` của dashboard (Monaco): nằm cùng hàng, bên phải tiêu đề panel; lọc theo tên hàm, tên hàm không kèm tham số và tên nhóm, không phân biệt hoa thường; hiện `No functions match "…"` khi không có kết quả; `Esc` xoá nhanh từ khoá.
- Tooltip trong bảng `Functions` có thêm một dòng mô tả ngắn cho từng hàm (lấy từ `docs/IDE/ioscontrol.md`), trước đây chỉ có chữ ký và kiểu trả về. Mô tả do daemon gửi vẫn được ưu tiên nếu có.
- Nhóm `Crane` có chữ ký đầy đủ kiểu tham số cho cả 10 hàm, ví dụ `crane.list(bundleId: string = None)` và `crane.backup(bundleId: string, container: string = None, name: string = None)`, thay vì hiện nguyên mẫu gọi mẫu `crane.list("com.facebook.Facebook")`.

### Đã sửa
- Danh mục hàm nạp từ daemon không còn bỏ qua tên có namespace: guard chỉ nhận `^[A-Za-z_]\w*$` nên mọi mục dạng `namespace.method` (như `crane.*`) đều bị loại bỏ, và vì thế nhóm `Crane` không có chữ ký lẫn mô tả.

### Đã thay đổi
- Toast của `toast(message, delay)` bám theo theme hệ thống thay vì luôn dùng nền trắng: chế độ sáng nền đen chữ trắng, chế độ tối nền trắng chữ đen; toast lỗi/cảnh báo/thành công vẫn giữ màu đỏ/vàng/xanh. Chữ đổi sang font hệ thống chuẩn (SF Pro, weight Regular) thay vì weight Light nét mảnh.
- `toast(message, 0)` giữ toast trên màn hình cho tới khi có lệnh toast mới (trước đây delay 0 bị coi là lỗi và không hiện gì); delay âm vẫn báo lỗi, delay thập phân (ví dụ `1.5`) được tôn trọng đúng thay vì bị cắt thành số nguyên.

## [0.3.30] — 2026-09-16

### Đã thêm
- Nút `Check` trên cả hai editor (native và Monaco) để chạy kiểm tra tĩnh theo yêu cầu.

### Đã thay đổi
- Kiểm tra script chỉ chạy khi bấm `Check`: bỏ kiểm tự động khi đang gõ, khi mở/chuyển tab và khi đổi ngôn ngữ, ở cả editor native lẫn Monaco. Run (dashboard) và Save (iPhone) vẫn kiểm lại nếu kết quả đang cũ nên cảnh báo "còn lỗi" luôn khớp với code hiện tại.
- Thụt lề còn 2 ký tự ở cả hai editor: phím Tab và auto-indent của editor native, `formatSource` của engine Python dùng chung, và `tabSize` của Monaco.

### Đã sửa
- Toast kết quả kiểm tra: bấm `Check` luôn hiện toast kể cả khi kết quả lặp lại; trước đây toast chỉ hiện khi kết quả đổi (để tránh nhấp nháy lúc kiểm tự động).
- Tắt VNC giờ tắt hẳn: bỏ `KeepAlive` khỏi LaunchDaemon TrollVNC nên launchd không dựng lại server sau khi tắt (trước đây chỉ bước kill chạy được, còn `plutil`/`launchctl unload` đòi root trong khi app, dashboardd và tweak đều chạy bằng `mobile`); dashboardd giám sát theo công tắc — bật thì khởi động server, tắt thì kill và giữ đúng trạng thái, kiểm tra lại mỗi 30 giây.
- Dashboard chỉ tự kết nối Live Screen khi `/api/status` xác nhận `vnc.enabled === true`: trạng thái chưa biết hoặc còn cũ (lần đầu mở trang, hoặc tab được đưa lên trước khi poll kịp cập nhật) không còn bị coi là được phép, nên tắt VNC rồi quay lại trang Scripts không còn tự kết nối và không còn thông báo client kết nối từ TrollVNC.

## [0.3.29] — 2026-09-16

### Đã thêm
- Editor script trên iPhone hiển thị số dòng ở mép trái, kèm vạch phân cách; số dòng bám theo layout nên dòng bị xuống hàng không bị đánh số hai lần.
- Setting `Editor Font Size` (slider 10–28) trong `Settings → Script`; cỡ chữ mới áp dụng ngay cho editor đang mở.

### Đã thay đổi
- Kết quả kiểm tra script hiển thị bằng toast ở đáy editor thay vì dòng trạng thái cố định phía trên: nền đỏ khi có lỗi, nền đen khi sạch; chạm vào toast để mở danh sách Problems. Toast chỉ hiện khi kết quả đổi nên không nhấp nháy lúc gõ.

### Đã sửa
- Editor trên iPhone tự chừa chỗ cho bàn phím và tự cuộn con trỏ lên trên bàn phím; trước đây bàn phím che mất phần dưới (kể cả con trỏ) nên rất khó soạn thảo.
- Bảng gợi ý autocomplete không còn bị bàn phím che.
- Checker không còn báo lỗi sai với những giá trị mà prelude chấp nhận: `tapText(..., index=0)` (0 = match đầu tiên, có ghi rõ trong prelude), `count` của `findColor`/`findColors`/`findImage` (bị clamp `max(1, count)`), `mins`/`maxs` âm của `randomInt`/`randomFloat`, và `duration` ngoài 0.3–5 của `setDebugVisual` (bị clamp).
- Enum của tham số kiểu `any` không còn bị bỏ qua: `keyDown`/`keyUp` với `keyType` sai giờ được báo đúng.

## [0.3.28] — 2026-09-16

### Đã thêm
- "Compiler" kiểm tra tĩnh cho script: vừa gõ vừa kiểm (debounce) và khi Run/Save, áp dụng cho cả Monaco (dashboard) lẫn editor native trên iPhone.
- Đánh giá dựa trên cấu trúc từng hàm qua `zxtouch.apispec`: sai cú pháp/cấu trúc câu lệnh, hàm không tồn tại, thiếu/thừa/sai keyword, sai kiểu literal, ngoài enum/range.
- Engine dùng chung `zxtouch.checker` (Python `ast`); task socket `49` chạy checker trên thiết bị; endpoint `POST /api/editor/validate` cho dashboard.
- Monaco hiển thị gạch chân lỗi (markers) kèm dòng trạng thái; script Lua được map ngược số dòng qua `lineMap` của transpiler.
- Editor native hiển thị gạch chân đỏ/cam, dòng trạng thái và danh sách Problems; hỏi xác nhận khi lưu script còn lỗi.

## [0.3.27] — 2026-09-15

### Đã thay đổi
- Tooltip function trong editor hiển thị thêm output/return type tương ứng cho từng function.
- Nút nổi dùng spring animation mượt hơn khi kéo dính vào mép, đồng thời hủy animation cũ an toàn khi kéo lại hoặc xoay màn hình.

## [0.3.26] — 2026-09-15

### Đã thay đổi
- Tab Monaco tự co theo độ dài tên script, không còn chiều rộng tối thiểu cố định.
- Khi chuyển tab, editor giữ nguyên vị trí con trỏ và vị trí cuộn riêng cho từng script.

## [0.3.25] — 2026-09-15

### Đã thêm
- Editor Monaco đa tab: mở nhiều script cùng lúc, chuyển tab nhanh, báo chấm chưa lưu, nút `+` tạo script mới.
- Nút tải ảnh chụp màn hình độ phân giải đầy đủ trên dashboard (`GET /api/capture-screen` trả về PNG).

### Đã thay đổi
- Gọn header editor và bề mặt tab; tiêu đề editor bám theo chiều rộng vùng soạn thảo, bỏ pane trạng thái và pane transpiled.

### Đã sửa
- Tắt VNC là tắt hẳn: unload daemon trước để KeepAlive không hồi sinh, rồi TERM → KILL kèm kiểm tra process và cổng `5901`/`5801`; dashboard dừng auto-reconnect và báo trạng thái cổng thực tế kể cả khi đã tắt.
- Tắt dashboard kéo theo tắt VNC trong cùng một lần ghi cấu hình; recovery và đổi scale có chốt chặn chống hồi sinh server khi người dùng vừa tắt.
- Ảnh chụp từ raw data giữ đúng định dạng PNG khi tên file có đuôi `.png`.

## [0.3.24] — 2026-09-15

### Đã thêm
- Cải thiện đồng bộ autocomplete, chữ ký hàm, tooltip và dashboard editor; bổ sung helper gõ văn bản có nhịp điệu tự nhiên.

### Đã thay đổi
- Script giữ metadata, icon và README trong từng bundle; bỏ registry và bộ example scripts được package cài đặt sẵn.

### Đã sửa
- Cải thiện IPC và vòng đời hiển thị bàn phím qua appdelegate, đồng thời sửa vị trí tooltip hàm trong editor.

## [0.3.23] — 2026-09-15

### Đã sửa
- Sửa cú pháp phân loại task truy vấn trạng thái bàn phím để package `pccontrol` biên dịch được.

## [0.3.22] — 2026-09-15

### Đã sửa
- Khai báo phương thức đăng ký observer trạng thái bàn phím để tweak appdelegate biên dịch được trên workflow package.

## [0.3.21] — 2026-09-15

### Đã thêm
- Bổ sung API Python `showKeyboard()`, `hideKeyboard()` và `keyboardVisible()` để điều khiển và truy vấn trạng thái bàn phím của ứng dụng đang ở phía trước.
- Thêm IPC giữa appdelegate và ZXTouch để phản hồi trạng thái bàn phím an toàn qua distributed notification.

### Đã sửa
- Nút nổi nhận thao tác chạm ổn định hơn trong hệ thống nhiều `UIWindow`, đồng thời khởi tạo popup khi cần.

## [0.3.20] — 2026-09-14

### Đã thêm
- Nút nổi toàn hệ thống: khi rảnh chạm để mở panel ZXTouch; khi script đang chạy chạm để tạm dừng, hiện toast "Script: Pause" kèm hộp "Stop Script?" (Yes = dừng hẳn, No = chạy tiếp). Nút kéo-thả được, tự dính mép, nhớ vị trí và tự xoay theo màn hình.
- Tạm dừng / tiếp tục script: áp dụng cho cả script raw (chờ có điều kiện, sleep chia nhỏ theo tốc độ phát) lẫn script Python (SIGSTOP/SIGCONT trên process group).
- Hạ tầng thông báo trạng thái script (`started` / `paused` / `resumed` / `stopped` / `finished`) để nút nổi và toast tự đồng bộ.
- Toast bền (persistent) không tự ẩn cho trạng thái tạm dừng.

### Đã thay đổi
- `system2Cancelable` có biến thể hỗ trợ pause cho tiến trình Python.
- Playback raw rút gọn xử lý tốc độ phát; các đường lỗi mở file / thiếu python dùng `clear` thống nhất.

### Đã sửa
- Toast cũ không còn ẩn nhầm toast mới (bộ đếm generation).
- `forceStop` / `clear` đánh thức các waiter đang pause và dừng runloop replay, tránh kẹt script.

## [0.3.19] — 2026-09-14

### Đã sửa
- OCR không còn áp dụng ngưỡng chiều cao mặc định khi người dùng không chỉ định `minimum_height`, khôi phục khả năng nhận diện các nhãn chữ nhỏ.
- Python client xử lý an toàn phản hồi socket rỗng, dữ liệu không phải bytes và dòng kết thúc CRLF.

## [0.3.18] — 2026-09-14

### Đã sửa
- OCR daemon không còn giữ IOSurface lock khi gọi `CARenderServerRenderDisplay` — render server là producer của surface, khóa trước khi render dễ deadlock/failed capture; nay render xong mới lock để đọc pixel, đúng thứ tự mà TrollVNC dùng trong daemon capture.
- Thêm log dọc pipeline capture (`render_start` / `render_complete` / `surface_lock_failed status=` / `image_copy_complete`) để chẩn đoán OCR stuck ở bước nào.

## [0.3.17] — 2026-09-14

### Đã sửa
- Thêm entitlement `com.apple.security.iokit-user-client-class` → `IOSurfaceRootUserClient` cho OCR daemon — trên iOS 15, tạo IOSurface phải mở user client này của kernel, thiếu là `IOSurfaceCreate` trả NULL (`surface_create ok=0`) dù size/properties đã đúng. Cùng entitlement daemon capture của TrollVNC đang dùng.

## [0.3.16] — 2026-09-14

### Đã sửa
- Bỏ `IOSurfaceIsGlobal` khỏi properties tạo surface trong OCR daemon — global surface chỉ window-server host (SpringBoard) mới tạo được, daemon gọi sẽ bị kernel từ chối (`surface_create ok=0`). Properties giờ giống TrollVNC (daemon capture đã chạy ổn định).

## [0.3.15] — 2026-09-14

### Đã sửa
- OCR daemon lấy kích thước màn hình bằng `_unjailedReferenceBoundsInPixels` (cách TrollVNC dùng trong daemon) thay vì `mainScreen.bounds` vốn trả về zero khi không có UIApplication scene — sửa lỗi `surface_create ok=0` khiến OCR hoàn toàn không hoạt động.
- Thêm fallback `bounds × scale` và `nativeBounds` cùng log nguồn kích thước (`size_source=`) để chẩn đoán capture.

## [0.3.14] — 2026-09-14

### Đã sửa
- Chuẩn hóa owner và permission của `com.zjx.ocr.plist` cùng binary OCR daemon trước khi `launchctl load`, tránh lỗi `path had bad ownership/permission` trên Dopamine rootless.
- Ghi lỗi load OCR daemon vào `ocrd.log` sau khi đã chuẩn hóa quyền để chẩn đoán được lỗi launchd còn lại.
- Sửa toàn bộ chuỗi thư mục `LaunchDaemons` (plist dashboard, TrollVNC và OCR) về `root:wheel` khi cài package — nguồn gốc lỗi là deb được build từ uid 1001 của runner.
- Workflow APT repo dựng lại deb với `--root-owner-group` để package phân phối qua GitHub Pages mang ownership root đúng chuẩn.

## [0.3.13] — 2026-09-14

### Đã thêm
- Tách OCR thành daemon `com.zjx.ocr` chạy nền, cho phép xử lý nhận dạng văn bản ngoài tiến trình SpringBoard.
- Bổ sung IPC OCR qua Unix socket, tự động quay về xử lý cục bộ khi daemon không khả dụng.

### Đã thay đổi
- Tái sử dụng IOSurface khi chụp màn hình OCR và ghi log chi tiết hơn cho quá trình capture, IPC và Vision.
- Bổ sung Vision và CoreImage vào các framework cần thiết cho pipeline OCR.

### Đã sửa
- Xử lý an toàn kết quả OCR không có candidate và sửa phép tính `minimumHeight` để dùng số thực chính xác.

## [0.3.12] — 2026-09-14

### Đã thêm
- Dashboard HTTP chạy dưới launch daemon riêng `com.zjx.dashboard` (`zxtouch-dashboardd`, `UserName mobile`, tự restart): crash dashboard không còn kéo SpringBoard theo; SpringBoard chỉ giữ fallback cho tới khi daemon chiếm port `:8080`.
- Endpoint `GET/POST /api/vnc/scale` đổi framebuffer scale TrollVNC (`0.3` mặc định tiết kiệm, thêm `0.5`, `0.6`, `0.7`, `1.0` pixel-perfect); dropdown Stream quality trên dashboard đã có tác dụng thật (restart server + reconnect).
- `/api/status` báo thêm `vnc.scale` thực tế đang chạy.

### Đã thay đổi
- Framebuffer TrollVNC mặc định giảm từ `-s 0.75` xuống `-s 0.3` để nhẹ RAM/bandwidth; launchd plist, recovery fallback và docs đồng bộ theo preset mới.
- Báo lỗi khi chạy script hiển thị bằng toast đỏ tự ẩn sau 3 giây thay vì hộp thoại alert chặn thao tác.

## [0.3.11] — 2026-09-14

### Đã thêm
- Dashboard gọi `POST /api/vnc/recover` để backend tự nạp lại daemon TrollVNC (có thời gian chờ 30 giây giữa các lần) khi auto-retry hết lượt, thay vì dừng hẳn ở trạng thái Offline.
- Trạng thái thiết bị báo đúng tình trạng cổng VNC thực tế (`vncPortOpen` / `httpPortOpen`); dashboard ghi log khi cổng 5901 đóng.
- Endpoint `GET /api/health` để kiểm tra dashboard HTTP đang sống.

### Đã thay đổi
- Kết quả `/api/status` được cache 2 giây để giảm tải cho IPC với service ZXTouch; khi service không phản hồi, dashboard nhận về payload offline rõ ràng (kèm cờ `stale`) thay vì lỗi chung.

### Đã sửa
- noVNC không còn gọi `disconnect()` trên RFB object đã đóng hoặc đang disconnect (kiểm tra trạng thái kết nối nội bộ trước khi teardown); hết treo khi bắt tay quá hạn hoặc bấm Disconnect lặp.
- `postinst` (rootless và roothide) ghi lỗi `launchctl load` TrollVNC vào `trollvnc.log` kèm thông báo dashboard sẽ tự khôi phục, thay vì âm thầm bỏ qua.

## [0.3.9] — 2026-09-13

### Đã thêm
- Thêm công tắc `VNC server management` dưới `Remote Management` để bật hoặc tắt VNC streaming screen và lưu trạng thái qua lần khởi động lại thiết bị.
- Editor tự lưu script sau một khoảng thời gian, hỗ trợ `Ctrl+S`/`Cmd+S`, báo trạng thái chưa lưu và tự nhận diện tên các hàm do người dùng định nghĩa để tô sáng.
- Bổ sung `setDebugTouchLog()` / `set_debug_touch_log()` để bật hoặc tắt log chẩn đoán cho các thao tác chạm và `tapText`.

### Đã thay đổi
- Monaco Editor tự thụt lề, định dạng khi gõ hoặc dán, dùng khoảng trắng với tab rộng 4 ký tự; gợi ý biến trong editor xử lý đúng khoảng trắng và phép gán nhiều biến.
- Python client thêm khoảng trễ ngẫu nhiên ngắn giữa các ký tự khi chèn văn bản để mô phỏng thao tác gõ thay vì gửi một đợt dán quá nhanh.

### Đã sửa
- Touch dispatch không còn bỏ sót thao tác chạm đầu tiên khi `senderID` chưa được khởi tạo; dữ liệu touch, kích thước màn hình và việc tạo hoặc dispatch HID event được kiểm tra an toàn hơn.
- Sửa liên kết symbol và điều khiển VNC daemon trong SpringBoard; trạng thái bật/tắt VNC được áp dụng đúng sau khi tải lại cấu hình.
- Đảm bảo package build thất bại rõ ràng nếu thiếu `trollvncserver` hoặc bundled noVNC, thay vì phát hành bản không thể kết nối VNC.
- Sửa retry noVNC để không gọi `disconnect()` lặp trên RFB object đã đóng.
- Làm mới TrollVNC daemon khi cài package và đồng bộ tài liệu WebSocket dùng cổng `5901`.

## [0.3.8] — 2026-09-13

### Đã thêm
- Tham số `lang` cho các hàm OCR: `findText`, `ocrFind`, `waitForText`, `tapText`, `ocrText` — nhận một mã (`"vi"`, `"en"`) hoặc danh sách (`{"vi", "en"}`) để nhận diện tiếng Việt có dấu chính xác hơn.
- Bảng `{k = v}` do `jsonDecode` trả về truy cập được như bảng Lua: `cfg.nested.a.b`, `cfg.loops[i]` — cả khi chạy Python trực tiếp lẫn qua editor Lua.
- Nối chuỗi `..` trong editor Lua hoạt động với số (`"gia tri: " .. 42`); `nil`, `~=`, `#` và các bảng một vị trí (`{1, 2, 3}`) dịch đúng, kể cả trên các dòng nối tiếp của lệnh nhiều dòng.

### Đã sửa
- Vòng lặp `for i = n, 1, -1` bước âm không còn bỏ sót lượt lặp cuối.
- Gán nhiều giá trị từ các hàm chạm/tìm (`local x, y = tapText(...)`, `tapImage`, `findImage`, `waitForImage`, `swipeUntil*`) dịch đúng trên mọi ví dụ trong tài liệu.
- `pairs(t)` với hai biến lặp theo cặp khóa–giá trị; với một biến vẫn lặp theo khóa như Lua.
- `findColor` kẹp ngưỡng màu về 0–255 và ghi log khi không tìm đủ số kết quả yêu cầu; `findImage` ghi log vùng tìm không được hỗ trợ thay vì âm thầm bỏ qua.

## [0.3.7] — 2026-09-13

### Đã thêm
- Nhóm hàm tiện ích hệ thống: `wifiInfo()`, `getIP()`, `setAirplaneMode()`, `setCellularData()`, `setProxySystem()`, `clearProxySystem()`. Các hàm này không bao giờ báo lỗi làm dừng script — chỉ trả kết quả và ghi lý do vào log.
- `httpGet` / `httpPost` trả kèm trạng thái phản hồi (`.status`, `.ok`) trên cùng kết quả là chuỗi thân trả về.
- Kho hàm mẫu trong editor tăng từ 62 lên 88 mục, có thêm nhóm Mạng. Bổ sung: `findColors`, `swipeUntilImage`, `deleteScreenshot`, `convertBase64`, `showOverlay`, `updateOverlay`, `hideOverlay`, `setDebugVisual`, `clearDebugVisual`, `keyDown`, `keyUp`, `randomFloat`, `httpPost`, `appendFile`, `recordPlay`, `recordSave`, `recordLoad`, `crane.rename`, `crane.delete`, `crane.wipe`, `crane.restore`.

### Đã thay đổi
- Bật/tắt máy bay và dữ liệu di động có tham số tự khôi phục sau `delay`; lịch khôi phục vẫn chạy đúng ngay cả khi script đã thoát.
- `local body, status = httpGet(...)` trong editor Lua nay dịch đúng sang cú pháp trả về mới.

### Đã sửa
- `httpGet` / `httpPost` không còn bị các API dùng Cloudflare chặn 403 (lỗi 1010): tự gửi User-Agent của trình duyệt.
- Lỗi HTTP (403, 404,…) không còn làm đứt cả script; chỉ khi không kết nối được mới trả kết quả rỗng.
- Bảng `{k = v}` trong Lua nay dịch đúng, kể cả bảng lồng nhiều tầng và lời gọi trải nhiều dòng.

## [0.3.6] — 2026-09-12

### Đã thêm
- Màn hình trực tiếp tự kết nối khi mở dashboard, tự thử lại khi rớt mạng (giãn cách 2/4/8/15/30 giây, có watchdog bắt tay 12 giây) kèm nút "Retry now"; hộp nhớ lựa chọn "Auto-connect & retry".
- Thẻ "Installed Apps" trong xem Thiết bị: tên + bundle ID, tìm kiếm, làm mới, huy hiệu "front" cho ứng dụng đang mở, chạm để copy bundle ID.
- Editor Lua hỗ trợ viết gọn một dòng: `if C then B end`, `while C do B end`, `for i=1,3 do B end`, kể cả `else` một dòng và nhiều lệnh nối bằng `;`.

### Đã sửa
- Script Lua đặt chuỗi trong điều kiện (`if`, `while`, `for`) không còn báo lỗi cú pháp khi chạy trên máy.

## [0.3.5] — 2026-09-12

### Đã thêm
- Tên các hàm API được tô sáng nổi bật trong editor, dễ phân biệt với mã thường khi viết Lua hoặc Python.

## [0.3.4] — 2026-09-12

### Đã thay đổi
- Hệ tọa độ được thống nhất về pixel thiết bị cho mọi hàm: `tap`, `swipe`, OCR, `findImage`, `findColor`, screenshot — trùng với đơn vị `screenSize()`. Tâm kết quả OCR chạm trực tiếp được ngay.

### Đã sửa
- Chạm không ăn trên các máy dòng Plus (điểm chạm trước đây bị quy đổi sai và có thể rơi ngoài màn hình).

## [0.3.3] — 2026-09-12

### Đã thêm
- Hình minh họa debug vẽ trực tiếp lên màn hình iPhone khi script chạy: khung đỏ quanh kết quả OCR / ảnh tìm được, vòng tròn đỏ tại điểm chạm, đoạn thẳng đỏ cho thao tác vuốt. Mặc định bật, tự mờ, không chặn cảm ứng.
- `setDebugVisual(enabled, duration)` để bật/tắt và chỉnh thời gian hiển thị; `clearDebugVisual()` để xóa ngay mọi hình đang hiện.

## [0.3.2] — 2026-09-12

### Đã thêm
- `ocrFind(text)` trả về `(x, y, matched_text)` theo kiểu Lua.
- Log script có dấu mốc bắt đầu / kết thúc kèm dấu thời gian.
- Mở dashboard thẳng từ app mà không cần token.

### Đã sửa
- Thao tác chạm theo kết quả OCR trả về sai vị trí.

## [0.3.1] — 2026-09-12

### Đã thay đổi
- Thanh điều khiển Màn hình trực tiếp chuyển sang dạng icon, gọn và dễ dùng trên điện thoại; icon mới cho nút đánh thức màn hình.
- Editor và khung log bám sát chiều cao màn hình, không còn phải cuộn trang.

### Đã thêm
- Trình gợi ý hàm khi gõ trong editor (tự động hoàn tất) cho cả Lua lẫn Python.

## [0.3.0] — 2026-09-12

### Đã thêm
- Viết script không cần mã rườm rà: gọi `tap()`, `swipe()`, `ocr()`… trực tiếp ở cả Lua lẫn Python, không cần khai báo hay khởi tạo.
- Tab Editor ngay trong dashboard: viết — lưu — chạy tức thì, có bản sao dự phòng khi không có internet.
- Khung "Hàm" gồm 12 nhóm bên cạnh editor, chạm để chèn mẫu Lua/Python.
- Khung "Run Log" bên dưới editor: theo dõi log khi script chạy, cộng dồn qua nhiều lần chạy, chỉ xóa khi bấm.
- Bộ hàm `crane.*` cho script: `list`, `switch`, `create`, `delete`, `rename`, `clearData`, `size`, `backup`, `wipe`, `restore`. Máy chưa cài Crane sẽ được nhận biết và bỏ qua an toàn.

### Đã thay đổi
- Popup "Script Finished" tắt theo mặc định; bật lại được trong Cài đặt.

### Đã sửa
- Phân loại loại tác vụ bàn phím (5/6/7) và ví dụ Quick Tap.

## [0.2.2] — 2026-09-12

### Đã thay đổi
- Cổng WebSocket của Màn hình trực tiếp chuyển sang `:5901` cho ổn định.

### Đã thêm
- Log chẩn đoán khi kết nối VNC có vấn đề.

## [0.2.1] — 2026-09-12

### Đã thêm
- Thư viện giải nén cho noVNC được đóng gói kèm, Màn hình trực tiếp chạy không phụ thuộc tài nguyên bên ngoài.

### Đã loại bỏ
- Cơ chế dự phòng kết nối qua cổng `:5801` — việc kết nối gọn và dự đoán được hơn.

## [0.2.0] — 2026-09-12

### Đã thay đổi
- TrollVNC được build từ mã nguồn trong repo thay vì dùng gói tải sẵn, bản phân phối tự chủ và nhất quán hơn.

## [0.1.9] — 2026-09-12

### Đã thay đổi
- Dashboard trong mạng LAN mở không cần token, dùng liền từ thiết bị khác cùng mạng.

### Đã thêm
- noVNC đóng gói kèm trong app: Màn hình trực tiếp hoạt động cả khi máy không có internet.

## [0.1.8] — 2026-09-12

### Đã thêm
- Màn hình trực tiếp: xem màn hình iPhone ngay trên dashboard qua VNC (TrollVNC), thao tác được từ máy tính/tablet.
- Trang APT repo riêng để cài và cập nhật bằng dòng lệnh.
- Quy trình xuất bản tự động: build xong là bản mới lên repo, không cần thao tác tay.
- Dịch vụ VNC chạy nền cùng hệ thống, khởi động lại máy vẫn dùng được.

## [0.1.7] — 2026-08-30

### Đã sửa
- iOS 17 ổn định hơn: SpringBoard không còn rơi vào safe mode, hết tình trạng kẹt ở chế độ ghi thao tác.
- Nút Stop trên bảng điều khiển dừng được cả phiên ghi thao tác.

### Đã thêm
- Tùy chọn bật/tắt popup "Script Finished" trong Cài đặt.
- Hướng dẫn cài đặt cho iOS 17.

<!-- So sánh giữa các bản -->

[0.3.52]: https://github.com/chiconghvan/utouch/compare/v0.3.51...v0.3.52
[0.3.51]: https://github.com/chiconghvan/utouch/compare/v0.3.50...v0.3.51
[0.3.50]: https://github.com/chiconghvan/utouch/compare/v0.3.48...v0.3.50
[0.3.48]: https://github.com/chiconghvan/utouch/compare/v0.3.47...v0.3.48
[0.3.47]: https://github.com/chiconghvan/utouch/compare/v0.3.46...v0.3.47
[0.3.46]: https://github.com/chiconghvan/utouch/compare/v0.3.45...v0.3.46
[0.3.45]: https://github.com/chiconghvan/utouch/compare/v0.3.44...v0.3.45
[0.3.44]: https://github.com/chiconghvan/utouch/compare/v0.3.43...v0.3.44
[0.3.43]: https://github.com/chiconghvan/utouch/compare/v0.3.42...v0.3.43
[0.3.42]: https://github.com/chiconghvan/utouch/compare/v0.3.41...v0.3.42
[0.3.41]: https://github.com/chiconghvan/utouch/compare/v0.3.40...v0.3.41
[0.3.40]: https://github.com/chiconghvan/utouch/compare/v0.3.39...v0.3.40
[0.3.39]: https://github.com/chiconghvan/utouch/compare/v0.3.38...v0.3.39
[0.3.38]: https://github.com/chiconghvan/utouch/compare/v0.3.37...v0.3.38
[0.3.37]: https://github.com/chiconghvan/utouch/compare/v0.3.36...v0.3.37
[0.3.36]: https://github.com/chiconghvan/utouch/compare/v0.3.35...v0.3.36
[0.3.35]: https://github.com/chiconghvan/utouch/compare/v0.3.34...v0.3.35
[0.3.34]: https://github.com/chiconghvan/utouch/compare/v0.3.33...v0.3.34
[0.3.33]: https://github.com/chiconghvan/utouch/compare/v0.3.32...v0.3.33
[0.3.32]: https://github.com/chiconghvan/utouch/compare/v0.3.31...v0.3.32
[0.3.31]: https://github.com/chiconghvan/utouch/compare/v0.3.30...v0.3.31
[0.3.30]: https://github.com/chiconghvan/utouch/compare/v0.3.29...v0.3.30
[0.3.29]: https://github.com/chiconghvan/utouch/compare/v0.3.28...v0.3.29
[0.3.28]: https://github.com/chiconghvan/utouch/compare/v0.3.27...v0.3.28
[0.3.27]: https://github.com/chiconghvan/utouch/compare/v0.3.26...v0.3.27
[0.3.26]: https://github.com/chiconghvan/utouch/compare/v0.3.25...v0.3.26
[0.3.25]: https://github.com/chiconghvan/utouch/compare/v0.3.24...v0.3.25
[0.3.24]: https://github.com/chiconghvan/utouch/compare/v0.3.23...v0.3.24
[0.3.23]: https://github.com/chiconghvan/utouch/compare/v0.3.22...v0.3.23
[0.3.22]: https://github.com/chiconghvan/utouch/compare/v0.3.21...v0.3.22
[0.3.21]: https://github.com/chiconghvan/utouch/compare/v0.3.20...v0.3.21
[0.3.20]: https://github.com/chiconghvan/utouch/compare/v0.3.19...v0.3.20
[0.3.19]: https://github.com/chiconghvan/utouch/compare/v0.3.18...v0.3.19
[0.3.18]: https://github.com/chiconghvan/utouch/compare/v0.3.17...v0.3.18
[0.3.17]: https://github.com/chiconghvan/utouch/compare/v0.3.16...v0.3.17
[0.3.16]: https://github.com/chiconghvan/utouch/compare/v0.3.15...v0.3.16
[0.3.15]: https://github.com/chiconghvan/utouch/compare/v0.3.14...v0.3.15
[0.3.14]: https://github.com/chiconghvan/utouch/compare/v0.3.13...v0.3.14
[0.3.13]: https://github.com/chiconghvan/utouch/compare/v0.3.12...v0.3.13
[0.3.12]: https://github.com/chiconghvan/utouch/compare/v0.3.11...v0.3.12
[0.3.11]: https://github.com/chiconghvan/utouch/compare/v0.3.10...v0.3.11
[0.3.9]: https://github.com/chiconghvan/utouch/compare/v0.3.8...v0.3.9
[0.3.8]: https://github.com/chiconghvan/utouch/compare/v0.3.7...v0.3.8
[0.3.7]: https://github.com/chiconghvan/utouch/compare/v0.3.6...v0.3.7
[0.3.6]: https://github.com/chiconghvan/utouch/compare/v0.3.5...v0.3.6
[0.3.5]: https://github.com/chiconghvan/utouch/compare/v0.3.4...v0.3.5
[0.3.4]: https://github.com/chiconghvan/utouch/compare/v0.3.3...v0.3.4
[0.3.3]: https://github.com/chiconghvan/utouch/compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com/chiconghvan/utouch/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/chiconghvan/utouch/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/chiconghvan/utouch/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/chiconghvan/utouch/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/chiconghvan/utouch/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/chiconghvan/utouch/compare/v0.1.9...v0.2.0
[0.1.9]: https://github.com/chiconghvan/utouch/compare/v0.1.8...v0.1.9
[0.1.8]: https://github.com/chiconghvan/utouch/compare/32529e5...v0.1.8
[0.1.7]: https://github.com/chiconghvan/utouch/commit/32529e5
