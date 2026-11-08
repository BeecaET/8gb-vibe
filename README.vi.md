# 8GB Vibe

*Vibe coding on a budget Mac.*

[English](README.md) | Tiếng Việt

**Miễn phí 100%.** Tải tại [8gb.beeca.vn](https://8gb.beeca.vn). Một sản phẩm của BEECA.

Trợ lý cho người vibe code trên máy Mac 8 GB. App thanh menu cho macOS, giúp máy cấu hình thấp (MacBook Air M2, 8 GB RAM) chạy mượt khi làm việc nặng: nhiều phiên Claude Code, Xcode, Gradle, Docker.

- Chức năng và lộ trình: [docs/CHUC_NANG.md](docs/CHUC_NANG.md)
- Trạng thái: **MVP 1 (chỉ xem)** xong, cộng phần **thoát app** của MVP 2, trang Agent AI và Dev server. Chưa có dọn cache, chế độ làm việc, hàng đợi build.
- App không tự tắt hay xoá gì. Mọi lần thoát app đều do người dùng chọn và xác nhận.

## Có gì

| Phần | Nội dung |
|---|---|
| Thanh menu | Vòng tròn đầy theo % RAM, màu theo mức căng (xanh, cam, đỏ), kèm số swap. |
| Popover | 3 đồng hồ RAM, swap, ổ; biểu đồ swap 1 giờ; top 3 nhóm; tổng RAM giải phóng được. |
| Tổng quan | RAM, swap, ổ trống, tải; biểu đồ swap; gợi ý; trạng thái các ngưỡng. |
| Bộ nhớ | Ngân sách RAM; bảng nhóm công việc (Claude, Xcode, Android, Docker...) mở rộng được. |
| Agent AI | Nhóm Vibe. Agent dòng lệnh (Claude Code, Codex CLI, Gemini CLI...) theo từng phiên, app AI, IDE có AI. Ước tính sơ bộ còn chỗ cho khoảng bao nhiêu phiên theo ngân sách RAM (không bảo đảm không swap); báo khi máy đã thiếu RAM. |
| Dev server | Server đang mở cổng (Next.js, Vite, Python...): dự án, cổng, cổng mở ra mạng, ai đã chạy, RAM, rảnh bao lâu. Đánh dấu tiến trình mồ côi (agent hay Terminal đã đóng nhưng server vẫn chạy). Chuột phải để mở trình duyệt hoặc dừng, qua hộp xác nhận. |
| Tiến trình | Bảng tất cả tiến trình, sắp xếp, tìm kiếm, có nhóm. |
| Ổ đĩa | Đo dung lượng cache và dữ liệu lớn đã biết, chia mức an toàn, cần xem, của app khác. |
| Chạy nền | Dịch vụ tự chạy khi khởi động (LaunchAgents, LaunchDaemons). |
| Cài đặt | Ngưỡng cảnh báo, kiểu hiển thị thanh menu, thông báo, mở cùng máy. |
| Dọn RAM | Danh sách app, Simulator, Gradle daemon, emulator đang chiếm RAM. Gợi ý thứ rảnh trên 30 phút. Chọn rồi thoát, qua hộp xác nhận. App không chịu đóng sau 10 giây thì cho buộc thoát (xác nhận lần hai). |
| Tiến trình | Chuột phải vào tiến trình của bạn để thoát (qua hộp xác nhận). |
| Nhật ký | Ghi mọi lần thoát: thời điểm, đối tượng, RAM, kết quả. Tệp: `~/Library/Application Support/8GB Vibe/nhat-ky.jsonl`. |
| Thông báo | "Máy đang chậm" kèm gợi ý nên tắt gì; bấm vào thì mở trang Dọn RAM. Báo thêm khi ổ gần đầy, quá nhiều phiên Claude Code. Mỗi loại tối đa 30 phút một lần. |

Không cho thoát từ app: chính app này, Finder, Dock, app Claude (đóng sẽ ngắt mọi phiên Claude Code). Phiên Claude Code chỉ gợi ý lưu trữ trong app Claude.

Có thêm: điểm sức khoẻ máy (0 đến 100), icon thật của từng app, trang Giới thiệu và bản quyền.

## Build và chạy

Không cần mở Xcode. Bản dùng thử trên máy này (ký ad-hoc):

```bash
./scripts/package.sh
```

```bash
open "build/8GB Vibe.app"
```

## Phát hành

Bản phát hành: universal (Apple Silicon và Intel), ký Developer ID, hardened runtime, notarize, đóng gói DMG.

Bản phát hành cần chứng chỉ Developer ID của BEECA và hồ sơ notarize, nên chỉ nhóm bảo trì chạy. Tạo hồ sơ một lần (lưu mật khẩu ứng dụng của Apple ID vào Keychain):

```bash
xcrun notarytool store-credentials <tên hồ sơ> --apple-id <email> --team-id 59SQ2V25T2
```

Build bản phát hành:

```bash
NOTARY_PROFILE=<hồ sơ> ./scripts/release.sh
```

Kết quả: `build/release/8GB-Vibe-<phiên bản>.dmg` và tệp `.sha256`. Phiên bản đọc từ tệp `VERSION`, số build là số commit.

Chạy test phần lõi:

```bash
swift test -j 2
```

Tham số khi kiểm thử:

- `--window [trang]`: mở luôn cửa sổ chính. Trang: `overview`, `memory`, `agents`, `devServers`, `processes`, `disk`, `backgroundItems`, `freeRAM`, `log`, `settings`, `about`.
- `--capture-popover <tệp.png>`: vẽ popover ra ảnh rồi thoát.
- `--test-stop-dev-server <cổng>` (chỉ bản debug): dừng dev server ở cổng đó theo đúng đường của hộp xác nhận, để thử việc dừng và nhật ký. Chỉ dừng server có thư mục làm việc nằm trong thư mục tạm.

## Đo đạc

Để quyết định làm gì tiếp, app đo máy chịu tải ra sao theo từng phút. Không gửi dữ liệu đi đâu.

- Mỗi phút: áp lực bộ nhớ cao nhất, swap vào và ra (MB, tính từ độ chênh giữa hai mẫu 5 giây), số lần nén và giải nén mỗi giây, pageout, swap đã dùng, RAM đã dùng, wired, số việc nặng chạy cùng lúc (Xcode, SwiftPM, Gradle, build next/vite/webpack/tsc, test jest/vitest/Playwright, cargo, go, pytest, docker build). Ở phút đầu của một đợt căng, ghi nhóm hoặc phiên tăng RAM nhiều nhất ngay trước đó ("có thể liên quan": chỉ là tương quan).
- "Căng" là định nghĩa tạm: áp lực bộ nhớ từ mức cảnh báo, hoặc swap vào và ra từ 20 MB trong một phút. Ngưỡng sẽ chỉnh theo dữ liệu.
- Tệp: `~/Library/Application Support/8GB Vibe/measurements/<ngày>.csv`, chỉ người dùng đọc được (0600), giữ tối đa 14 ngày và 5 MB. Chỉ một bản app đang chạy được ghi.
- Việc nặng được thấy khi app lấy mẫu tiến trình: 5 giây một lần khi mở cửa sổ, 60 giây khi chạy nền, nên việc rất ngắn có thể bị sót.
- Điểm sức khoẻ trừ theo hoạt động swap, không trừ chỉ vì tệp swap lớn.

```bash
"/Applications/8GB Vibe.app/Contents/MacOS/8GBVibe" --measurement-summary
```

```bash
"/Applications/8GB Vibe.app/Contents/MacOS/8GBVibe" --export-measurements ~/Desktop/8gb-do-luong.csv
```

## Ngôn ngữ

App có tiếng Việt (gốc) và tiếng Anh. Mặc định theo ngôn ngữ của macOS; Cài đặt có ô Ngôn ngữ (Tự động, Tiếng Việt, English), đổi xong mở lại app.

- Code, tên tệp, chú thích viết bằng tiếng Anh. Khoá dịch là câu tiếng Việt. Bản tiếng Anh ở `Resources/en.lproj/Localizable.strings`, được chép vào gói .app khi đóng gói.
- SwiftUI: `Text("...")`, `Button("...")` tự dịch. Chuỗi kiểu `String`: viết `String(localized: "...", bundle: .main)`.
- Câu có biến: khoá dùng `%@` (chuỗi, số đã định dạng) và `%lld` (số nguyên), ví dụ `"Đã chọn %lld mục" = "%lld selected";`.
- Thử tiếng Anh: `open -n "build/8GB Vibe.app" --args -AppleLanguages "(en)"`.

## Cấu trúc

| Thư mục | Nội dung |
|---|---|
| `Sources/VibeCore` | Lõi, không có giao diện: đọc số liệu hệ thống, đọc tiến trình (libproc), gộp nhóm, phiên rảnh, ngân sách RAM, gợi ý, ngưỡng, đo ổ, đọc LaunchAgents. |
| `Sources/EightGBVibe` | App SwiftUI: thanh menu, popover, cửa sổ chính. |
| `Tests/VibeCoreTests` | Test phần lõi. |
| `scripts/package.sh` | Bản dùng thử: build, đóng gói `.app`, ký ad-hoc. |
| `scripts/release.sh` | Bản phát hành: universal, ký Developer ID, notarize, DMG. |
| `scripts/make-icon.swift` | Vẽ icon app, tạo `Resources/AppIcon.icns`. |
| `scripts/common.sh` | Phần dùng chung: tên app, bundle id, tạo gói `.app`. |

## Giới hạn đã biết

- Thời gian rảnh chỉ tính từ lúc app bắt đầu theo dõi. Mới mở app thì hiện "Đang theo dõi".
- Chủ của máy ảo (Claude hay Docker) là ước đoán theo thời điểm khởi động.
- "Các app cần" là ước tính: cộng RAM thật cần của từng tiến trình (tính cả phần đã nén theo cỡ chưa nén) với phần wired.
- Thanh menu đầy thì macOS có thể ẩn biểu tượng mới. Kiểm tra trong Cài đặt hệ thống, mục Thanh menu.

## Đóng góp

Xem [CONTRIBUTING.md](CONTRIBUTING.md). Lỗi bảo mật xin báo riêng, xem [SECURITY.md](SECURITY.md).

## Giấy phép

Mã nguồn theo [Giấy phép Apache 2.0](LICENSE). Bản quyền 2026 thuộc BEECA. Xem thêm [NOTICE](NOTICE).

## Nhãn hiệu

Tên "8GB Vibe", icon app, tên và logo BEECA là nhãn hiệu của BEECA, không thuộc phạm vi Giấy phép Apache 2.0 (mục 6). Bản fork phát hành ra ngoài phải đổi tên, đổi icon và không dùng logo BEECA. Chi tiết: [TRADEMARKS.md](TRADEMARKS.md).
