# IOSControl — API Reference (full)

> Nguon: https://ioscontrol.com/docs.html (`docs-data.js?v=8`)
> Ngay fetch: 2026-09-12
> Sections: 17 | Functions/Endpoints: 103
> Ngon ngu: EN chinh + VI phu (giup tra cuu song ngu nhu trang goc).

## Muc luc

1. [Touch Simulation (8)](#sec-touch)
2. [Color & Pixel (5)](#sec-color)
3. [Image Recognition (12)](#sec-image)
4. [User Interaction (7)](#sec-interact)
5. [App Management (5)](#sec-app)
6. [Text & Input (5)](#sec-input)
7. [UI & Feedback (4)](#sec-ui)
8. [Timing & Sleep (3)](#sec-timing)
9. [Screen Info (2)](#sec-screen)
10. [HTTP Client (2)](#sec-http)
11. [File & JSON (5)](#sec-file)
12. [Utilities (8)](#sec-util)
13. [Record & Playback (5)](#sec-record)
14. [Scheduler (3)](#sec-schedule)
15. [HTTP APIs (9)](#sec-rest)
16. [Crane Containers (10)](#sec-crane)
17. [Device Spoofing (10)](#sec-spoof)

---

<a id="sec-touch"></a>
## Touch Simulation

_Mô phỏng cảm ứng_

Simulate touches, swipes, pinch, rotate and other gestures on the device screen.

_Mô phỏng chạm, vuốt, phóng to, xoay và các thao tác cảm ứng khác trên màn hình._

### `tap(x, y)`

- Type: `func`
- EN: Tap at coordinates
- VI: Chạm tại toạ độ
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `x` | `number` | yes | X coordinate (WDA points) | Toạ độ X (điểm WDA) |
| `y` | `number` | yes | Y coordinate (WDA points) | Toạ độ Y (điểm WDA) |

**Example (Lua/cURL):**

```lua
-- Tap a button then wait for UI response
tap(195, 400)
sleep(0.3)
local c = getColor(195, 400)
if c ~= 0xFFFFFF then
  log("Button pressed successfully")
end
```
**Example (Python):**

```python
# Tap a button then wait for UI response
tap(195, 400)
sleep(0.3)
c = get_color(195, 400)
if c != 0xFFFFFF:
    log("Button pressed successfully")
```
---

### `touchDown(id, x, y)`

- Type: `func`
- EN: Press finger down (multi-touch)
- VI: Nhấn ngón tay xuống (đa chạm)
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `id` | `number` | yes | Finger ID (0-9) | ID ngón tay (0-9) |
| `x` | `number` | yes | X coordinate | Toạ độ X |
| `y` | `number` | yes | Y coordinate | Toạ độ Y |

**Example (Lua/cURL):**

```lua
-- Pinch-to-zoom with two fingers
touchDown(0, 150, 400)
touchDown(1, 250, 400)
sleep(0.1)
for i = 1, 10 do
  touchMove(0, 150 - i*5, 400)
  touchMove(1, 250 + i*5, 400)
  usleep(30000)
end
touchUp(0, 100, 400)
touchUp(1, 300, 400)
```
**Example (Python):**

```python
# Pinch-to-zoom with two fingers
touch_down(0, 150, 400)
touch_down(1, 250, 400)
sleep(0.1)
for i in range(1, 11):
    touch_move(0, 150 - i*5, 400)
    touch_move(1, 250 + i*5, 400)
    usleep(30000)
touch_up(0, 100, 400)
touch_up(1, 300, 400)
```
---

### `touchMove(id, x, y)`

- Type: `func`
- EN: Move finger to new position
- VI: Di chuyển ngón tay đến vị trí mới
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `id` | `number` | yes | Finger ID | ID ngón tay |
| `x` | `number` | yes | New X | X mới |
| `y` | `number` | yes | New Y | Y mới |

**Example (Lua/cURL):**

```lua
-- Draw a circle gesture
touchDown(0, 200, 300)
for angle = 0, 360, 10 do
  local rad = math.rad(angle)
  local x = 200 + 50 * math.cos(rad)
  local y = 300 + 50 * math.sin(rad)
  touchMove(0, x, y)
  usleep(20000)
end
touchUp(0, 200, 300)
```
**Example (Python):**

```python
# Draw a circle gesture
import math
touch_down(0, 200, 300)
for angle in range(0, 361, 10):
    rad = math.radians(angle)
    x = 200 + 50 * math.cos(rad)
    y = 300 + 50 * math.sin(rad)
    touch_move(0, x, y)
    usleep(20000)
touch_up(0, 200, 300)
```
---

### `touchUp(id, x, y)`

- Type: `func`
- EN: Release finger
- VI: Nhả ngón tay
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `id` | `number` | yes | Finger ID | ID ngón tay |
| `x` | `number` | yes | X coordinate | Toạ độ X |
| `y` | `number` | yes | Y coordinate | Toạ độ Y |

**Example (Lua/cURL):**

```lua
touchUp(0, 150, 300)
```
---

### `swipe(x1, y1, x2, y2, duration)`

- Type: `func`
- EN: Swipe gesture from point A to B
- VI: Vuốt từ điểm A đến B
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `x1` | `number` | yes | Start X | X bắt đầu |
| `y1` | `number` | yes | Start Y | Y bắt đầu |
| `x2` | `number` | yes | End X | X kết thúc |
| `y2` | `number` | yes | End Y | Y kết thúc |
| `duration` | `number` | no | Duration in seconds (default: 0.5) | Thời gian (giây, mặc định: 0.5) |

**Example (Lua/cURL):**

```lua
-- Scroll through a feed 5 times
for i = 1, 5 do
  swipe(200, 600, 200, 200, 0.3)
  sleep(1.5)
  log("Scrolled page " .. i)
end
```
**Example (Python):**

```python
# Scroll through a feed 5 times
for i in range(1, 6):
    swipe(200, 600, 200, 200, 0.3)
    sleep(1.5)
    log(f"Scrolled page {i}")
```
---

### `longPress(x, y, duration)`

- Type: `func`
- EN: Long press at coordinates
- VI: Nhấn giữ tại toạ độ
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `x` | `number` | yes | X coordinate | Toạ độ X |
| `y` | `number` | yes | Y coordinate | Toạ độ Y |
| `duration` | `number` | no | Hold duration in seconds | Thời gian giữ (giây) |

**Example (Lua/cURL):**

```lua
-- Long press to open context menu
longPress(200, 400, 1.5)
sleep(0.5)
-- Tap "Copy" option in context menu
tap(200, 350)
```
**Example (Python):**

```python
# Long press to open context menu
long_press(200, 400, 1.5)
sleep(0.5)
# Tap "Copy" option in context menu
tap(200, 350)
```
---

### `pinch(x, y, scale, duration)`

- Type: `func`
- EN: Pinch zoom in/out gesture
- VI: Phóng to/thu nhỏ bằng 2 ngón
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `x` | `number` | yes | Center X | Tâm X |
| `y` | `number` | yes | Center Y | Tâm Y |
| `scale` | `number` | yes | Scale factor (>1 = zoom in, <1 = zoom out) | Hệ số (>1 = phóng to, <1 = thu nhỏ) |
| `duration` | `number` | no | Duration in seconds | Thời gian (giây) |

**Example (Lua/cURL):**

```lua
pinch(200, 400, 2.0, 0.5)  -- Zoom in 2x
```
---

### `rotate(x, y, angle, duration)`

- Type: `func`
- EN: Rotate gesture around center point
- VI: Xoay quanh điểm trung tâm
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `x` | `number` | yes | Center X | Tâm X |
| `y` | `number` | yes | Center Y | Tâm Y |
| `angle` | `number` | yes | Rotation angle in degrees | Góc xoay (độ) |
| `duration` | `number` | no | Duration in seconds | Thời gian (giây) |

**Example (Lua/cURL):**

```lua
rotate(200, 400, 90, 0.5)  -- Rotate 90°
```
---

<a id="sec-color"></a>
## Color & Pixel

_Màu sắc & Pixel_

Read pixel colors, find color patterns, and wait for specific colors on screen.

_Đọc màu pixel, tìm mẫu màu, và chờ màu cụ thể trên màn hình._

### `getColor(x, y)`

- Type: `func`
- EN: Get pixel color at coordinates
- VI: Lấy màu pixel tại toạ độ
- Return: `number — hex color (0xRRGGBB)`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `x` | `number` | yes | X coordinate | Toạ độ X |
| `y` | `number` | yes | Y coordinate | Toạ độ Y |

**Example (Lua/cURL):**

```lua
-- Wait for loading screen to finish
while true do
  local c = getColor(200, 400)
  if c ~= 0x000000 then
    log("Loading complete! Color: " .. string.format("0x%06X", c))
    break
  end
  sleep(0.5)
end
tap(200, 400)
```
**Example (Python):**

```python
# Wait for loading screen to finish
while True:
    c = get_color(200, 400)
    if c != 0x000000:
        log(f"Loading complete! Color: {c:#08x}")
        break
    sleep(0.5)
tap(200, 400)
```
---

### `getColors(locations)`

- Type: `func`
- EN: Get multiple pixel colors at once
- VI: Lấy nhiều màu pixel cùng lúc
- Return: `table — array of hex colors`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `locations` | `table` | yes | Array of {x, y} pairs | Mảng các cặp {x, y} |

**Example (Lua/cURL):**

```lua
local colors = getColors({{100,200}, {150,300}})
```
---

### `findColor(color, count, region)`

- Type: `func`
- EN: Find pixels matching a specific color. Returns table of {{x,y}, {x,y}, ...} (indexed, not keyed). Uses keepScreen() buffer if active.
- VI: Tìm pixel khớp với màu chỉ định. Trả về bảng {{x,y}, {x,y}, ...} (theo chỉ mục). Dùng buffer keepScreen() nếu đang hoạt động.
- Return: `[object Object]`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `color` | `number` | yes | Target color (0xRRGGBB) | Màu đích (0xRRGGBB) |
| `count` | `number` | no | Max results (0 = all, default: 0) | Số kết quả tối đa (0 = tất cả, mặc định: 0) |
| `region` | `table` | no | {x, y, w, h} search area (POINT) | Vùng tìm {x, y, w, h} (POINT) |

**Example (Lua/cURL):**

```lua
-- Find all red pixels on screen
local pts = findColor(0xFF0000, 10, {0, 0, 414, 896})
log("Found " .. #pts .. " red pixels")
for _, p in ipairs(pts) do
  tap(p[1], p[2])  -- p[1]=x, p[2]=y
  sleep(0.3)
end

-- Tìm tất cả pixel đỏ trên màn hình
-- Kết quả: {{x1,y1}, {x2,y2}, ...}
```
---

### `findColors(colors, count, region)`

- Type: `func`
- EN: Find multi-color pattern on screen. Colors format: {{color, dx, dy}, ...} where dx/dy are POINT offsets from anchor.
- VI: Tìm mẫu nhiều màu trên màn hình. Định dạng: {{color, dx, dy}, ...} trong đó dx/dy là offset POINT từ điểm neo.
- Return: `[object Object]`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `colors` | `table` | yes | {{color, dx, dy}, ...} — anchor color first (dx=0,dy=0) | {{color, dx, dy}, ...} — màu neo đầu tiên (dx=0,dy=0) |
| `count` | `number` | no | Max results (0 = all) | Số kết quả tối đa (0 = tất cả) |
| `region` | `table` | no | {x, y, w, h} search area (POINT) | Vùng tìm {x, y, w, h} (POINT) |

**Example (Lua/cURL):**

```lua
-- Find pattern: red pixel, green pixel 10px right
local results = findColors({
  {0xFF0000, 0, 0},   -- anchor: red
  {0x00FF00, 10, 0},  -- green 10pt to the right
}, 1)
if #results > 0 then
  tap(results[1][1], results[1][2])
end
```
---

### `waitForColor(x, y, color, timeout)`

- Type: `func`
- EN: Wait until pixel matches target color
- VI: Chờ cho đến khi pixel khớp màu
- Return: `boolean — true if matched`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `x` | `number` | yes | X coordinate | Toạ độ X |
| `y` | `number` | yes | Y coordinate | Toạ độ Y |
| `color` | `number` | yes | Expected color | Màu mong đợi |
| `timeout` | `number` | no | Timeout in seconds | Thời gian chờ (giây) |

**Example (Lua/cURL):**

```lua
-- Wait for green "Ready" indicator
local ok = waitForColor(200, 300, 0x00FF00, 10)
if ok then
  log("Ready! Starting automation...")
  tap(200, 500)
else
  log("Timeout waiting for ready state")
end
```
**Example (Python):**

```python
# Wait for green "Ready" indicator
ok = wait_for_color(200, 300, 0x00FF00, 10)
if ok:
    log("Ready! Starting automation...")
    tap(200, 500)
else:
    log("Timeout waiting for ready state")
```
---

<a id="sec-image"></a>
## Image Recognition

_Nhận dạng hình ảnh_

Find images on screen with template matching, OCR text recognition.

_Tìm hình ảnh trên màn hình bằng template matching, nhận dạng chữ OCR._

### `findImage(path, count, threshold, region)`

- Type: `func`
- EN: Find template image on screen. When count=1: returns x, y (two values). When count>1: returns table of {{x,y}, ...}
- VI: Tìm hình ảnh mẫu trên màn hình. Khi count=1: trả về x, y (hai giá trị). Khi count>1: trả về bảng {{x,y}, ...}
- Return: `[object Object]`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `path` | `string` | yes | Image filename (from images/ or scripts/ dir) | Tên file ảnh (từ thư mục images/ hoặc scripts/) |
| `count` | `number` | no | Max matches (default: 1) | Số kết quả tối đa (mặc định: 1) |
| `threshold` | `number` | no | Match threshold 0-1 (default: 0.9) | Ngưỡng khớp 0-1 (mặc định: 0.9) |
| `region` | `table` | no | {x, y, w, h} search region (POINT) | Vùng tìm {x, y, w, h} (POINT) |

**Example (Lua/cURL):**

```lua
-- count=1 (default): returns x, y
local x, y = findImage("play_btn.png")
if x then
  tap(x, y)
  log("Found at " .. x .. "," .. y)
else
  log("Not found")
end

-- count>1: returns table
local matches = findImage("star.png", 5, 0.85)
log("Found " .. #matches .. " matches")
for i, m in ipairs(matches) do
  tap(m[1], m[2])  -- m[1]=x, m[2]=y
  sleep(0.3)
end

-- With region (search only bottom half)
local x, y = findImage("btn.png", 1, 0.9, {0, 400, 414, 450})
```
---

### `waitForImage(path, timeout)`

- Type: `func`
- EN: Wait for image to appear on screen. Polls every 500ms. Returns table {x=, y=} on success, false on timeout.
- VI: Chờ hình ảnh xuất hiện trên màn hình. Kiểm tra mỗi 500ms. Trả về bảng {x=, y=} nếu thành công, false nếu hết thời gian.
- Return: `[object Object]`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `path` | `string` | yes | Image filename | Tên file ảnh |
| `timeout` | `number` | no | Timeout in seconds (default: 10) | Thời gian chờ giây (mặc định: 10) |

**Example (Lua/cURL):**

```lua
-- Wait for dialog to appear, then tap it
local result = waitForImage("dialog.png", 15)
if result then
  tap(result.x, result.y)
  log("Dialog found at " .. result.x .. "," .. result.y)
else
  log("Dialog not found after 15s")
end
```
---

### `screenshot(name, region)`

- Type: `func`
- EN: Take screenshot — saves as JPEG in images/ directory
- VI: Chụp màn hình — lưu JPEG vào thư mục images/
- Return: `string — saved file path`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `name` | `string` | no | Filename (saved to images/ dir) | Tên file (lưu vào thư mục images/) |
| `region` | `table` | no | {x, y, w, h} capture region | Vùng chụp {x, y, w, h} |

**Example (Lua/cURL):**

```lua
-- Full screen
screenshot("myscreen")

-- Region crop
screenshot("crop", {200, 200, 400, 400})

-- Auto timestamp name
screenshot()
```
---

### `deleteScreenshot(name)`

- Type: `func`
- EN: Delete screenshot from images/ directory
- VI: Xoá screenshot từ thư mục images/
- Return: `boolean — success`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `name` | `string` | yes | Filename to delete | Tên file cần xoá |

**Example (Lua/cURL):**

```lua
deleteScreenshot("old_screenshot.jpg")
```
---

### `convertBase64(path)`

- Type: `func`
- EN: Convert file to base64 string (images/, scripts/)
- VI: Chuyển file sang chuỗi base64 (images/, scripts/)
- Return: `string — base64 encoded data`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `path` | `string` | yes | Filename or absolute path | Tên file hoặc đường dẫn tuyệt đối |

**Example (Lua/cURL):**

```lua
-- Screenshot then send via HTTP
screenshot("capture.jpg")
local b64 = convertBase64("capture.jpg")
httpPost("https://api.example.com/upload", {image = b64})
```
---

### `ocrText(x, y, w, h)`

- Type: `func`
- EN: Read text from screen region via OCR
- VI: Đọc chữ từ vùng màn hình bằng OCR
- Return: `string — detected text`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `x` | `number` | no | Region X | X vùng |
| `y` | `number` | no | Region Y | Y vùng |
| `w` | `number` | no | Region width (0 = full screen) | Chiều rộng (0 = toàn màn hình) |
| `h` | `number` | no | Region height | Chiều cao vùng |

**Example (Lua/cURL):**

```lua
-- Read coin count from game UI
local text = ocrText(50, 10, 150, 40)
local coins = tonumber(text:match("%d+"))
if coins then
  log("Current coins: " .. coins)
  if coins >= 1000 then
    log("Enough coins! Buying upgrade...")
    tap(300, 500)
  end
end
```
**Example (Python):**

```python
# Read coin count from game UI
text = ocr_text(50, 10, 150, 40)
import re
m = re.search(r"\d+", text)
if m:
    coins = int(m.group())
    log(f"Current coins: {coins}")
    if coins >= 1000:
        log("Enough coins! Buying upgrade...")
        tap(300, 500)
```
---

### `findText(text, region)`

- Type: `func`
- EN: Find text on screen using OCR. Returns x, y, text (three values) or nil. Alias: ocrFind()
- VI: Tìm chữ trên màn hình bằng OCR. Trả về x, y, text (ba giá trị) hoặc nil. Bí danh: ocrFind()
- Return: `[object Object]`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `text` | `string` | yes | Text to search for | Chữ cần tìm |
| `region` | `table` | no | {x, y, w, h} search area (POINT) | Vùng tìm {x, y, w, h} (POINT) |

**Example (Lua/cURL):**

```lua
-- Find text and tap it
local x, y, text = findText("Login")
if x then
  tap(x, y)
  log("Found: " .. text .. " at " .. x .. "," .. y)
else
  log("Text not found")
end

-- Search only in specific region
local x, y = findText("OK", {0, 600, 414, 200})
```
---

### `waitForText(text, timeout)`

- Type: `func`
- EN: Wait for text to appear on screen (OCR). Polls every 500ms. Returns table {x=, y=, text=} on success, false on timeout.
- VI: Chờ chữ xuất hiện trên màn hình (OCR). Kiểm tra mỗi 500ms. Trả về bảng {x=, y=, text=} nếu tìm thấy, false nếu hết giờ.
- Return: `[object Object]`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `text` | `string` | yes | Text to wait for | Chữ cần chờ |
| `timeout` | `number` | no | Timeout in seconds (default: 10) | Thời gian chờ giây (mặc định: 10) |

**Example (Lua/cURL):**

```lua
-- Wait for welcome screen
local result = waitForText("Welcome", 15)
if result then
  tap(result.x, result.y)
  log("Found: " .. result.text)
else
  log("Welcome not found after 15s")
end
```
---

### `tapImage(path, timeout, threshold, region)`

- Type: `func`
- EN: Find image on screen and tap its center. Optional region to limit search area.
- VI: Tìm hình trên màn hình và chạm vào giữa. Tuỳ chọn region để giới hạn vùng tìm.
- Return: `boolean, x, y`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `path` | `string` | yes | Image filename | Tên file ảnh |
| `timeout` | `number` | no | Timeout seconds (default 5) | Thời gian chờ (mặc định 5) |
| `threshold` | `number` | no | Match threshold 0-1 (default 0.8) | Ngưỡng khớp 0-1 (mặc định 0.8) |
| `region` | `table` | no | {x, y, w, h} search area (POINT). Omit for full screen. | Vùng tìm {x, y, w, h} (POINT). Bỏ qua = toàn màn hình. |

**Example (Lua/cURL):**

```lua
-- One-liner: find and tap button
local ok, x, y = tapImage("btn_ok.png")
if ok then log("Tapped at " .. x .. "," .. y) end

-- Search only bottom half of screen
tapImage("btn.png", 10, 0.85, {0, 400, 414, 200})
```
---

### `tapText(text, timeout, index, region)`

- Type: `func`
- EN: Find text on screen (OCR) and tap it. If multiple matches exist, use index to select which one. Optional region to limit search area.
- VI: Tìm chữ trên màn hình (OCR) và chạm vào. Nếu có nhiều kết quả, dùng index để chọn. Tuỳ chọn region để giới hạn vùng tìm.
- Return: `boolean, x, y`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `text` | `string` | yes | Text to find and tap | Chữ cần tìm và chạm |
| `timeout` | `number` | no | Timeout seconds (default 5) | Thời gian chờ (mặc định 5) |
| `index` | `number` | no | Which occurrence to tap (1=first, 2=second...). Sorted top→bottom, left→right. Default: 1 | Thứ tự kết quả cần chạm (1=đầu tiên, 2=thứ hai...). Sắp xếp trên→dưới, trái→phải. Mặc định: 1 |
| `region` | `table` | no | {x, y, w, h} search area (POINT). Omit for full screen. | Vùng tìm {x, y, w, h} (POINT). Bỏ qua = toàn màn hình. |

**Example (Lua/cURL):**

```lua
-- Tap first occurrence (default)
tapText("Add")

-- Tap the 2nd "Delete" button on screen
tapText("Delete", 5, 2)

-- Search only in header area
tapText("Back", 5, 1, {0, 0, 200, 80})

-- Login flow
tapText("Login")
sleep(1)
tapText("Continue")
```
---

### `swipeUntilImage(path, direction, maxSwipes, threshold, speed)`

- Type: `func`
- EN: Swipe screen until image is found
- VI: Vuốt cho đến khi tìm thấy hình
- Return: `boolean, x, y`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `path` | `string` | yes | Image to search for | Hình cần tìm |
| `direction` | `string` | no | "up", "down", "left", "right" | "up", "down", "left", "right" |
| `maxSwipes` | `number` | no | Maximum swipe attempts (default 10) | Số lần vuốt tối đa (mặc định 10) |
| `threshold` | `number` | no | Match threshold 0-1 (default 0.9) | Ngưỡng khớp 0-1 (mặc định 0.9) |
| `speed` | `number` | no | Swipe duration in seconds (default 0.5) | Tốc độ vuốt tính bằng giây (mặc định 0.5) |

**Example (Lua/cURL):**

```lua
-- Scroll down until we see the target
local ok, x, y = swipeUntilImage("target.png", "up", 15)
if ok then
  log("Found at " .. x .. "," .. y)
  tap(x, y)
end

-- Fast swipe with custom speed
swipeUntilImage("btn.png", "up", 10, 0.9, 0.2)
```
---

### `swipeUntilText(text, direction, maxSwipes, speed)`

- Type: `func`
- EN: Swipe screen until text is found (OCR)
- VI: Vuốt cho đến khi tìm thấy chữ (OCR)
- Return: `boolean, x, y`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `text` | `string` | yes | Text to search for | Chữ cần tìm |
| `direction` | `string` | no | "up", "down", "left", "right" | "up", "down", "left", "right" |
| `maxSwipes` | `number` | no | Maximum swipe attempts (default 10) | Số lần vuốt tối đa (mặc định 10) |
| `speed` | `number` | no | Swipe duration in seconds (default 0.3) | Tốc độ vuốt tính bằng giây (mặc định 0.3) |

**Example (Lua/cURL):**

```lua
-- Scroll Settings to find Wi-Fi
local ok, x, y = swipeUntilText("Wi-Fi", "up")
if ok then tap(x, y) end

-- Slow swipe
swipeUntilText("Privacy", "up", 10, 0.8)
```
---

<a id="sec-interact"></a>
## User Interaction

_Tương tác_

Show dialogs for user input during script execution, hash functions, and timestamps.

_Hiện hộp thoại nhập liệu, hàm hash, và timestamp._

### `dialogInput(title, message, default)`

- Type: `func`
- EN: Show text input dialog and wait for user response
- VI: Hiện hộp thoại nhập text và chờ phản hồi
- Return: `string|nil — user input or nil if cancelled`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `title` | `string` | no | Dialog title | Tiêu đề |
| `message` | `string` | no | Description text | Mô tả |
| `default` | `string` | no | Default input text | Text mặc định |

**Example (Lua/cURL):**

```lua
-- Ask for login credentials at runtime
local user = dialogInput("Username", "Enter your username")
if not user then stop() end
local pass = dialogInput("Password", "Enter password")
log("Login as: " .. user)
```
---

### `dialogChoice(title, ...options)`

- Type: `func`
- EN: Show choice dialog with multiple options
- VI: Hiện hộp thoại chọn nhiều lựa chọn
- Return: `string|nil — selected option or nil`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `title` | `string` | yes | Dialog title | Tiêu đề |
| `options` | `string...` | yes | Option strings (variable args) | Các lựa chọn (varargs) |

**Example (Lua/cURL):**

```lua
-- Let user pick script mode
local mode = dialogChoice("Speed", "Fast", "Normal", "Safe")
if mode == "Fast" then
  log("Running in fast mode!")
end
```
---

### `timestamp()`

- Type: `func`
- EN: Get current unix timestamp in milliseconds
- VI: Lấy timestamp unix hiện tại (mili giây)
- Return: `number — milliseconds since epoch`

**Params:** none

**Example (Lua/cURL):**

```lua
-- Measure execution time
local t1 = timestamp()
tap(200, 400)
sleep(1)
local elapsed = timestamp() - t1
log("Took " .. elapsed .. "ms")
```
---

### `md5(string)`

- Type: `func`
- EN: Calculate MD5 hash of a string
- VI: Tính mã băm MD5 của chuỗi
- Return: `string — 32-char hex hash`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `string` | `string` | yes | Input string | Chuỗi đầu vào |

**Example (Lua/cURL):**

```lua
local hash = md5("hello")
log(hash)  -- "5d41402abc4b2a76b9719d911017c592"
```
---

### `showOverlay(data)`

- Type: `func`
- EN: Show transparent stats overlay on screen (touch passes through)
- VI: Hiện bảng thống kê mờ trên màn hình (chạm xuyên qua)
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `data` | `table` | yes | Key-value pairs to display | Bảng key-value hiển thị |

**Example (Lua/cURL):**

```lua
-- Show stats overlay
showOverlay({
  ["Runs"] = "0",
  ["Success"] = "0",
  ["Fails"] = "0"
})

-- Update during automation loop
for i = 1, 100 do
  updateOverlay("Runs", i)
  -- do automation...
  updateOverlay("Success", success)
end

hideOverlay()
```
---

### `updateOverlay(key, value)`

- Type: `func`
- EN: Update a single entry in the overlay
- VI: Cập nhật 1 dòng trong overlay
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `key` | `string` | yes | Stat name | Tên thống kê |
| `value` | `string|number` | yes | New value | Giá trị mới |

**Example (Lua/cURL):**

```lua
updateOverlay("Runs", 42)
updateOverlay("Status", "Running...")
```
---

### `hideOverlay()`

- Type: `func`
- EN: Remove the stats overlay from screen
- VI: Ẩn bảng thống kê
- Return: `void`

**Params:** none

**Example (Lua/cURL):**

```lua
hideOverlay()
```
---

<a id="sec-app"></a>
## App Management

_Quản lý ứng dụng_

Launch, close, and manage apps on the device.

_Mở, đóng và quản lý ứng dụng trên thiết bị._

### `appRun(bundleId)`

- Type: `func`
- EN: Launch an app by bundle ID
- VI: Mở ứng dụng bằng bundle ID
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `bundleId` | `string` | yes | App bundle identifier | Bundle ID ứng dụng |

**Example (Lua/cURL):**

```lua
-- Open Safari and navigate to a URL
appRun("com.apple.safari")
sleep(2)
-- Tap the address bar
tap(214, 52)
sleep(0.5)
inputText("https://google.com")
sleep(0.3)
keyDown("return")
```
**Example (Python):**

```python
# Open Safari and navigate to a URL
app_run("com.apple.safari")
sleep(2)
# Tap the address bar
tap(214, 52)
sleep(0.5)
input_text("https://google.com")
sleep(0.3)
key_down("return")
```
---

### `appKill(bundleId)`

- Type: `func`
- EN: Close/kill a running app
- VI: Đóng/tắt ứng dụng đang chạy
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `bundleId` | `string` | yes | App bundle identifier | Bundle ID ứng dụng |

**Example (Lua/cURL):**

```lua
appKill("com.apple.safari")
```
---

### `appClear(bundleId)`

- Type: `func`
- EN: Clear all app data — kills app, wipes keychain, data container, shared containers, and system caches. App returns to fresh-install state.
- VI: Xóa toàn bộ dữ liệu app — tắt app, xóa keychain, container dữ liệu, shared containers, và cache hệ thống. App trở về trạng thái mới cài.
- Return: `boolean — true if success`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `bundleId` | `string` | yes | App bundle identifier | Bundle ID ứng dụng |

**Example (Lua/cURL):**

```lua
-- Reset Facebook to fresh state
appClear("com.facebook.Facebook")
sleep(2)
appRun("com.facebook.Facebook")
log("Facebook reset done")
```
---

### `appState(bundleId)`

- Type: `func`
- EN: Check if an app is running
- VI: Kiểm tra ứng dụng có đang chạy
- Return: `[object Object]`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `bundleId` | `string` | yes | App bundle identifier | Bundle ID ứng dụng |

**Example (Lua/cURL):**

```lua
-- Restart game if it crashed
local state = appState("com.game.myapp")
if state == 0 then
  log("Game not running, restarting...")
  appRun("com.game.myapp")
  sleep(3)
elseif state == 1 then
  log("Game in background, bringing to front")
  appRun("com.game.myapp")
else
  log("Game is active, continuing script")
end
```
**Example (Python):**

```python
# Restart game if it crashed
state = app_state("com.game.myapp")
if state == 0:
    log("Game not running, restarting...")
    app_run("com.game.myapp")
    sleep(3)
elif state == 1:
    log("Game in background, bringing to front")
    app_run("com.game.myapp")
else:
    log("Game is active, continuing script")
```
---

### `openURL(url)`

- Type: `func`
- EN: Open a URL or URL scheme
- VI: Mở URL hoặc URL scheme
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `url` | `string` | yes | URL to open (http/https or app scheme) | URL cần mở (http/https hoặc scheme ứng dụng) |

**Example (Lua/cURL):**

```lua
openURL("https://google.com")
openURL("tel://123456789")
```
---

<a id="sec-input"></a>
## Text & Input

_Nhập liệu & Bàn phím_

Type text, simulate hardware key presses.

_Nhập văn bản, mô phỏng phím cứng._

### `inputText(text)`

- Type: `func`
- EN: Type text string on device
- VI: Nhập chuỗi văn bản trên thiết bị
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `text` | `string` | yes | Text to type | Văn bản cần nhập |

**Example (Lua/cURL):**

```lua
-- Fill a login form
tap(200, 300)  -- Tap email field
sleep(0.3)
inputText("user@email.com")
sleep(0.2)
tap(200, 400)  -- Tap password field
sleep(0.3)
inputText("mypassword123")
tap(200, 500)  -- Tap login button
```
**Example (Python):**

```python
# Fill a login form
tap(200, 300)  # Tap email field
sleep(0.3)
input_text("user@email.com")
sleep(0.2)
tap(200, 400)  # Tap password field
sleep(0.3)
input_text("mypassword123")
tap(200, 500)  # Tap login button
```
---

### `keyDown(keyType)`

- Type: `func`
- EN: Press a hardware key
- VI: Nhấn phím cứng
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `keyType` | `string` | yes | Key name: home, volumeUp, volumeDown, power | Tên phím: home, volumeUp, volumeDown, power |

**Example (Lua/cURL):**

```lua
keyDown("home")
```
---

### `keyUp(keyType)`

- Type: `func`
- EN: Release a hardware key
- VI: Nhả phím cứng
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `keyType` | `string` | yes | Key name | Tên phím |

**Example (Lua/cURL):**

```lua
keyUp("home")
```
---

### `getClipboard()`

- Type: `func`
- EN: Get clipboard text content
- VI: Lấy nội dung clipboard
- Return: `string`

**Params:** none

**Example (Lua/cURL):**

```lua
-- Copy text from app and log it
longPress(200, 300, 1.0)
sleep(0.5)
tap(250, 260)  -- Tap "Copy" in menu
sleep(0.3)
local text = getClipboard()
log("Copied: " .. text)
```
**Example (Python):**

```python
# Copy text from app and log it
long_press(200, 300, 1.0)
sleep(0.5)
tap(250, 260)  # Tap "Copy" in menu
sleep(0.3)
text = get_clipboard()
log(f"Copied: {text}")
```
---

### `setClipboard(text)`

- Type: `func`
- EN: Set clipboard text content
- VI: Đặt nội dung clipboard
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `text` | `string` | yes | Text to set | Văn bản cần đặt |

**Example (Lua/cURL):**

```lua
-- Paste a promo code into input field
setClipboard("PROMO2024")
tap(200, 300)  -- Focus input
sleep(0.3)
longPress(200, 300, 1.0)
sleep(0.5)
tap(200, 260)  -- Tap "Paste"
```
**Example (Python):**

```python
# Paste a promo code into input field
set_clipboard("PROMO2024")
tap(200, 300)  # Focus input
sleep(0.3)
long_press(200, 300, 1.0)
sleep(0.5)
tap(200, 260)  # Tap "Paste"
```
---

<a id="sec-ui"></a>
## UI & Feedback

_Giao diện & Phản hồi_

Show toast messages, alerts, vibrate, and log output.

_Hiện thông báo toast, alert, rung, và ghi log._

### `toast(message, delay)`

- Type: `func`
- EN: Show temporary notification on device
- VI: Hiện thông báo tạm thời trên thiết bị
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `message` | `string` | yes | Message text | Nội dung thông báo |
| `delay` | `number` | no | Display duration in seconds (default: 2) | Thời gian hiển thị (giây, mặc định: 2) |

**Example (Lua/cURL):**

```lua
toast("Script started!", 3)
```
---

### `alert(message)`

- Type: `func`
- EN: Show alert dialog popup
- VI: Hiện hộp thoại cảnh báo
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `message` | `string` | yes | Alert message | Nội dung cảnh báo |

**Example (Lua/cURL):**

```lua
alert("Are you sure?")
```
---

### `vibrate()`

- Type: `func`
- EN: Vibrate the device
- VI: Rung thiết bị
- Return: `void`

**Params:** none

**Example (Lua/cURL):**

```lua
vibrate()
```
---

### `setDebugVisual(enabled, duration)`

- Type: `func`
- EN: Toggle runtime debug shapes drawn directly on the iPhone screen (separate module, like Toast). OCR / image match -> red bounding box, tap / longPress -> red circle (r=60px), swipe -> red line with endpoint caps. ON by default, auto-fades after `duration` seconds, never blocks touches. Old daemons without TASK_DEBUG_MARK=48 are safely ignored.
- VI: Bật/tắt vẽ debug trực tiếp lên màn hình iPhone (module riêng như Toast). OCR / tìm ảnh có match -> hình chữ nhật đỏ, tap / longPress -> vòng tròn đỏ (r=60px), swipe -> đoạn thẳng đỏ có 2 đầu mút. Mặc định BẬT, tự mờ sau `duration` giây, không chặn cảm ứng. Daemon cũ chưa có TASK_DEBUG_MARK=48 sẽ tự bỏ qua.
- Return: `boolean`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `enabled` | `boolean` | no | true = draw, false = off (default: true) | true = vẽ, false = tắt (mặc định: true) |
| `duration` | `number` | no | Seconds each shape stays (0.3-5, default: 1.5) | Số giây mỗi hình tồn tại (0.3-5, mặc định: 1.5) |

**Example (Lua/cURL):**

```lua
-- Tắt vẽ debug cho script chạy ngầm
setDebugVisual(false)

-- Chỉ hiện 0.8s cho đỡ rối
setDebugVisual(true, 0.8)

tap(200, 300)            -- vòng tròn đỏ tại (200,300)
swipe(200, 600, 200, 200) -- đoạn thẳng đỏ từ (200,600) đến (200,200)
tapText("Login")         -- bbox đỏ quanh chữ + vòng tròn đỏ chỗ tap
clearDebugVisual()       -- xóa ngay mọi hình đang hiện
```
---

### `clearDebugVisual()`

- Type: `func`
- EN: Immediately clear all debug shapes from the screen
- VI: Xóa ngay mọi hình debug đang hiển thị
- Return: `boolean`

**Params:** none

**Example (Lua/cURL):**

```lua
clearDebugVisual()
```
---

### `log(message)`

- Type: `func`
- EN: Log message to console
- VI: Ghi log ra console
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `message` | `string` | yes | Log message | Nội dung log |

**Example (Lua/cURL):**

```lua
log("Step 1 complete ✅")
```
---

<a id="sec-timing"></a>
## Timing & Sleep

_Thời gian & Chờ_

Control script timing with sleep, random delays, and smart waits.

_Điều khiển thời gian script với sleep, delay ngẫu nhiên._

### `sleep(seconds)`

- Type: `func`
- EN: Pause execution for specified seconds
- VI: Tạm dừng thực thi trong khoảng thời gian
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `seconds` | `number` | yes | Wait duration (supports decimals) | Thời gian chờ (hỗ trợ số thập phân) |

**Example (Lua/cURL):**

```lua
sleep(1.5)  -- Wait 1.5 seconds
```
---

### `usleep(microseconds)`

- Type: `func`
- EN: Pause for microseconds (high precision)
- VI: Tạm dừng theo microsecond (độ chính xác cao)
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `microseconds` | `number` | yes | Wait in microseconds | Thời gian chờ (microsecond) |

**Example (Lua/cURL):**

```lua
usleep(500000)  -- Wait 0.5s
```
---

### `randomSleep(min, max)`

- Type: `func`
- EN: Sleep random duration between min and max
- VI: Ngủ ngẫu nhiên trong khoảng min đến max
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `min` | `number` | yes | Minimum seconds | Tối thiểu (giây) |
| `max` | `number` | yes | Maximum seconds | Tối đa (giây) |

**Example (Lua/cURL):**

```lua
randomSleep(0.5, 2.0)  -- Anti-detection
```
---

<a id="sec-screen"></a>
## Screen Info

_Thông tin màn hình_

Get screen dimensions, resolution, and live streaming.

_Lấy kích thước, độ phân giải, và stream trực tiếp._

### `screenSize()`

- Type: `func`
- EN: Get screen dimensions
- VI: Lấy kích thước màn hình
- Return: `table — {width, height}`

**Params:** none

**Example (Lua/cURL):**

```lua
local s = screenSize()
log("Screen: " .. s.width .. "x" .. s.height)
```
---

### `deviceInfo()`

- Type: `func`
- EN: Get device model, iOS version, battery
- VI: Lấy thông tin thiết bị, iOS, pin
- Return: `table — device details`

**Params:** none

**Example (Lua/cURL):**

```lua
local d = deviceInfo()
log(d.model .. " iOS " .. d.version)
```
---

<a id="sec-http"></a>
## HTTP Client

Make HTTP requests from scripts to external APIs.

_Gọi HTTP request từ script đến API bên ngoài._

### `httpGet(url, headers, timeout)`

- Type: `func`
- EN: HTTP GET request
- VI: Gửi yêu cầu HTTP GET
- Return: `body, statusCode`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `url` | `string` | yes | Request URL | URL yêu cầu |
| `headers` | `table` | no | Optional headers {key=value} | Headers tuỳ chọn {key=value} |
| `timeout` | `number` | no | Request timeout in seconds (default 15) | Timeout tính bằng giây (mặc định 15) |

**Example (Lua/cURL):**

```lua
-- Simple GET
local body, status = httpGet("https://api.example.com/data")
log(body)

-- With headers
local body = httpGet("https://api.example.com", {
  ["Authorization"] = "Bearer token123"
})

-- Custom timeout 30s (for slow APIs)
local body = httpGet("https://slow-api.com/data", nil, 30)
```
---

### `httpPost(url, body, headers, timeout)`

- Type: `func`
- EN: HTTP POST request
- VI: Gửi yêu cầu HTTP POST
- Return: `body, statusCode`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `url` | `string` | yes | Request URL | URL yêu cầu |
| `body` | `string` | yes | Request body (string or jsonEncode()) | Nội dung (chuỗi hoặc jsonEncode()) |
| `headers` | `table` | no | Optional headers | Headers tuỳ chọn |
| `timeout` | `number` | no | Request timeout in seconds (default 15) | Timeout tính bằng giây (mặc định 15) |

**Example (Lua/cURL):**

```lua
local body = jsonEncode({username="admin", password="123"})
local resp, status = httpPost(
  "https://api.example.com/login",
  body,
  {["Content-Type"] = "application/json"}
)
log(resp)

-- With 60s timeout for upload
local resp = httpPost(url, largeBody, headers, 60)
```
---

<a id="sec-file"></a>
## File & JSON

_Tệp & JSON_

Read/write files and parse JSON data.

_Đọc/ghi tệp và xử lý dữ liệu JSON._

### `readFile(path)`

- Type: `func`
- EN: Read text file contents
- VI: Đọc nội dung tệp văn bản
- Return: `string`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `path` | `string` | yes | File path | Đường dẫn tệp |

**Example (Lua/cURL):**

```lua
-- Load saved settings
local raw = readFile("/var/mobile/Library/IOSControl/config.json")
local config = jsonDecode(raw)
log("Loops: " .. config.loops)
log("Delay: " .. config.delay .. "s")
```
**Example (Python):**

```python
# Load saved settings
import json
raw = read_file("/var/mobile/Library/IOSControl/config.json")
config = json.loads(raw)
log(f"Loops: {config["loops"]}")
log(f"Delay: {config["delay"]}s")
```
---

### `writeFile(path, content)`

- Type: `func`
- EN: Write string to file
- VI: Ghi chuỗi vào tệp
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `path` | `string` | yes | File path | Đường dẫn tệp |
| `content` | `string` | yes | File content | Nội dung tệp |

**Example (Lua/cURL):**

```lua
-- Save automation results to log
local results = {
  coins = 1500,
  runs = 10,
  time = os.date("%Y-%m-%d %H:%M:%S")
}
writeFile("results.json", jsonEncode(results))
log("Results saved!")
```
**Example (Python):**

```python
# Save automation results to log
import json, time
results = {
    "coins": 1500,
    "runs": 10,
    "time": time.strftime("%Y-%m-%d %H:%M:%S")
}
write_file("results.json", json.dumps(results))
log("Results saved!")
```
---

### `appendFile(path, content)`

- Type: `func`
- EN: Append text to file (creates if not exists)
- VI: Ghi thêm vào cuối file (tạo nếu chưa có)
- Return: `boolean`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `path` | `string` | yes | File path | Đường dẫn tệp |
| `content` | `string` | yes | Text to append | Nội dung ghi thêm |

**Example (Lua/cURL):**

```lua
-- Log results to file
for i = 1, 10 do
  tap(200, 400)
  sleep(1)
  appendFile("log.txt", "Run " .. i .. " done\n")
end
```
---

### `jsonDecode(str)`

- Type: `func`
- EN: Parse JSON string to table
- VI: Phân tích chuỗi JSON sang bảng
- Return: `table`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `str` | `string` | yes | JSON string | Chuỗi JSON |

**Example (Lua/cURL):**

```lua
local t = jsonDecode('{"name":"test"}')
```
---

### `jsonEncode(table)`

- Type: `func`
- EN: Convert table to JSON string
- VI: Chuyển bảng thành chuỗi JSON
- Return: `string`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `table` | `table` | yes | Lua table | Bảng Lua |

**Example (Lua/cURL):**

```lua
local s = jsonEncode({score=100})
```
---

<a id="sec-util"></a>
## Utilities

_Tiện ích_

Random numbers, device info, and miscellaneous tools.

_Số ngẫu nhiên, thông tin thiết bị, và các công cụ khác._

### `randomInt(min, max)`

- Type: `func`
- EN: Random integer in range
- VI: Số nguyên ngẫu nhiên trong khoảng
- Return: `number`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `min` | `number` | yes | Minimum | Tối thiểu |
| `max` | `number` | yes | Maximum | Tối đa |

**Example (Lua/cURL):**

```lua
local x = randomInt(100, 300)
```
---

### `randomFloat(min, max)`

- Type: `func`
- EN: Random float in range
- VI: Số thực ngẫu nhiên trong khoảng
- Return: `number`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `min` | `number` | yes | Minimum | Tối thiểu |
| `max` | `number` | yes | Maximum | Tối đa |

**Example (Lua/cURL):**

```lua
local d = randomFloat(0.1, 0.5)
```
---

### `wifiInfo()`

- Type: `func`
- EN: Get WiFi SSID and IP address
- VI: Lấy SSID WiFi và địa chỉ IP
- Return: `table — {ssid, ip}`

**Params:** none

**Example (Lua/cURL):**

```lua
local w = wifiInfo()
log(w.ip)
```
---

### `setCellularData(enabled, delay)`

- Type: `func`
- EN: Toggle 4G/cellular data on or off
- VI: Bật/tắt dữ liệu di động 4G
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `enabled` | `boolean` | yes | true = on, false = off | true = bật, false = tắt |
| `delay` | `number` | no | Auto-restore after N seconds (optional) | Tự phục hồi sau N giây (tuỳ chọn) |

**Example (Lua/cURL):**

```lua
-- Turn off cellular for 5 seconds then back on
setCellularData(false, 5)

-- Permanently turn off
setCellularData(false)

-- Turn back on
setCellularData(true)
```
---

### `setAirplaneMode(enabled, delay)`

- Type: `func`
- EN: Toggle airplane mode on or off
- VI: Bật/tắt chế độ máy bay
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `enabled` | `boolean` | yes | true = on, false = off | true = bật, false = tắt |
| `delay` | `number` | no | Auto-restore after N seconds (optional) | Tự phục hồi sau N giây (tuỳ chọn) |

**Example (Lua/cURL):**

```lua
-- Reset network: airplane on 3s then off
setAirplaneMode(true, 3)
sleep(4)
log("Network reset complete")
```
---

### `getIP()`

- Type: `func`
- EN: Get public IP address (via api.ipify.org)
- VI: Lấy IP công cộng (qua api.ipify.org)
- Return: `string — public IP address`

**Params:** none

**Example (Lua/cURL):**

```lua
-- Check IP before and after airplane mode
local ip1 = getIP()
log("Before: " .. ip1)
setAirplaneMode(true, 3)
sleep(5)
local ip2 = getIP()
log("After: " .. ip2)
```
---

### `setProxySystem(host, port)`

- Type: `func`
- EN: Set device-wide Wi-Fi proxy (all apps). IP and Port only.
- VI: Đặt proxy toàn thiết bị qua Wi-Fi (TẤT CẢ app). Chỉ hỗ trợ IP và Port.
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `host` | `string` | yes | Proxy IP | IP Proxy |
| `port` | `number` | yes | Proxy Port | Cổng Proxy |

**Example (Lua/cURL):**

```lua
-- Reset connections after setting proxy
setProxySystem("160.25.77.31", 8770)
setAirplaneMode(true)
sleep(1)
setAirplaneMode(false)
```
---

### `clearProxySystem()`

- Type: `func`
- EN: Disable device-wide Wi-Fi proxy. Restores direct connection.
- VI: Tắt proxy hệ thống Wi-Fi. Khôi phục kết nối trực tiếp.
- Return: `void`

**Params:** none

**Example (Lua/cURL):**

```lua
clearProxySystem()
log("Proxy removed")
```
---

<a id="sec-record"></a>
## Record & Playback

_Ghi & Phát lại_

Record touch actions and replay them as scripts.

_Ghi lại thao tác chạm và phát lại dưới dạng script._

### `recordStart()`

- Type: `func`
- EN: Start recording touch events
- VI: Bắt đầu ghi sự kiện chạm
- Return: `void`

**Params:** none

**Example (Lua/cURL):**

```lua
-- Record a login flow and save it
log("Recording started... perform actions on device")
recordStart()
sleep(10)  -- Wait for user to perform actions
local events = recordStop()
log("Recorded " .. #events .. " events")
recordSave("login_flow")
log("Saved as login_flow")
```
**Example (Python):**

```python
# Record a login flow and save it
log("Recording started... perform actions")
record_start()
sleep(10)  # Wait for user actions
events = record_stop()
log(f"Recorded {len(events)} events")
record_save("login_flow")
log("Saved as login_flow")
```
---

### `recordStop()`

- Type: `func`
- EN: Stop recording and save events
- VI: Dừng ghi và lưu sự kiện
- Return: `table — recorded events`

**Params:** none

**Example (Lua/cURL):**

```lua
local events = recordStop()
```
---

### `recordPlay(events)`

- Type: `func`
- EN: Replay recorded events
- VI: Phát lại sự kiện đã ghi
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `events` | `table` | yes | Events from recordStop() | Sự kiện từ recordStop() |

**Example (Lua/cURL):**

```lua
recordPlay(events)
```
---

### `recordSave(name)`

- Type: `func`
- EN: Save recording to file
- VI: Lưu bản ghi vào tệp
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `name` | `string` | yes | Recording name | Tên bản ghi |

**Example (Lua/cURL):**

```lua
recordSave("login_flow")
```
---

### `recordLoad(name)`

- Type: `func`
- EN: Load recording from file
- VI: Tải bản ghi từ tệp
- Return: `table — events`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `name` | `string` | yes | Recording name | Tên bản ghi |

**Example (Lua/cURL):**

```lua
local e = recordLoad("login_flow")
recordPlay(e)
```
---

<a id="sec-schedule"></a>
## Scheduler

_Lập lịch_

Schedule scripts to run at specific times or on events.

_Lập lịch chạy script vào thời điểm cụ thể hoặc theo sự kiện._

### `schedule(cron, script)`

- Type: `func`
- EN: Schedule script with cron expression
- VI: Lập lịch script bằng biểu thức cron
- Return: `string — schedule ID`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `cron` | `string` | yes | Cron expression (e.g. "0 8 * * *") | Biểu thức cron (VD: "0 8 * * *") |
| `script` | `string` | yes | Script filename | Tên tệp script |

**Example (Lua/cURL):**

```lua
-- Run daily farm at 8 AM
local id = schedule("0 8 * * *", "daily_farm.lua")
log("Scheduled daily farm, ID: " .. id)

-- Run every 30 minutes
schedule("*/30 * * * *", "check_energy.lua")
```
**Example (Python):**

```python
# Run daily farm at 8 AM
id = schedule("0 8 * * *", "daily_farm.lua")
log(f"Scheduled daily farm, ID: {id}")

# Run every 30 minutes
schedule("*/30 * * * *", "check_energy.lua")
```
---

### `scheduleAfter(seconds, script)`

- Type: `func`
- EN: Run script after delay
- VI: Chạy script sau khoảng thời gian
- Return: `string — schedule ID`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `seconds` | `number` | yes | Delay in seconds | Thời gian trì hoãn (giây) |
| `script` | `string` | yes | Script filename | Tên tệp script |

**Example (Lua/cURL):**

```lua
scheduleAfter(3600, "hourly.lua")
```
---

### `onNotification(app, action)`

- Type: `func`
- EN: Trigger action on push notification
- VI: Kích hoạt hành động khi có thông báo đẩy
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `app` | `string` | yes | App bundle ID | Bundle ID ứng dụng |
| `action` | `function` | yes | Callback function | Hàm callback |

**Example (Lua/cURL):**

```lua
-- Auto-reply when WhatsApp notification arrives
onNotification("net.whatsapp.WhatsApp", function(info)
  log("New message from: " .. info.title)
  appRun("net.whatsapp.WhatsApp")
  sleep(2)
  -- Tap the notification chat
  tap(200, 100)
  sleep(1)
  inputText("Auto-reply: I'm busy right now")
  tap(380, 800)  -- Send button
end)
```
**Example (Python):**

```python
# Auto-reply when WhatsApp notification arrives
def on_msg(info):
    log(f"New message from: {info["title"]}")
    app_run("net.whatsapp.WhatsApp")
    sleep(2)
    tap(200, 100)  # Tap notification chat
    sleep(1)
    input_text("Auto-reply: I'm busy right now")
    tap(380, 800)  # Send button

on_notification("net.whatsapp.WhatsApp", on_msg)
```
---

<a id="sec-rest"></a>
## HTTP APIs

Control IOSControl remotely via HTTP endpoints. All endpoints are on the iPhone daemon at port 9999.

_Điều khiển IOSControl từ xa qua HTTP. Tất cả endpoint chạy trên daemon iPhone port 9999._

### `POST /api/scripts/run`

- Type: `post`
- EN: Play a script — execute Lua code on the device
- VI: Chạy script — thực thi code Lua trên thiết bị
- Return: `JSON {success, taskId}`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `code` | `string` | yes | Lua code to execute | Code Lua cần thực thi |
| `scriptName` | `string` | no | Script filename (for tracking) | Tên file script (để theo dõi) |

**Example (Lua/cURL):**

```bash
curl -X POST http://{device-ip}:9999/api/scripts/run \\
  -H "Content-Type: application/json" \\
  -d '{"code":"tap(100,200)\nsleep(1)\nlog(\"done\")", "scriptName":"test.lua"}'
```
---

### `POST /api/scripts/stop`

- Type: `post`
- EN: Stop playing a script — sends stop signal to running script
- VI: Dừng script đang chạy — gửi tín hiệu dừng
- Return: `JSON {success, message}`

**Params:** none

**Example (Lua/cURL):**

```bash
curl -X POST http://{device-ip}:9999/api/scripts/stop
```
---

### `GET /api/scripts/running`

- Type: `get`
- EN: Check if a script is currently running
- VI: Kiểm tra script có đang chạy không
- Return: `JSON {running, taskId, scriptName}`

**Params:** none

**Example (Lua/cURL):**

```bash
curl http://{device-ip}:9999/api/scripts/running

# Response: {"running":true,"taskId":"ABC-123","scriptName":"bot.lua"}
```
---

### `GET /api/scripts/{taskId}/status`

- Type: `get`
- EN: Get script execution status and logs
- VI: Lấy trạng thái thực thi và log của script
- Return: `JSON {success, status, logs, error}`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `taskId` | `string` | yes | Task ID returned from /run | Task ID trả về từ /run |

**Example (Lua/cURL):**

```bash
curl http://{device-ip}:9999/api/scripts/ABC-123/status

# Response: {"success":true,"status":"done","logs":[{"message":"done"}]}
```
---

### `GET /api/scripts/files`

- Type: `get`
- EN: List files in scripts directory
- VI: Liệt kê file trong thư mục scripts
- Return: `JSON {success, files: [{name, size, modified}]}`

**Params:** none

**Example (Lua/cURL):**

```bash
curl http://{device-ip}:9999/api/scripts/files
```
---

### `GET /api/scripts/load`

- Type: `get`
- EN: Load a script file content
- VI: Đọc nội dung file script
- Return: `JSON {success, name, code}`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `name` | `string` | yes | Script filename | Tên file script |

**Example (Lua/cURL):**

```bash
curl "http://{device-ip}:9999/api/scripts/load?name=bot.lua"
```
---

### `POST /api/scripts/save`

- Type: `post`
- EN: Create or update a script file
- VI: Tạo hoặc cập nhật file script
- Return: `JSON {success, name}`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `name` | `string` | yes | Script filename | Tên file script |
| `code` | `string` | yes | Script content | Nội dung script |

**Example (Lua/cURL):**

```bash
curl -X POST http://{device-ip}:9999/api/scripts/save \\
  -H "Content-Type: application/json" \\
  -d '{"name":"bot.lua","code":"tap(100,200)"}'
```
---

### `POST /api/scripts/delete`

- Type: `post`
- EN: Delete a script file
- VI: Xóa file script
- Return: `JSON {success}`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `name` | `string` | yes | Script filename to delete | Tên file script cần xóa |

**Example (Lua/cURL):**

```bash
curl -X POST http://{device-ip}:9999/api/scripts/delete \\
  -H "Content-Type: application/json" \\
  -d '{"name":"old_script.lua"}'
```
---

### `GET /ping`

- Type: `get`
- EN: Health check — verify daemon is running
- VI: Kiểm tra daemon đang chạy
- Return: `JSON {status, version, name, ip}`

**Params:** none

**Example (Lua/cURL):**

```bash
curl http://{device-ip}:9999/ping

# Response: {"status":"ok","version":"1.0.0","name":"IOSControl","ip":"192.168.1.x"}
```
---

<a id="sec-crane"></a>
## Crane Containers

Manage Crane app containers — multi-account, backup, clear data while keeping login. Requires Crane tweak by opa334.

_Quản lý container Crane — đa tài khoản, backup, xóa data giữ đăng nhập. Cần cài tweak Crane (opa334)._

### `crane.list(bundleId?)`

- Type: `func`
- EN: List Crane containers for an app
- VI: Liệt kê container Crane của app
- Return: `[object Object]`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `bundleId` | `string` | no | App bundle ID (optional — omit to list all apps) | Bundle ID app (tuỳ chọn — bỏ để liệt kê tất cả app) |

**Example (Lua/cURL):**

```lua
-- List containers for Facebook
local containers = crane.list("com.facebook.Facebook")
for i, c in ipairs(containers) do
  log(c.name .. " (" .. c.id .. ") default=" .. tostring(c.isDefault))
end

-- List all apps with containers
local apps = crane.list()
for _, app in ipairs(apps) do log(app.bundleId) end
```
---

### `crane.switch(bundleId, name)`

- Type: `func`
- EN: Switch active container
- VI: Chuyển container đang hoạt động
- Return: `boolean`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `bundleId` | `string` | yes | App bundle ID | Bundle ID app |
| `name` | `string` | yes | Container name or UUID | Tên container hoặc UUID |

**Example (Lua/cURL):**

```lua
crane.switch("com.facebook.Facebook", "Account1")
sleep(2)
appRun("com.facebook.Facebook")
```
---

### `crane.create(bundleId, name)`

- Type: `func`
- EN: Create a new container
- VI: Tạo container mới
- Return: `boolean, string?`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `bundleId` | `string` | yes | App bundle ID | Bundle ID app |
| `name` | `string` | yes | New container name | Tên container mới |

**Example (Lua/cURL):**

```lua
local ok, err = crane.create("com.facebook.Facebook", "FB_Account2")
if ok then log("Created!") else log("Error: " .. err) end
```
---

### `crane.delete(bundleId, name)`

- Type: `func`
- EN: Delete a container (data lost)
- VI: Xóa container (mất dữ liệu)
- Return: `boolean`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `bundleId` | `string` | yes | App bundle ID | Bundle ID app |
| `name` | `string` | yes | Container name or UUID | Tên container hoặc UUID |

**Example (Lua/cURL):**

```lua
crane.delete("com.facebook.Facebook", "OldAccount")
```
---

### `crane.wipe(bundleId, name)`

- Type: `func`
- EN: Full wipe — data + keychain
- VI: Xoá toàn bộ — data + keychain
- Return: `boolean`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `bundleId` | `string` | yes | App bundle ID | Bundle ID app |
| `name` | `string` | yes | Container name or UUID | Tên container hoặc UUID |

**Example (Lua/cURL):**

```lua
-- Full wipe: removes all data including login
crane.wipe("com.facebook.Facebook", "Account1")
```
---

### `crane.rename(bundleId, old, new)`

- Type: `func`
- EN: Rename a container
- VI: Đổi tên container
- Return: `boolean`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `bundleId` | `string` | yes | App bundle ID | Bundle ID app |
| `oldName` | `string` | yes | Current name | Tên hiện tại |
| `newName` | `string` | yes | New name | Tên mới |

**Example (Lua/cURL):**

```lua
crane.rename("com.facebook.Facebook", "Test1", "MainAccount")
```
---

### `crane.clearData(bundleId)`

- Type: `func`
- EN: Clear caches but KEEP login — reduce storage without logout
- VI: Xóa cache nhưng GIỮ đăng nhập — giảm dung lượng không bị logout
- Return: `[object Object]`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `bundleId` | `string` | yes | App bundle ID | Bundle ID app |

**Example (Lua/cURL):**

```lua
-- FB grows to 500MB after browsing → clear back to ~15MB, still logged in!
local ok, count = crane.clearData("com.facebook.Facebook")
log("Cleared " .. count .. " directories")

-- Clears: Caches, WebKit, SplashBoard, tmp
-- Keeps: Keychain, Preferences, Cookies
```
---

### `crane.backup(bundleId, container?, name?)`

- Type: `func`
- EN: Backup container as tar.gz
- VI: Backup container thành tar.gz
- Return: `boolean, string — success and backup file path`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `bundleId` | `string` | yes | App bundle ID | Bundle ID app |
| `containerName` | `string` | no | Container name (optional) | Tên container (tuỳ chọn) |
| `backupName` | `string` | no | Backup filename prefix | Tiền tố tên file backup |

**Example (Lua/cURL):**

```lua
local ok, path = crane.backup("com.facebook.Facebook", nil, "fb_main")
log("Saved: " .. path)
-- → /var/mobile/Library/IOSControl/Backups/fb_main_20260513_143000.tar.gz
```
---

### `crane.restore(bundleId, path)`

- Type: `func`
- EN: Restore from tar.gz backup
- VI: Khôi phục từ backup tar.gz
- Return: `boolean`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `bundleId` | `string` | yes | App bundle ID | Bundle ID app |
| `backupPath` | `string` | yes | Full path to .tar.gz | Đường dẫn đầy đủ tới .tar.gz |

**Example (Lua/cURL):**

```lua
crane.restore("com.facebook.Facebook",
  "/var/mobile/Library/IOSControl/Backups/fb_main_20260513_143000.tar.gz")
```
---

### `crane.size(bundleId)`

- Type: `func`
- EN: Get container size breakdown
- VI: Xem chi tiết dung lượng container
- Return: `[object Object]`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `bundleId` | `string` | yes | App bundle ID | Bundle ID app |

**Example (Lua/cURL):**

```lua
local s = crane.size("com.facebook.Facebook")
log("Total: " .. string.format("%.1f", s.total/1024/1024) .. " MB")
log("Caches: " .. string.format("%.1f", s.caches/1024/1024) .. " MB")
log("WebKit: " .. string.format("%.1f", s.webkit/1024/1024) .. " MB")

-- Auto-clear if cache > 100MB
if s.caches > 100 * 1024 * 1024 then
  crane.clearData("com.facebook.Facebook")
end
```
---

<a id="sec-spoof"></a>
## Device Spoofing

_Giả lập thiết bị_

Spoof device identity per-app — model, iOS version, carrier, timezone. Requires paid license for spoof.app().

_Giả lập danh tính thiết bị theo app — model, iOS, nhà mạng, timezone. spoof.app() yêu cầu license trả phí._

### `spoof.app(bundleID)`

- Type: `func`
- EN: Quick-spoof: random device profile for target app. Requires paid license.
- VI: Spoof nhanh: random profile thiết bị cho app. Yêu cầu license trả phí.
- Return: `[object Object]`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `bundleID` | `string` | yes | Target app bundle ID | Bundle ID app đích |

**Example (Lua/cURL):**

```lua
-- Random device for Pokemon GO\nlocal info = spoof.app("com.nianticlabs.pokemongo")\nlog("Spoofed as: " .. info.name .. " iOS " .. info.version)\n-- → iPhone 16 Pro Max iOS 18.3.1\n\nappRun("com.nianticlabs.pokemongo")
```
---

### `spoof.app(bundleID, ios, model)`

- Type: `func`
- EN: Specific-spoof: set exact iOS version and model for target app. Requires paid license.
- VI: Spoof cụ thể: chọn chính xác iOS và model cho app. Yêu cầu license trả phí.
- Return: `[object Object]`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `bundleID` | `string` | yes | Target app bundle ID | Bundle ID app đích |
| `ios` | `string` | yes | iOS version (e.g. "18.3.1") | Phiên bản iOS (vd "18.3.1") |
| `model` | `string` | yes | ProductType or name (e.g. "iPhone16,2" or "iPhone 15 Pro Max") | ProductType hoặc tên (vd "iPhone16,2" hoặc "iPhone 15 Pro Max") |

**Example (Lua/cURL):**

```lua
-- Specific: iPhone 16 Pro Max on iOS 18.3.1\nlocal info = spoof.app("com.facebook.Facebook", "18.3.1", "iPhone17,2")\nlog(info.model)   -- "iPhone17,2"\nlog(info.name)    -- "iPhone 16 Pro Max"\nlog(info.version) -- "18.3.1"\n\n-- Also accepts device name:\nspoof.app("com.facebook.Facebook", "18.0", "iPhone 15 Pro")
```
---

### `spoof.name(name)`

- Type: `func`
- EN: Set fake device name (UIDevice.name)
- VI: Đặt tên thiết bị giả (UIDevice.name)
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `name` | `string|nil` | yes | Device name or nil to clear | Tên thiết bị hoặc nil để xoá |

**Example (Lua/cURL):**

```lua
spoof.name("iPhone 15 Pro")\n-- Clear:\nspoof.name(nil)
```
---

### `spoof.version(ios)`

- Type: `func`
- EN: Set fake iOS version
- VI: Đặt phiên bản iOS giả
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `ios` | `string|nil` | yes | iOS version or nil to clear | Phiên bản iOS hoặc nil để xoá |

**Example (Lua/cURL):**

```lua
spoof.version("18.3.1")
```
---

### `spoof.carrier(carrier)`

- Type: `func`
- EN: Set fake carrier (name or full table with mcc/mnc)
- VI: Đặt nhà mạng giả (tên hoặc bảng đầy đủ mcc/mnc)
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `carrier` | `string|table` | yes | Carrier name or {name, iso, mcc, mnc} | Tên nhà mạng hoặc {name, iso, mcc, mnc} |

**Example (Lua/cURL):**

```lua
-- Simple:\nspoof.carrier("Viettel")\n\n-- Full (consistent MCC/MNC):\nspoof.carrier({name="Viettel", iso="vn", mcc="452", mnc="04"})
```
---

### `spoof.timezone(tz)`

- Type: `func`
- EN: Set fake timezone
- VI: Đặt timezone giả
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `tz` | `string|nil` | yes | IANA timezone (e.g. America/New_York) | Timezone IANA (vd America/New_York) |

**Example (Lua/cURL):**

```lua
spoof.timezone("America/New_York")
```
---

### `spoof.target(bundleID)`

- Type: `func`
- EN: Add app to spoof target list (only these apps get spoofed)
- VI: Thêm app vào danh sách target (chỉ các app này bị spoof)
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `bundleID` | `string` | yes | App bundle ID to target | Bundle ID app cần target |

**Example (Lua/cURL):**

```lua
spoof.target("com.facebook.Facebook")\nspoof.target("com.instagram.Istanbul")
```
---

### `spoof.webrtc(allow)`

- Type: `func`
- EN: Block or allow WebRTC (prevents IP leak)
- VI: Chặn hoặc cho phép WebRTC (chống lộ IP)
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `allow` | `boolean` | yes | false = block, true = allow | false = chặn, true = cho phép |

**Example (Lua/cURL):**

```lua
spoof.webrtc(false)  -- Block WebRTC leak
```
---

### `spoof.webgl(allow)`

- Type: `func`
- EN: Block or allow WebGL (prevents GPU fingerprint)
- VI: Chặn hoặc cho phép WebGL (chống fingerprint GPU)
- Return: `void`

**Params:**

| Name | Type | Required | EN | VI |
|---|---|---|---|---|
| `allow` | `boolean` | yes | false = block, true = allow | false = chặn, true = cho phép |

**Example (Lua/cURL):**

```lua
spoof.webgl(false)  -- Block WebGL fingerprint
```
---

### `spoof.reset()`

- Type: `func`
- EN: Clear all spoof config — restore original device identity
- VI: Xoá toàn bộ config spoof — khôi phục danh tính gốc
- Return: `void`

**Params:** none

**Example (Lua/cURL):**

```lua
-- Done with spoofing, restore original\nspoof.reset()
```
---

