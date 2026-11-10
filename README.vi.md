# 8GB Vibe

*Vibe coding on a budget Mac.*

[English](README.md) | Tiếng Việt

8GB Vibe là app thanh menu miễn phí cho macOS, giúp máy Mac cấu hình thấp (như MacBook Air M2 8 GB RAM) chạy mượt khi vibe code: nhiều phiên Claude Code hay Codex, Xcode, Gradle, Docker và dev server cùng lúc. App cho biết cái gì đang chiếm bộ nhớ, cảnh báo trước khi máy bắt đầu ì, và giúp giải phóng RAM. App không bao giờ tự tắt hay tự xoá gì mà không hỏi bạn trước.

**Tải về:** [8gb.beeca.vn](https://8gb.beeca.vn) hoặc [GitHub Releases](https://github.com/BeecaET/8gb-vibe/releases). Miễn phí, sản phẩm của BEECA.

- Yêu cầu: macOS 13 Ventura trở lên, Apple Silicon hoặc Intel (bản universal).
- Bản phát hành ký Developer ID của BEECA và được Apple notarize. Mỗi bản phát hành ghi mã SHA-256 của tệp DMG.
- Giao diện tiếng Việt và tiếng Anh.
- Chức năng và lộ trình: [docs/FEATURES.md](docs/FEATURES.md). Thiết kế MCP server: [docs/MCP.md](docs/MCP.md) (tiếng Anh).

## Có gì

| Phần | Nội dung |
|---|---|
| Thanh menu | Vòng tròn đầy theo % RAM, màu theo mức áp lực bộ nhớ (xanh, cam, đỏ), kèm số swap. |
| Popover | Đồng hồ RAM, swap, ổ đĩa; biểu đồ swap 1 giờ; top 3 nhóm; lượng RAM giải phóng được. |
| Tổng quan | Câu khuyên một dòng, RAM, swap, ổ trống, tải; biểu đồ swap; gợi ý; trạng thái các ngưỡng. |
| Bộ nhớ | Ngân sách RAM và bảng nhóm công việc (Claude, Xcode, Android, Docker...) mở rộng được. |
| Agent AI | Agent dòng lệnh (Claude Code, Codex CLI, Gemini CLI...) theo từng phiên, app AI, IDE có AI. Ước tính sơ bộ còn chỗ cho khoảng bao nhiêu phiên theo ngân sách RAM (chỉ là ước tính, không bảo đảm không swap). |
| Dev server | Server đang mở cổng (Next.js, Vite, Python...): dự án, cổng, cổng mở ra mạng, ai đã chạy, RAM, rảnh bao lâu. Đánh dấu server mồ côi (agent hay Terminal đã đóng). Mở trình duyệt hoặc dừng, có xác nhận. |
| Tiến trình | Tất cả tiến trình, sắp xếp, tìm kiếm, có nhóm. Thoát tiến trình của bạn, có xác nhận. |
| Ổ đĩa | Đo cache và dữ liệu lớn đã biết, chia mức an toàn, cần xem, dữ liệu của app khác. |
| Chạy nền | Dịch vụ tự chạy khi đăng nhập hay khởi động (LaunchAgents, LaunchDaemons). |
| Máy | Hồ sơ phần cứng của máy, dùng để điều chỉnh lời khuyên và ngưỡng. |
| Dọn RAM | App, Simulator, Gradle daemon, emulator đang chiếm RAM. Gợi ý thứ rảnh trên 30 phút. Thoát có xác nhận; buộc thoát cần xác nhận lần hai. |
| Thông báo | "Máy đang chậm" kèm việc nên tắt, ổ gần đầy, quá nhiều phiên agent. Mỗi loại tối đa 30 phút một lần, lưu lại ở trang Thông báo. |
| Nhật ký | Mọi lần thoát bạn đã xác nhận: giờ, đối tượng, RAM giải phóng (ước tính và đo được), kết quả. |
| Cài đặt | Chia tab: ngưỡng cảnh báo, kiểu thanh menu, thông báo, mở cùng máy, ngôn ngữ, giao diện Sáng/Tối, màu nhấn, Agent AI. |

Nhấn ⌘K trong cửa sổ chính để mở bảng lệnh.

### Nguyên tắc an toàn

- Mọi lần thoát, dừng hay dọn đều do bạn chọn và xác nhận. Không tự tắt, không tự xoá.
- Không bao giờ thoát từ app: chính 8GB Vibe, Finder, Dock, tiến trình hệ thống macOS và app Claude (thoát app này sẽ đóng mọi phiên Claude Code).
- Không dữ liệu nào rời khỏi máy. App không mở server HTTP, không đọc Keychain hay cookie trình duyệt.

## Agent AI (MCP)

App có sẵn MCP server qua stdio tại `8GB Vibe.app/Contents/Helpers/8gbvibe-mcp`. AI agent (Claude Code, Codex, Claude Desktop, Gemini CLI, Antigravity, Cursor) đọc được trạng thái máy và phối hợp việc nặng:

- Đọc: `machine_status`, `heavy_processes`, `agent_sessions`, `hardware_profile`, `can_start` (lời khuyên trước việc nặng).
- Phối hợp: `register_agent`, `heartbeat`, `acquire_slot` / `release_slot` (một chỗ việc nặng có hạn giờ, để hai agent không build cùng lúc), `slots`, `post_message` / `read_messages`.

Phối hợp là tự giác. Không tool nào tắt tiến trình, xoá tệp hay đổi cài đặt. Trong Cài đặt > Agent AI, bạn chọn mức quyền và cài server vào các agent có trên máy; app hỏi trước, sao lưu tệp cấu hình của agent và gỡ lại được. Cài tay vào Claude Code:

```bash
claude mcp add --transport stdio --scope user 8gbvibe -- "/Applications/8GB Vibe.app/Contents/Helpers/8gbvibe-mcp"
```

Thiết kế, số đo và mô hình an toàn: [docs/MCP.md](docs/MCP.md).

## Đo lường

Để quyết định làm gì tiếp, app ghi lại máy chịu tải thế nào theo từng phút. Không gì rời khỏi máy.

- Mỗi phút: áp lực bộ nhớ cao nhất; swap vào và ra (MB, từ độ chênh giữa hai mẫu 5 giây); số lần nén và giải nén mỗi giây; pageout; swap đã dùng; RAM đã dùng; wired; số việc nặng chạy cùng lúc (Xcode, SwiftPM, Gradle, build next/vite/webpack/tsc, test jest/vitest/Playwright, cargo, go, pytest, docker build); và khi bắt đầu một đợt căng, nhóm hay phiên có RAM tăng nhiều nhất ngay trước đó (ghi "có thể liên quan": chỉ là tương quan).
- "Căng" là định nghĩa tạm: áp lực bộ nhớ từ mức cảnh báo trở lên, hoặc tổng swap vào và ra từ 20 MB trong phút. Ngưỡng sẽ chỉnh theo dữ liệu.
- Tệp: `~/Library/Application Support/8GB Vibe/measurements/<ngày>.csv`, chỉ bạn đọc được (0600), giữ tối đa 14 ngày và 5 MB. Chỉ một bản app đang chạy được ghi.
- Việc nặng được thấy khi lấy mẫu tiến trình: 5 giây một lần khi mở cửa sổ, 60 giây một lần khi chạy nền, nên việc rất ngắn có thể bị sót.
- Điểm sức khoẻ (0 đến 100) trừ theo hoạt động swap, không theo dung lượng tệp swap.

```bash
"/Applications/8GB Vibe.app/Contents/MacOS/8GBVibe" --measurement-summary
```

```bash
"/Applications/8GB Vibe.app/Contents/MacOS/8GBVibe" --export-measurements ~/Desktop/8gb-measurements.csv
```

## Build từ mã nguồn

Cần macOS 13 trở lên và bộ công cụ Swift (Xcode hoặc Command Line Tools). Không dùng thư viện bên thứ ba. `-j 2` giữ build nhẹ trên máy 8 GB.

Chạy test phần lõi:

```bash
swift test -j 2
```

Build bản dùng thử trên máy (chữ ký ad hoc, chỉ cho chip của máy này):

```bash
./scripts/package.sh
```

```bash
open "build/8GB Vibe.app"
```

Tham số khi chạy thử:

- `--window [trang]`: mở cửa sổ chính ở một trang: `overview`, `memory`, `agents`, `devServers`, `processes`, `disk`, `backgroundItems`, `machine`, `freeRAM`, `log`, `inbox`, `settings`, `about`.
- `--capture-popover <tệp.png>`: vẽ popover ra ảnh rồi thoát.
- `--test-stop-dev-server <cổng>` (chỉ bản debug): dừng dev server ở cổng đó qua đúng đường của hộp xác nhận. Chỉ dừng server có thư mục làm việc nằm trong thư mục tạm.

## Phát hành (nhóm bảo trì)

Bản phát hành: universal (Apple Silicon và Intel), ký Developer ID với hardened runtime, notarize, đóng gói DMG. Cần chứng chỉ Developer ID của BEECA và hồ sơ notarytool. Tạo hồ sơ một lần (lưu mật khẩu ứng dụng của Apple ID vào Keychain):

```bash
xcrun notarytool store-credentials <hồ sơ> --apple-id <email> --team-id 59SQ2V25T2
```

Build bản phát hành:

```bash
NOTARY_PROFILE=<hồ sơ> ./scripts/release.sh
```

Kết quả: `build/release/8GB-Vibe-<phiên bản>.dmg` và tệp `.sha256`. Phiên bản đọc từ tệp `VERSION`, số build là số commit.

## Ngôn ngữ

App có tiếng Việt và tiếng Anh. Mặc định theo ngôn ngữ của macOS; Cài đặt có ô Ngôn ngữ (Tự động, Tiếng Việt, English), đổi xong mở lại app.

- Code, tên tệp, chú thích viết bằng tiếng Anh. Chuỗi giao diện dịch bằng `Localizable.strings` trong `Resources/<ngôn ngữ>.lproj`, được chép vào app khi đóng gói.
- SwiftUI `Text("...")` và `Button("...")` tự dịch. Với giá trị `String` dùng `String(localized: "...", bundle: .main)`.
- Câu có giá trị dùng `%@` (chuỗi, số đã định dạng) và `%lld` (số nguyên).
- Thử tiếng Anh: `open -n "build/8GB Vibe.app" --args -AppleLanguages "(en)"`.

## Cấu trúc

| Thư mục | Nội dung |
|---|---|
| `Sources/VibeCore` | Phần lõi, không giao diện: số đo hệ thống, đọc tiến trình (libproc), gom nhóm, phiên rảnh, ngân sách RAM, gợi ý, ngưỡng, dev server và cổng, agent AI, quét ổ đĩa, LaunchAgents, logic MCP server. |
| `Sources/EightGBVibe` | App SwiftUI: thanh menu, popover, cửa sổ chính. |
| `Tests/VibeCoreTests` | Test phần lõi. |
| `scripts/package.sh` | Bản dùng thử: build, đóng gói `.app`, ký ad hoc. |
| `scripts/release.sh` | Bản phát hành: universal, Developer ID, notarize, DMG. |
| `scripts/common.sh` | Cấu hình chung: tên app, bundle id, đóng gói `.app`. |
| `scripts/make-icon.swift` | Vẽ icon app và tạo `Resources/AppIcon.icns`. |
| `scripts/mcp-harness` | Bộ chạy thử MCP server nhiều tiến trình. |
| `web` | Trang 8gb.beeca.vn (tĩnh). |
| `packaging/homebrew` | Mẫu cask Homebrew. |

## Giới hạn đã biết

- Thời gian rảnh chỉ tính từ lúc app bắt đầu theo dõi. Ngay sau khi mở, app ghi "Đang theo dõi".
- Chủ của máy ảo (Claude hay Docker) được đoán theo giờ khởi động.
- "App cần" là ước tính: footprint thật của từng tiến trình (bộ nhớ nén tính theo cỡ chưa nén) cộng bộ nhớ wired.
- Khi thanh menu đầy, macOS có thể ẩn biểu tượng mới. Xem Cài đặt hệ thống > Thanh menu.

## Đóng góp

Hoan nghênh báo lỗi, ý tưởng và pull request, bằng tiếng Anh hoặc tiếng Việt. Xem [CONTRIBUTING.md](CONTRIBUTING.md). Lỗi bảo mật xin báo riêng, xem [SECURITY.md](SECURITY.md).

## Giấy phép

Mã nguồn theo [Giấy phép Apache 2.0](LICENSE). Copyright 2026 BEECA. Xem thêm [NOTICE](NOTICE).

## Nhãn hiệu

Tên "8GB Vibe", icon app, tên và logo BEECA là nhãn hiệu của BEECA, không thuộc phạm vi Giấy phép Apache 2.0 (mục 6). Bản fork phát hành ra ngoài phải đổi tên, đổi icon và không dùng logo BEECA. Chi tiết: [TRADEMARKS.md](TRADEMARKS.md).
