# Chức năng 8GB Vibe

- Cập nhật: 08/11/2026 (theo lộ trình BEECA duyệt cùng ngày)
- Câu định vị: **8GB Vibe, vibe coding on a budget Mac.** Trạm điều phối RAM cho người vibe code và agent AI trên máy Mac cấu hình yếu.
- Ký hiệu trạng thái: **Có** (đã có trong bản phát hành), **Có (1.1.0)** (mới ở bản 1.1.0, phát hành 08/11/2026), **Kế hoạch** (chưa làm, kèm bản dự kiến).

---

## 1. Tổng quan theo nhóm

| Nhóm | Mục đích | Trạng thái |
|---|---|---|
| A. Theo dõi máy | Biết máy đang khoẻ hay yếu, ai đang chiếm tài nguyên | Có |
| B. Theo dõi agent AI | Biết các agent đang chạy gì, tốn bao nhiêu, còn chỗ không | Có (1.1.0) |
| C. Giải phóng RAM | Tắt app, dịch vụ, tiến trình mồ côi, luôn hỏi trước | Có |
| D. Cảnh báo | Báo sớm khi máy sắp đơ, agent xong việc | Có một phần |
| E. Ổ đĩa | Biết cái gì chiếm ổ, dọn cache an toàn | Có phần xem, phần dọn ở 1.2 |
| F. Dev server và build | Quản lý server, cổng, build nặng | Có (dev server, 1.1.0), hàng đợi build ở 1.3 |
| G. Điều khiển từ xa | Điều khiển Mac ở nhà từ Mac khác | Kế hoạch, sau 2.0 |
| H. Cho agent dùng | Agent tự biết giới hạn máy trước khi chạy việc nặng | Kế hoạch 1.3, 2.0 |
| I. Sản phẩm | Giới thiệu, bản quyền, ngôn ngữ, phát hành | Có |

---

## 2. Chi tiết

### A. Theo dõi máy

| Chức năng | Mô tả | Trạng thái |
|---|---|---|
| Biểu tượng thanh menu | Vòng tròn đầy theo % RAM, màu theo mức căng, kèm số swap | Có |
| Popover | Điểm sức khoẻ, RAM, swap, ổ trống, biểu đồ swap 1 giờ, app dùng nhiều RAM nhất | Có |
| Điểm sức khoẻ máy | Từ 0 đến 100, kèm câu giải thích vì sao máy chậm | Có |
| Tổng quan | Thẻ RAM, swap, tải CPU, ổ trống có biểu đồ; "Ai đang chiếm RAM" có icon app thật | Có |
| Ngân sách RAM | So các app cần bao nhiêu với RAM máy, phần vượt phải nén hoặc swap | Có |
| Gộp theo nhóm công việc | Claude, Xcode và Simulator, Android, Docker, trình duyệt, chat, đồng bộ, IDE và AI khác, hệ thống | Có |
| Tiến trình | Bảng mọi tiến trình, sắp xếp, tìm kiếm | Có |
| Chạy nền | Dịch vụ tự chạy khi khởi động máy (chỉ xem) | Có |
| Lịch sử 24 giờ và 7 ngày | Lưu mẫu mỗi phút (RAM, swap, áp lực, top 5 nhóm), biểu đồ trong Tổng quan, giới hạn dung lượng tệp | Kế hoạch 1.2 |
| Báo cáo tuần | Swap cao nhất, công cụ tốn nhất, có nên nâng RAM không | Kế hoạch 2.0 |

### B. Theo dõi agent AI

