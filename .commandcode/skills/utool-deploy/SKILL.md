---
name: utool-deploy
description: Phát hành một phiên bản mới cho repo utouch/ZXTouch — đối chiếu commit kể từ tag gần nhất, viết CHANGELOG, bump version ở mọi nguồn khai báo, commit "Release vX.Y.Z", push main, tạo tag annotated và để CI dựng GitHub Release + publish APT repo. Dùng khi người dùng yêu cầu "phát hành version", "release", "bump version", "tạo changelog rồi push/tag/release" cho project này.
argument-hint: "[version] (mặc định: tăng patch so với tag gần nhất)"
---

# Phát hành ZXTouch (utouch)

Quy trình phát hành của repo này đã cố định — làm đúng theo đây, không tự nghĩ ra quy
trình mới và không tạo GitHub Release bằng tay (CI làm).

## Quy ước bắt buộc

- Tăng **patch**: `v0.3.34` → `v0.3.35` (trừ khi người dùng chỉ định khác).
- `CHANGELOG.md` viết **tiếng Việt**, theo *Keep a Changelog*, mục `Đã thêm` /
  `Đã thay đổi` / `Đã sửa` / `Đã loại bỏ`, ngày dạng `YYYY-MM-DD`, có link so sánh.
- Commit tiêu đề đúng mẫu `Release vX.Y.Z`; tag là **annotated tag** cùng tên
  (`git tag -a vX.Y.Z -m "Release vX.Y.Z"`).
- CI lo build + release + APT. Không sửa tay `docs/Packages*`, `docs/Release`,
  `docs/debs/` — các file này do workflow `apt-repo.yml` sinh ra.
- Chỉ commit đúng các file của lần phát hành; để nguyên file untracked khác trong
  working tree.

## Bước 0 — Khảo sát hiện trạng

```powershell
git tag --sort=-v:refname | Select-Object -First 5   # tag gần nhất
git log --oneline vX.Y.Z..HEAD                        # commit kể từ tag đó
git status --short                                    # có gì đang dở không
git diff --stat vX.Y.Z..HEAD
```

Với mỗi commit, đọc kỹ để viết changelog: `git show <hash>` (hoặc `--stat` trước khi
xem diff dài). Lưu ý hai loại commit **không** đưa vào changelog vì không mang thay
đổi người dùng: commit `APT repo: publish vX.Y.Z to GitHub Pages` (do CI sinh) và các
commit chỉ dọn `.gitignore`.

Nếu repo đang có thay đổi chưa commit chưa rõ nguồn gốc, hỏi lại trước khi làm tiếp.

## Bước 1 — Viết mục CHANGELOG

- Thêm khối `## [X.Y.Z] — YYYY-MM-DD` ngay dưới `## [Unreleased]` (giữ `[Unreleased]`
  rỗng, không xoá).
- Chuyển mọi mục đang nằm trong `[Unreleased]` xuống bản mới, rồi bổ sung mục cho các
  commit còn lại.
- Mỗi mục nêu rõ hành vi trước → sau, tên endpoint/hàm/hằng số liên quan; tránh mô tả
  chung chung.
- Thêm link so sánh vào đầu danh sách link ở cuối file (danh sách đang xếp giảm dần):

```markdown
[0.3.35]: https://github.com/chiconghvan/utouch/compare/v0.3.34...v0.3.35
```

## Bước 2 — Bump version ở mọi nguồn khai báo

Đổi `X.Y.Z cũ` → `X.Y.Z mới` tại **đủ 9 vị trí**:

| File | Ghi chú |
|---|---|
| `control` | `Version:` |
| `appdelegate/control` | `Version:` |
| `pccontrol/control` | `Version:` |
| `zxtouch/shortcutextUI/Info.plist` | `CFBundleShortVersionString` |
| `zxtouch/zxtouchTests/Info.plist` | `CFBundleShortVersionString` |
| `zxtouch/zxtouchUITests/Info.plist` | `CFBundleShortVersionString` |
| `zxtouch/zxtouch.xcodeproj/project.pbxproj` | `MARKETING_VERSION` — **4 chỗ**, dùng `replace_all` |
| `zxtouch/zxtouch/Settings/SettingsPageViewController.m` | nhãn `@"ZXTouch Rootless X.Y.Z"` |

Các file **không** sửa: `docs/Packages`, `docs/Packages.gz`, `docs/Packages.bz2`,
`docs/Release`, `docs/debs/*` (CI sinh), `CHANGELOG.md` (giữ nguyên version cũ trong
các mục lịch sử).

