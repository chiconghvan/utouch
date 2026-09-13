# Thay đổi phiên bản

Mẫu thay đổi dạng *Keep a Changelog* cho uTouch / zxtouch, tuân thủ
[Keep a Changelog](https://keepachangelog.com/vi/1.1.0/); số phiên bản theo
[Semantic Versioning](https://semver.org/lang/vi/).

Loại mục: `Đã thêm` (tính năng mới) · `Đã thay đổi` (đổi hành vi sẵn có) ·
`Đã sửa` (khắc phục lỗi) · `Đã loại bỏ` (bỏ hẳn).

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