| Chức năng | Mô tả | Trạng thái |
|---|---|---|
| Trang Agent AI | Nhóm Vibe ở thanh bên, thay trang Claude Code cũ. Gom agent dòng lệnh (Claude Code, Codex CLI...), app AI (Claude gồm máy ảo, ChatGPT...), IDE có AI (Cursor, Antigravity...) | Có (1.1.0) |
| Ước tính chỗ cho phiên mới | "Ước tính còn chỗ cho khoảng N phiên agent nữa"; khi gần hết RAM: "chưa nên mở thêm phiên"; khi các app đã cần hơn RAM máy: cảnh báo thiếu RAM kèm số GB vượt. Luôn ghi là ước tính, không bảo đảm không swap | Có (1.1.0, câu chữ sửa ở 1.1.1) |
| MCP server theo phiên | Số MCP và RAM của từng phiên; báo khi một MCP chạy nhiều bản ("Playwright MCP chạy 5 bản, tốn 2,1 GB") | Có (1.1.0) |
| Cảnh báo phình bộ nhớ | Phiên tăng RAM đều trong 30 phút hoặc vượt 2 GB thì gợi ý thoát rồi mở lại (không tự làm); báo RAM wired tăng bất thường | Có (1.1.0) |
| Nhận dạng thêm | Antigravity CLI (`agy`), cây con của `sandbox-exec` (Codex), máy ảo Cowork của Claude hiện riêng | Có (1.1.0) |
| Hạn mức token (phụ) | Chỉ hiện % 5 giờ và 7 ngày từ dữ liệu chính thức của Claude Code; không đọc Keychain, cookie | Kế hoạch 1.4 |

### C. Giải phóng RAM

| Chức năng | Mô tả | Trạng thái |
|---|---|---|
| Dọn RAM | Danh sách app, Simulator, Gradle, emulator đang chiếm RAM; gợi ý thứ rảnh trên 30 phút | Có |
| Hộp xác nhận | Liệt kê từng mục kèm RAM giải phóng; Esc là huỷ | Có |
| Thoát chuẩn | App tự lưu rồi đóng; không đóng sau 10 giây thì cho buộc thoát (xác nhận lần hai) | Có |
| Thoát từ bảng Tiến trình | Chuột phải vào tiến trình của bạn | Có |
| Bảo vệ (sửa B1) | Không cho thoát chính app, loginwindow, Finder, Dock, app Claude, phiên Claude Code từ mọi chỗ, kể cả bảng Tiến trình và nút Dừng của Dev server | Có (1.1.0) |
| Nhật ký | Ghi mọi lần thoát: thời điểm, đối tượng, RAM, kết quả | Có |
| Tiến trình mồ côi | Dev server, MCP server, Playwright còn chạy sau khi agent đã xong; dừng có xác nhận | Có (1.1.0) |
| Mồ côi biết nguồn gốc | Nhớ cây cha khi agent còn sống; hiện "của phiên Claude Code ở dự án X, kết thúc 2 giờ trước"; gộp theo phiên gốc để dừng một lần | Có (1.1.0) |
| Thử nút Dừng trên tiến trình thật | Server giả trong thư mục tạm, dừng qua app, kiểm nhật ký; sửa B2 (kiểm danh tính trước khi dừng) | Có (1.1.0) |
| Chế độ Vibe | "Chỉ Claude", "Claude + iOS", "Claude + Web": một lần bấm dọn máy cho việc sắp làm, có xác nhận | Kế hoạch 1.4 |
| Hạ ưu tiên app nền | `taskpolicy -b` cho đồng bộ đám mây, chat khi đang build; bấm lại là trả như cũ | Kế hoạch 1.4 |

### D. Cảnh báo

| Chức năng | Mô tả | Trạng thái |
|---|---|---|
| Máy đang chậm | Thông báo kèm gợi ý nên tắt gì; bấm vào mở trang Dọn RAM | Có |
| Ổ sắp đầy, quá nhiều phiên | Mỗi loại tối đa 30 phút một lần | Có |
| Ngưỡng chỉnh được | Swap, ổ trống, tải CPU, số phiên, thời gian coi là rảnh | Có |
| Báo agent xong, cần duyệt quyền | Qua hook của từng công cụ, gọi lệnh `8gb notify` (không mở server HTTP), chỉ gửi loại sự kiện, mã phiên, thư mục dự án. Mặc định tắt; bật cho từng công cụ trong Cài đặt; hiện đúng đoạn sẽ thêm vào tệp cài đặt của agent, sao lưu, có nút gỡ, ghi nhật ký. Làm Claude Code trước, rồi Codex, sau cùng Cursor và Antigravity | Kế hoạch 1.2 |
| Cảnh báo sớm | Swap tăng nhanh thì báo trước khi đơ | Kế hoạch 2.0 |