## Bước 3 — Kiểm tra trước khi commit

```powershell
python -m pytest tools/tests -q                     # phải xanh
Grep "0\.3\.3[0-9]" --glob "!docs/**"                # chỉ còn CHANGELOG.md là đúng
git status --short                                   # đúng 9 file modified
```

Nếu còn chuỗi version cũ ngoài `CHANGELOG.md` thì tìm và bump nốt.

Ngoài phạm vi version, trước khi commit cũng kiểm hai quy ước hay bị bỏ sót của repo:
`layout/Applications/zxtouch.app/index.html` phải trùng `zxtouch/zxtouch/http/index.html`
(so bằng `Compare-Object`), và thay đổi hành vi hàm prelude phải kèm cập nhật
`docs/IDE/ioscontrol.md` trong cùng commit.

## Bước 4 — Commit

```powershell
git add -u                                          # chỉ file đã tracked, không nuốt file lạ
git commit -F "$env:COMMANDCODE_SCRATCHPAD\release-commit.txt"
```

`git add -u` là chủ ý: các thư mục untracked (`.commandcode/`, ảnh chụp, log) phải
nằm ngoài commit phát hành.

Nội dung commit (ghi ra file tạm rồi truyền bằng `-F`, đừng nhồi nhiều `-m`):

```
Release vX.Y.Z

Bump package/app version to X.Y.Z across Debian control files, Xcode MARKETING_VERSION and Info.plists, and refresh the Settings > About label from <cũ> to <mới>.

Changelog for the commits since v<cũ>: <2-3 câu tóm tắt các thay đổi người dùng>.

Co-authored-by: CommandCodeBot <noreply@commandcode.ai>
```

## Bước 5 — Push main rồi đẩy tag

```powershell
git push origin main
git tag -a vX.Y.Z -m "Release vX.Y.Z"
git push origin vX.Y.Z
```

PowerShell hiển thị stderr của git thành khối `NativeCommandError` — đừng vội kết luận
là lỗi, hãy đọc dòng `9204255..65af70f  main -> main` và `* [new tag] vX.Y.Z -> vX.Y.Z`.
Xác nhận bằng `git status -sb` (phải là `## main...origin/main`, không còn `ahead`).

Push và tạo release là hành động công khai — chỉ làm khi người dùng đã yêu cầu phát hành.

## Bước 6 — Theo dõi CI

Push tag kích hoạt `build.yml` (macos-latest) → dựng rootless + roothide `.deb`, tạo
GitHub Release kèm release notes sinh tự động; release đó lại kích hoạt `apt-repo.yml`
→ publish vào `docs/` rồi tự push commit `APT repo: publish vX.Y.Z to GitHub Pages`.
Một run cho `main` cũng chạy song song nhưng không tạo release — chỉ run theo tag mới có.

```powershell
gh run list --limit 8                               # tìm run "Build ZXTouch Package" theo tag vX.Y.Z
gh run watch <run-id> --exit-status                 # mất khoảng 5 phút
```

Chạy `gh run watch` ở chế độ nền rồi `shell_output({id, wait: "exit"})` để không chặn
vòng lặp. Sau khi run xanh, kiểm tiếp run `Publish APT repo to GitHub Pages`.

## Bước 7 — Xác nhận và đồng bộ

```powershell
gh release view vX.Y.Z --json tagName,name,body,assets
git pull --ff-only origin main                      # lấy commit publish APT do CI đẩy lên
```

Đối chiếu: release có đúng 2 asset `.deb` (`_rootless`, `_roothide`), body có bảng
hướng dẫn cài và link `compare/v<cũ>...vX.Y.Z`; `docs/Packages` trên main đã mang
version mới.

Báo cáo lại bằng tiếng Việt: commit hash, tag, link release, link compare, và ví dụ
thực tế (asset/version mới) để người dùng đối chiếu.

## Bẫy thường gặp

- **Chỉ sửa `control` gốc**: build đóng gói theo `pccontrol/control` — thiếu file này
  thì `.deb` mang version cũ.
- **Bỏ tag annotated**: `git push --tags` với tag nhẹ vẫn tạo release nhưng lệch
  convention; luôn `git tag -a`.
- **Sửa `docs/Packages` bằng tay**: sẽ xung đột với commit CI đẩy lên ngay sau đó.
- **Commit lẫn file lạ**: dùng `git add -u`, không `git add -A`.
- **Coi khối CLIXML/NativeCommandError của PowerShell là lỗi push**: nó chỉ là stderr;
  xác nhận bằng `git status -sb`.