### E. Ổ đĩa

| Chức năng | Mô tả | Trạng thái |
|---|---|---|
| Đo cache và dữ liệu lớn | Chia ba mức: an toàn, cần xem, của app khác | Có |
| Dọn cache an toàn | DerivedData, npm, pip, uv, Homebrew, Gradle, Codex, Playwright, npx, Cursor, Simulator hỏng. Có xem trước dung lượng, hộp xác nhận, nhật ký. Ô chọn trong Cài đặt: "Chuyển vào Thùng rác" (mặc định) hoặc "Xoá thẳng"; hộp xác nhận ghi rõ cách đang chọn | Kế hoạch 1.2 |
| Mục cần xem | Worktree của agent lâu không dùng, `node_modules` không mở 30 ngày, model AI lâu không dùng. Chỉ liệt kê, người dùng chọn từng mục; không xoá worktree có thay đổi chưa commit | Kế hoạch 1.2 |

### F. Dev server và build

| Chức năng | Mô tả | Trạng thái |
|---|---|---|
| Dev server và cổng | Trang Dev server: dự án, loại (Next.js, Vite, Python...), cổng, cổng mở ra mạng, ai đã chạy, RAM, rảnh bao lâu; mở trình duyệt; dừng có xác nhận | Có (1.1.0) |
| Hàng đợi build | `8gb build -- xcodebuild ...`: mỗi lúc một build nặng; chờ khi áp lực đỏ; app hiện hàng đợi | Kế hoạch 1.3 |
| Giữ máy thức khi agent chạy | `caffeinate -w <pid>` theo phiên đang chạy, tự hết khi agent xong; bật tắt trong menu | Kế hoạch 1.3 |

### G. Điều khiển từ xa (chỉ chủ máy dùng)

Lùi xuống sau bản 2.0 (quyết định 08/11/2026): cần đường hầm qua máy chủ, ghép đôi và mã hoá, là bề mặt tấn công lớn, phải rà bảo mật riêng.

| Chức năng | Mô tả | Trạng thái |
|---|---|---|
| Ghép đôi máy | Mã ghép một lần giữa hai Mac của bạn | Kế hoạch, sau 2.0 |
| Đường hầm qua 8gb.beeca.vn | Mã hoá đầu cuối, không cần Tailscale, không mở cổng | Kế hoạch, sau 2.0 |
| Mở màn hình, mở Terminal | Chia sẻ màn hình và SSH của macOS qua đường hầm | Kế hoạch, sau 2.0 |
| Máy của tôi, chế độ Vắng nhà | Trạng thái máy ở nhà, Dọn RAM từ xa, giữ máy thức khi cắm sạc | Kế hoạch, sau 2.0 |

### H. Cho agent dùng

| Chức năng | Mô tả | Trạng thái |
|---|---|---|
| Lệnh `8gb status` | Một dòng: áp lực, swap, còn chỗ cho N phiên, có nên build không; có `--json`. Đọc trạng thái app ghi ra tệp, không tự đo lại | Kế hoạch 1.3 |
| Đoạn mẫu cho CLAUDE.md, AGENTS.md | Nút "Chép đoạn mẫu", người dùng tự dán | Kế hoạch 1.3 |
| Hook SessionStart (tuỳ chọn) | Chèn trạng thái máy vào đầu mỗi phiên agent, cài theo cách của hook báo xong | Kế hoạch 1.3 |
| MCP server của 8GB Vibe | Công cụ `machine_status`, `heavy_processes`, `can_start_session`, chạy stdio | Kế hoạch 2.0 |

### I. Sản phẩm

| Chức năng | Mô tả | Trạng thái |
|---|---|---|
| Trang Giới thiệu | Icon, phiên bản, miễn phí 100%, quyền riêng tư, logo BEECA, bản quyền | Có |
| Cài đặt | Ngưỡng, kiểu thanh menu, thông báo, mở cùng máy | Có |
| Ngôn ngữ | Tiếng Việt và tiếng Anh theo ngôn ngữ máy, có ô chọn Ngôn ngữ trong Cài đặt | Có (1.1.0) |
| Icon lục bảo | Số 8 đồng hồ luân chuyển, nền lục bảo; màu nhấn lục bảo | Có (1.1.0) |
| Gợi ý cấu hình cho máy 8 GB | Kiểm tra rồi hướng dẫn: giới hạn RAM Docker hoặc dùng OrbStack, Colima; bớt MCP nặng; Gradle; Spotlight; login items; một app đồng bộ đám mây. Người dùng tự làm | Kế hoạch 1.4 |
| Bản phát hành | DMG universal (Apple silicon và Intel), ký Developer ID, notarize | Có |
| Trang web 8gb.beeca.vn | Giới thiệu và tải về | Đang làm (PR #1), chờ deploy |

---

## 2b. Cấu hình máy và hồ sơ tối ưu

Yêu cầu của BEECA (08/11/2026): tuỳ cấu hình mỗi máy mà app tối ưu khác nhau; quét phần cứng lần đầu dùng và lưu lại.

**Quét phần cứng** (`VibeCore/HardwareProfile.swift`):
- Dùng `sysctl` và IOKit, không dùng mạng. Thu: model (`hw.model`), tên máy, chip, Apple silicon hay Intel, số nhân hiệu năng và tiết kiệm, RAM, dung lượng và định dạng ổ trong, phiên bản macOS. Kiểm có Xcode, Docker, OrbStack, Android Studio trong /Applications hay không (chỉ kiểm tồn tại, không mở).
- Lưu ở `~/Library/Application Support/8GB Vibe/hardware.json`, quyền 0600, có ghi ngày quét.
- Quét lại khi: lần đầu mở; phiên bản schema đổi; model, RAM hoặc macOS khác lần trước (kiểm rẻ mỗi lần mở); hoặc người dùng bấm "Quét lại" ở trang Máy.

**Trang "Máy"** (nhóm Xem của thanh bên, ⌘I, có trong menu Xem; trang Giới thiệu chỉ còn một dòng tóm tắt và nút mở trang). Chỉ đọc, không mạng, không chạy app khác. Trường nào không đọc được ghi "Không đọc được", không đoán. Không đọc số serial hay UUID.

| Nhóm | Thông tin | Nguồn | Lưu |
|---|---|---|---|
| Máy | Tên máy, mã model, năm (lấy từ tên máy) | IOKit `product-name`, sysctl `hw.model` | hardware.json |
| Chip | Tên chip, nhân hiệu năng và tiết kiệm, nhân GPU, kiến trúc | sysctl, IOKit `AGXAccelerator` `gpu-core-count`, `uname` | hardware.json |
| Bộ nhớ | RAM; loại RAM (Apple silicon không công bố, ghi "Không đọc được"); đang dùng, nén, wired, swap | sysctl; số sống từ Monitor | RAM lưu; số sống không |
| Ổ đĩa | Dung lượng, còn trống, định dạng, ổ trong/ngoài, model ổ, SMART (chỉ biết ổ có hỗ trợ; tình trạng cần công cụ khác, app không đọc) | resourceValues, IOKit `IOBlockStorageDevice` | trừ còn trống |
| Pin | Tình trạng (macOS báo thì hiện), số lần sạc so với thiết kế, dung lượng còn so với thiết kế (mAh), mức pin, đang sạc, nguồn điện | IOPowerSources, IOKit `AppleSmartBattery` (chỉ lấy các khoá cần, bỏ số serial) | không |
| Màn hình | Mỗi màn hình: điểm ảnh, hiển thị như, tần số | CoreGraphics | không |
| Hệ thống | macOS và bản build, thời gian đã chạy, nhiệt (`thermalState`), Chế độ Nguồn điện thấp | ProcessInfo, sysctl `kern.osversion`, `kern.boottime` | bản macOS lưu |
| Công cụ phát triển | Xcode, Simulator, Docker, OrbStack, Android Studio, Command Line Tools, kèm phiên bản trong Info.plist | kiểm tệp tồn tại | hardware.json |
| Hồ sơ tối ưu | Bảng ngưỡng mặc định của hồ sơ; ghi "thử nghiệm" cho 16 và 24 GB; nút Quét lại | tính từ hồ sơ | không |

Số sống đọc mỗi 5 giây khi trang đang mở, không lưu. hardware.json lên schema 2 (tệp cũ vẫn đọc được, lần mở sau tự quét lại).

**Hồ sơ tối ưu** (giá trị mặc định; giá trị người dùng đã tự chỉnh trong Cài đặt được giữ nguyên):

| Giá trị | 8 GB (đến 12 GB) | 16 GB (đến 20 GB) | 24 GB trở lên | Nguồn |
|---|---|---|---|---|
| Swap vàng / đỏ | 3 / 6 GB | 4 / 8 GB | 6 / 12 GB | 8 GB: giữ mặc định cũ; 16, 24: ước tính |
| Phiên agent khuyên dưới / báo đỏ | 4 / 8 | 8 / 12 | 12 / 20 | Ước tính (người dùng báo khoảng 2 phiên nặng trên 16 GB; phiên Claude Code rảnh 110 đến 250 MB) |
| RAM chừa cho hệ thống khi ước tính chỗ cho phiên mới | 0,5 GB | 1 GB | 2 GB | Ước tính |
| "Swap đang rất nặng": swap mỗi phút báo ngay / báo khi gấp đôi | 3 / 1 GB | 4 / 1,5 GB | 6 / 2 GB | 8 GB: chọn trên mức thường ngày đo được (0,5 đến 3,5 GB/phút); còn lại: ước tính |
| Quét tiến trình khi chạy nền | 60 giây | 45 giây | 30 giây | Ước tính; máy ít RAM quét thưa hơn |
| Tải CPU 5 phút vàng / đỏ | 2 và 4 lần số nhân | như cột trái | như cột trái | Theo số nhân (máy 8 nhân: 16 / 32, giữ như cũ) |

Máy Intel: dùng cùng ngưỡng với máy Apple silicon cùng bậc RAM. Hệ số 0,6 cũ đã bỏ ở đợt 1 MCP (08/11/2026) vì chưa có số đo nào cho thấy máy Intel treo sớm hơn.

Tên cảnh báo: "Swap đang rất nặng" (trước là "Máy sắp đơ"; đổi vì số đo cho thấy máy vẫn phản hồi ở mức swap này). Nội dung ghi tốc độ swap vào ra đo được, khoảng đo (trung bình 60 giây gần nhất) và áp lực bộ nhớ. Không nói máy sắp treo; app nặng lên nhiều nhất chỉ ghi là "chưa chắc là nguyên nhân".

**Sự cố và giấc ngủ (đợt 1, 08/11/2026):**

- App nghe tín hiệu máy sắp ngủ và vừa thức, và so đồng hồ thường với đồng hồ dừng khi ngủ (`systemUptime`). Khoảng trống có ngủ chỉ ghi "máy ngủ", không báo sự cố.
- Tiêu đề sự cố theo bằng chứng:

| Bằng chứng | Tiêu đề |
|---|---|
| Không lấy được số đo từ 30 giây khi máy căng | Theo dõi bị gián đoạn khi máy căng |
| Vòng lặp chính của app trễ từ 10 giây | 8GB Vibe phản hồi chậm khi máy căng |
| Lần chạy trước không thoát bình thường, mẫu cuối đang căng | Lần trước app kết thúc bất thường khi máy căng (ghi thêm nếu máy đã khởi động lại, đọc `kern.boottime`) |
| Khoảng trống từ 60 giây và swap đỉnh từ 10 GB/phút | Theo dõi bị gián đoạn lâu khi swap rất nặng |

Không tiêu đề nào nói cả máy treo chỉ vì thiếu mẫu hay app phản hồi chậm.

**Số RAM khi dọn (đợt 1):**

- Trước khi đóng: "Bộ nhớ các app này đang giữ: khoảng X (ước tính)". Thanh "sau" vẽ nhạt dần, là khoảng, không phải vạch chắc chắn.
- Sau khi đóng: app chụp RAM đang dùng và swap ngay trước khi đóng, đo lại sau 10 giây. Thẻ thưởng hiện "Ước tính theo app" và "Đo được: RAM dùng giảm Y, swap giảm Z (có thể lẫn hoạt động khác)".
- Nhật ký thêm dòng "Đo sau khi dọn" có trường `doDuoc` (`ram`, `swap`, byte, có thể âm); `giaiPhong` giữ nguyên là số ước tính. Dòng "Tuần này" ghi rõ là cộng số ước tính.

Cách giữ giá trị người dùng: app nhớ bộ mặc định đã áp lần trước. Ngưỡng nào còn bằng mặc định cũ (chưa bị chỉnh) thì đổi sang mặc định của hồ sơ mới; ngưỡng đã chỉnh thì giữ.

Lần đầu quét, app gửi thông báo "Đã nhận diện máy: MacBook Air (M2, 2022), 8 GB. Dùng hồ sơ 8 GB."

## 3. Lộ trình (thứ tự BEECA chốt 08/11/2026)

Thứ tự này thay cho thứ tự cũ, sau khi rà soát nội bộ. Nguyên tắc: đo trước khi xây; mỗi bước có điều kiện đi tiếp.

| Bước | Đầu ra | Điều kiện đi tiếp |
|---|---|---|
| 1. Đo | Lưu biên bản thử dừng của 1.1.0. Đo áp lực, tốc độ swap (độ chênh giữa hai mẫu), nén và giải nén, việc nặng chạy chồng nhau, qua nhiều buổi làm việc. Lịch sử 24 giờ tối giản | Có dữ liệu đại diện trên máy 8 GB của BEECA; thiếu thì bổ sung kịch bản tái hiện |
| 2. `8gb status` qua MCP (giai đoạn 0 và 1, đang làm) | `8gbvibe-mcp` (stdio, nằm trong gói app): tool đọc `machine_status`, `heavy_processes`, `agent_sessions`, `hardware_profile`, `can_start`; tool phối hợp `register_agent`, `heartbeat`, `acquire_slot` (trả cả `slot`, `advice` và `start_now`), `renew_slot`, `my_slots`, `release_slot` (một chỗ việc nặng cho mọi máy: đây là chính sách phối hợp bảo thủ, không phải giới hạn của máy, chưa có tuỳ chọn tăng; hạn tối đa 30 phút mỗi lần, tổng 2 giờ), `slots`, `post_message`/`read_messages`. Agent còn sống theo tiến trình MCP của nó (pid và giờ khởi động), không theo việc model có gọi tool hay không. Mỗi slot có hai trường tách biệt: `lease` (`active`, `expired`, `overdue`) và `task` (`running`, `ended`, `unknown`). Hết giờ mà việc nặng của phiên đó còn chạy: `lease: expired`, `task: running`, không cấp cho người khác, không dừng việc đó. Quá tổng 2 giờ mà việc vẫn chạy: `lease: overdue`, app báo ở chuông và hiện trong Cài đặt > Agent AI với nút "Nhả chỗ" (hỏi trước, ghi nhật ký, chỉ bỏ lượt giữ chỗ, không đụng tiến trình). Có thời điểm đo và tuổi dữ liệu, trả "unknown" khi không có số đo. Chỉ là lời khuyên và giữ chỗ tự giác. Cài đặt có 3 mức quyền và danh sách client agent có trên máy (Claude Code, Codex, Gemini CLI, Cursor, Claude Desktop, Antigravity), mỗi client một dòng: trạng thái cấu hình, số agent đã kết nối, nút "Cài" và "Gỡ" (mục 8 của tài liệu MCP). Chi tiết: `docs/NGHIEN_CUU_MCP.md` | Một agent thật đọc được và làm theo trong demo |
| 3. Thu hồi theo phiên hoàn chỉnh | Trên nền 1.1.0 (mồ côi biết nguồn gốc, MCP theo phiên): dọn phần còn sót của một phiên trong một lần, có duyệt; `8gb leftovers` | Nguồn gốc tin cậy, có duyệt, đo được GB thu hồi, không dừng nhầm |
| 4. Chọn theo dữ liệu | Một trong: thu hồi sâu hơn, gợi ý giảm mức song song (ví dụ `--maxWorkers`, `org.gradle.workers.max`), hoặc hàng đợi việc nặng (`8gb run`) | Chứng minh được loại việc nào có lợi và đánh đổi thời gian |
| 5. Kiểm chứng ngoài máy nhóm phát triển | 5 đến 10 người thử, ít nhất 3 máy 8 GB; demo; nền tảng cộng đồng | Lợi ích lặp lại; lời hứa khớp bản phát hành |

Các chức năng đã lên kế hoạch khác (báo agent xong qua hook, dọn cache có Thùng rác, chế độ Vibe, hạ ưu tiên app nền, gợi ý cấu hình, MCP server của 8GB Vibe, báo cáo tuần) giữ trong danh sách mục 2, xếp lịch sau bước 4 theo dữ liệu đo. Điều khiển từ xa vẫn sau 2.0.

Quyết định đã chốt 08/11/2026 (mục 12.4 của tệp phản biện):
- Làm nền tảng công khai song song từ bây giờ: LICENSE, CI build và test lõi, Homebrew cask, CONTRIBUTING, SECURITY, mẫu issue.
- Sửa câu "Còn chỗ cho N phiên agent nữa trước khi phải swap": đã làm ở bản 1.1.1 (ước tính, ba trạng thái còn chỗ, gần hết, thiếu RAM).
- Thông điệp: Mac thiếu RAM khi chạy agent (8 GB, và 16 GB chạy nhiều agent); giữ tên 8GB Vibe.
- Chuyển repo công khai khi xong bước 3 và nền tảng công khai (dùng repo mới sạch, theo quyết định trước).
- Giấy phép: **Apache 2.0** cho mã nguồn (BEECA chốt cuối 08/11/2026). Mục 6 của giấy phép không cấp quyền dùng nhãn hiệu: tên 8GB Vibe, logo app và logo BEECA giữ riêng, ghi thêm trong `TRADEMARKS.md` hoặc README.

Sau bước 2 (MCP): giai đoạn 3 "yêu cầu dọn dẹp chờ duyệt trong app"; giai đoạn sau: mức quyền "Tự làm việc rủi ro thấp" và công tắc "agent tự dừng mồ côi của chính phiên khi máy thiếu RAM" (mặc định tắt, có nhật ký). Hook `PreToolUse` để bắt buộc giữ chỗ chỉ làm nếu dữ liệu đo cần.

## 4. Nguyên tắc

- Mọi hành động đều hỏi trước. Không tự tắt, không tự xoá, không tự cài hook.
- Mặc định không gửi dữ liệu đi đâu. Hook, báo về điện thoại, điều khiển từ xa là tuỳ chọn, phải tự bật.
- App luôn nhẹ: dưới 50 MB RAM, gần 0 % CPU khi chạy nền.
- Không tắt dịch vụ của macOS, không dùng `purge`, không đọc Keychain hay cookie, không mở server HTTP trên máy.
- Giữ hỗ trợ máy Intel (bản universal).
