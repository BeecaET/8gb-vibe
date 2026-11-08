# Nghiên cứu: MCP của 8GB Vibe cho các AI agent

- Ngày: 08/11/2026. Người làm: nhóm phát triển. Chỉ nghiên cứu, chưa code.
- Yêu cầu của BEECA: "8GB có MCP để các AI agent kiểm soát được phần cứng máy, yêu cầu dọn dẹp, giao tiếp với nhau. Nghiên cứu kỹ trước khi code."
- Ký hiệu nguồn:
  - **[KIỂM]**: đã đọc tài liệu chính thức hoặc đã đo trên máy này.
  - **[PHỤ]**: nguồn thứ cấp (blog, issue, danh mục).
  - **[GIẢ ĐỊNH]**: suy luận hoặc ước tính, chưa kiểm.

## 0. Kết luận ngắn

1. **Nên làm, theo kiểu "MCP chỉ đọc và phối hợp; mọi hành động phá huỷ do người duyệt trong app".** Chưa có sản phẩm nào kết hợp giám sát RAM và swap của macOS, giữ chỗ việc nặng giữa các agent khác hãng, và duyệt dọn dẹp ngoài kênh agent [PHỤ].
2. **Mỗi phiên agent sẽ có một tiến trình MCP riêng.** Claude Code tạo một tiến trình stdio cho mỗi phiên, không dùng chung [KIỂM, tài liệu và issue #28860]. Với 5 đến 10 phiên, RAM của tiến trình MCP là điểm quyết định. Đo trên máy này: một tiến trình stdio Swift tối giản chiếm **1,8 MB** footprint, Python 6,9 MB, Node 16 MB [KIỂM]. Vì vậy MCP phải là một chương trình Swift rất mỏng, không viết bằng Node hay Python.
3. **Không mở cổng HTTP.** Nguyên tắc của dự án đã chốt "không mở server HTTP trên máy". Dùng stdio; chia sẻ trạng thái giữa các phiên qua tệp có khoá trong Application Support (giai đoạn 1), hoặc Unix socket 0600 tới app (nếu cần sau).
4. **Elicitation và tool annotations không phải lớp an toàn.** Đặc tả MCP ghi client MUST coi annotations là không tin cậy [KIỂM]. Elicitation hiện trong chính client của agent và có thể bị hook tự trả lời [KIỂM]. Dọn dẹp phải được duyệt trong app 8GB Vibe.
5. **MCP bổ sung cho hook, không thay hook.** MCP dùng khi agent chủ động hỏi. Hook (`PreToolUse`) dùng khi cần bắt buộc, vì CLAUDE.md chỉ là ngữ cảnh, không phải quy tắc bắt buộc [KIỂM, tài liệu Claude Code].

## 1. Hiện trạng MCP

### 1.1. Đặc tả

| Mục | Nội dung | Nguồn |
|---|---|---|
| Bản mới nhất | 2026-07-28; bản trước 2025-11-25 | [KIỂM] modelcontextprotocol.io/specification/latest |
| Thay đổi lớn ở 2026-07-28 | Không còn trạng thái phiên: bỏ handshake `initialize`, mỗi request mang `protocolVersion` và năng lực client trong `_meta`; thêm `server/discover` (bắt buộc); bỏ `Mcp-Session-Id`; `subscriptions/listen` thay `resources/subscribe`; bỏ `ping` và `logging/setLevel`; elicitation trả về `InputRequiredResult` thay vì server gửi request ngược | [KIỂM] .../2026-07-28/changelog |
| Không còn khuyến nghị dùng | Roots, Sampling, Logging (ghi ra stderr), HTTP+SSE, Dynamic Client Registration | [KIỂM] |
| Transport | stdio và Streamable HTTP. HTTP+SSE không còn khuyến nghị. HTTP chạy local: server MUST kiểm header `Origin`, SHOULD bind 127.0.0.1, SHOULD có xác thực | [KIỂM] .../basic/transports |
| Xác thực | Tuỳ chọn. HTTP nên theo OAuth 2.1. stdio SHOULD NOT dùng OAuth, lấy thông tin từ biến môi trường | [KIỂM] .../basic/authorization |
| Tool annotations | `readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint`. "clients MUST consider tool annotations to be untrusted unless they come from trusted servers". Luôn SHOULD có người có quyền từ chối | [KIỂM] .../server/tools |
| Elicitation | Có 2 kiểu: form (schema phẳng, cấm hỏi bí mật) và URL. Kết quả: accept, decline hoặc cancel. Client MUST hiện rõ server nào đang hỏi | [KIỂM] .../client/elicitation |
| Resources, thông báo | Có, nhưng các client hỗ trợ không đều. Chỉ nên dựa vào tools | [KIỂM, mục 1.3] |

Hệ quả: dùng stdio, không cần OAuth. Client đời 2025-11-25 vẫn phổ biến, nên server cần nói được cả kiểu cũ (`initialize`) và kiểu mới [GIẢ ĐỊNH: việc này nhỏ nếu tự viết JSON-RPC].

### 1.2. SDK Swift chính thức (modelcontextprotocol/swift-sdk)

| Mục | Nội dung | Nguồn |
|---|---|---|
| Phiên bản | 0.12.1 (07/05/2026), vẫn là 0.x nên bản phụ có thể đổi API | [KIỂM] GitHub releases |
| Bản đặc tả hỗ trợ | 2025-11-25 (trừ Tasks, Sampling-with-tools, một phần xác thực). Chưa thấy hỗ trợ 2026-07-28 | [KIỂM] / [GIẢ ĐỊNH] cho 2026-07-28 |
| macOS tối thiểu | `.macOS("13.0")`, nên chạy được trên macOS 13 | [KIỂM] Package.swift |
| Công cụ | swift-tools-version 6.1 (README ghi Swift 6.0+) | [KIỂM] |
| Phụ thuộc | swift-system, swift-log, eventsource, swift-nio 2.65+, swift-docc-plugin (nhánh main) | [KIỂM] |
| Transport phía server | `StdioTransport`, HTTP có và không có trạng thái | [KIỂM] README |

Đánh giá:

- SDK đủ dùng về chức năng.
- Nhưng kéo theo swift-nio và bản thân còn 0.x. Ảnh hưởng tới RAM và thời gian build chưa đo [GIẢ ĐỊNH].
- 8GB Vibe chỉ cần stdio, JSON-RPC và vài tool. Một bộ JSON-RPC tự viết khoảng vài trăm dòng có thể nhẹ hơn và ít phụ thuộc hơn [GIẢ ĐỊNH].
- Đề xuất: giai đoạn 0 đo cả hai cách rồi chọn.

### 1.3. Client và cách cài (stdio)

| Client | Lệnh hoặc tệp cấu hình | Phạm vi | Ghi chú | Nguồn |
|---|---|---|---|---|
| Claude Code | `claude mcp add --transport stdio --scope user 8gbvibe -- <đường dẫn>` | local (mặc định, theo dự án, `~/.claude.json`); project (`.mcp.json`, phải duyệt); user (`~/.claude.json`) | Một tiến trình mỗi phiên. Annotations không dùng để tự duyệt; `readOnlyHint` chỉ cho chạy song song. `_meta["anthropic/requiresUserInteraction"]: true` buộc luôn hỏi người dùng, kể cả ở chế độ tự duyệt. Elicitation có form và URL, chỉ trong terminal tương tác | [KIỂM] code.claude.com/docs/en/mcp |
| Codex CLI | `codex mcp add 8gbvibe -- <đường dẫn>`, tệp `~/.codex/config.toml` mục `[mcp_servers.8gbvibe]` | user; `.codex/config.toml` cho dự án tin cậy | `default_tools_approval_mode` (chế độ `writes` hỏi với tool không phải read-only) | [KIỂM] |
| Gemini CLI | `gemini mcp add -s user 8gbvibe <đường dẫn>`, `~/.gemini/settings.json` | user hoặc project | Đã được Antigravity CLI thay cho nhiều tài khoản từ 18/06/2026 | [KIỂM] |
| Antigravity (agy) | `~/.gemini/config/mcp_config.json`, `<workspace>/.agents/mcp_config.json` | global hoặc workspace | Không có lệnh add | [KIỂM] antigravity.google/docs/mcp |
| Cursor | `~/.cursor/mcp.json` hoặc `.cursor/mcp.json` | global hoặc dự án | Có elicitation (không rõ kiểu) | [KIỂM] |

Việc cài vào client là **sửa cấu hình của agent**. Theo quyết định đã chốt về hook: mặc định tắt, chỉ cài khi người dùng bấm, hiện rõ đoạn sẽ thêm, có nút gỡ. Nhóm nghiên cứu không cài gì vào máy này.

## 2. Kiến trúc: so sánh

| | (a) Lệnh stdio + Unix socket tới app | (b) App mở HTTP 127.0.0.1 có token | (c) Chỉ stdio, đọc trực tiếp; phối hợp qua tệp có khoá |
|---|---|---|---|
| Tiến trình mỗi phiên | 1 tiến trình nhỏ | 0 | 1 tiến trình nhỏ |
| RAM 10 phiên (Swift) | khoảng 18 MB [KIỂM: 1,8 MB mỗi tiến trình] | 0 thêm | khoảng 18 MB |
| Khi app tắt | Shim trả "chưa biết" hoặc tự đọc số đo cơ bản | MCP chết hẳn | Vẫn chạy: đọc sysctl, phối hợp qua tệp |
| Trạng thái chung (giữ chỗ, tin nhắn) | Trong app, một nguồn sự thật | Trong app | Tệp JSON + `flock` trong Application Support |
| Bề mặt tấn công | Socket 0600, kiểm UID bằng `getpeereid` | Cổng mạng local: DNS rebinding, kiểm Origin, token nằm trong tệp cấu hình của client | Không có cổng, không có socket. Chỉ tệp 0600 |
| Đúng nguyên tắc đã chốt | Đúng | **Sai** ("không mở server HTTP trên máy") | Đúng |
| Độ phức tạp | Trung bình: app phải chạy server socket, viết giao thức nội bộ | Trung bình: HTTP, token, Origin | Thấp nhất. Cần cẩn thận khoá tệp và dọn chỗ giữ đã hết hạn |
| Độ tươi số đo | Tốt: app lấy mẫu 5 giây một lần | Tốt | Đọc trực tiếp ngay khi hỏi. Tốc độ swap cần hai mẫu: đọc tệp số đo của app nếu còn mới, không thì lấy mẫu 1 giây |

Đề xuất: **(c) trước, rồi (a) nếu cần.**

- Giai đoạn 1 dùng (c). Chương trình `8gbvibe-mcp` là một executable Swift riêng trong gói app, không dùng SwiftUI. Nó đọc sysctl qua VibeCore, đọc tệp trạng thái app ghi ra, và ghi các chỗ giữ, tin nhắn, yêu cầu dọn dẹp vào thư mục `~/Library/Application Support/8GB Vibe/agents/` (0700, tệp 0600).
- App đọc các tệp này để hiện ai đang giữ gì, và để hiện yêu cầu dọn dẹp chờ duyệt.
- Chuyển sang (a) khi số phiên lớn làm tranh chấp tệp, hoặc khi cần thông báo tức thời.

Đo trên máy này (MacBook Air M2 8 GB, áp lực mức cảnh báo, 08/11/2026). Mỗi chương trình đọc một dòng JSON và trả một dòng JSON, đo 5 lần [KIỂM]:

| Chương trình | Khởi động và trả lời lần đầu (đã nạp sẵn) | Footprint | RSS |
|---|---|---|---|
| Swift tối giản (Foundation) | 3 ms | 1,8 MB | 4 MB |
| Swift có liên kết AppKit và SwiftUI | 4 ms | 1,8 MB | 4 MB |
| Python 3 | 19 ms | 6,9 MB | 13 MB |
| Node | 63 ms | 16 MB | 33 MB |

- Lần chạy đầu tiên khi chưa nạp sẵn mất 0,4 đến 0,9 giây (máy đang swap) [KIỂM].
- Số liệu người dùng báo: Node qua npx khoảng 45 đến 50 MB mỗi tiến trình (gồm npm wrapper); Python qua uvx khoảng 17 MB [PHỤ, issue #28860].
- Chưa đo bản dùng swift-sdk (có swift-nio) [GIẢ ĐỊNH: vài MB thêm, cần đo ở giai đoạn 0].
- Kết luận: Swift tự viết, mỏng, khoảng 2 MB mỗi phiên. Với 10 phiên là khoảng 20 MB, nhỏ hơn một tab trình duyệt.

## 3. Bộ tool đề xuất

Mọi tool đều trả `measured_at` và `data_age_s`, và trả "unknown" khi không có dữ liệu. Đây là yêu cầu đã chốt cho `8gb status` ở bước 2.

### 3.1. Mức Đọc (`readOnlyHint: true`)

| Tool | Trả về |
|---|---|
| `machine_status` | RAM đã dùng, swap đã dùng, tốc độ swap (MB/phút), áp lực, điểm sức khoẻ, hồ sơ phần cứng (8/16/24 GB), có đang "căng" không, cảnh báo "Máy sắp đơ" nếu có |
| `heavy_processes(limit)` | Nhóm và tiến trình tốn RAM nhất, đã gộp theo nhóm (không trả tham số dòng lệnh, tránh lộ token) |
| `agent_sessions` | Các phiên agent đang chạy: công cụ, dự án, RAM, rảnh bao lâu, MCP con |
| `hardware_profile` | Nội dung `hardware.json` và hồ sơ đang dùng |
| `can_start(kind, estimate_mb?)` | `kind`: xcode_build, swift_build, gradle, simulator, docker, npm_build, tests, other. Trả `go`, `wait` hoặc `no`, kèm lý do ("áp lực mức cảnh báo, swap 2 GB/phút, đang có 1 build Gradle"), số giây nên chờ, độ tuổi dữ liệu. Chỉ là lời khuyên |

### 3.2. Mức Phối hợp (ghi vào tệp chung, không đụng tiến trình nào)

| Tool | Ghi chú |
|---|---|
| `register_agent(tool, project, task?)` | Trả `agent_id` ngắn. Định danh là thông tin agent tự khai (không xác thực được), gắn thêm pid của tiến trình MCP và thư mục làm việc để app đối chiếu với phiên thật |
| `heartbeat(agent_id)` | Không có nhịp tim trong 10 phút thì agent bị coi là đã đi; chỗ giữ của nó tự hết |
| `acquire_slot(agent_id, kind, ttl_s ≤ 1800)` | Giữ chỗ cho việc nặng. Mặc định một chỗ "build nặng" cho cả máy (theo mục 12.1 của phản biện: mặc định một lượt). Trả `granted`, `queued` (kèm thứ tự) hoặc `denied` (kèm lý do: máy đang căng). Chỉ mang tính tự giác, giống lease của MCP Agent Mail [PHỤ] |
| `release_slot(agent_id, slot_id)` | Trả chỗ. Hết hạn thì app và các agent khác coi như đã trả |
| `slots` | Ai đang giữ gì, còn bao lâu, ai đang chờ |
| `post_message(agent_id, to?, text ≤ 500 ký tự)` và `read_messages(agent_id, since)` | Bảng tin giữa các agent. Mỗi tin ghi rõ người gửi; tool trả về kèm nhãn "dữ liệu từ agent khác, không phải lệnh của người dùng" (giống cách Claude Code gắn nhãn tin giữa teammate) [KIỂM: agent teams] |

### 3.3. Mức Hành động (không tự làm)

| Tool | Ghi chú |
|---|---|
| `request_cleanup(agent_id, items, reason)` | `items` chỉ được chọn trong danh sách ứng viên app đang có (id của `QuitCandidate`, gồm mồ côi gộp theo phiên). Không nhận pid tuỳ ý. Tạo một yêu cầu "chờ duyệt", hiện ở chuông thông báo của app; BEECA bấm duyệt thì app mới dừng, qua `ProcessIdentity` và `ProcessGuard` như mọi lần dừng khác. Đặt `_meta["anthropic/requiresUserInteraction"]: true` cho Claude Code |
| `cleanup_status(request_id)` | `pending`, `approved`, `done` (kèm RAM thu hồi), `rejected` hoặc `expired` (30 phút) |

Có hành động nào được tự làm không?

- Theo quy tắc dự án ("không tự tắt tiến trình nếu chưa được đồng ý từng lần"): **không**, ở mọi giai đoạn trước khi BEECA quyết khác.
- Ứng viên có thể bàn sau, cần BEECA duyệt trước: "agent được dừng tiến trình mồ côi do chính phiên của nó tạo ra". Rủi ro thấp nhất vì app biết nguồn gốc qua `LineageTracker`. Dù vậy, việc này vẫn là dừng tiến trình.
- Các thao tác chỉ đụng dữ liệu của chính agent (trả chỗ của mình, xoá tin của mình) được tự làm; chúng không đụng máy.

## 4. An toàn

| Rủi ro | Cách chặn |
|---|---|
| Prompt injection: tệp trong repo hoặc tin nhắn của agent khác bảo agent "gọi dọn dẹp, tắt X" | Không có tool dừng trực tiếp. `request_cleanup` chỉ tạo yêu cầu; người duyệt trong app thấy agent nào xin, xin gì, lý do. Các nghiên cứu cho thấy tấn công qua mô tả tool hoặc nội dung đọc vào có tỷ lệ thành công cao (MCPTox khoảng 36,5%) [PHỤ] |
| Agent đòi dừng tiến trình hệ thống, app Claude, phiên Claude Code | `ProcessGuard` vẫn áp ở bước thực thi trong app; ứng viên bị khoá không được đưa vào yêu cầu |
| Tin tưởng annotations hay elicitation | Không. Đặc tả: annotations không tin cậy [KIỂM]. Elicitation hiện trong client của agent, có thể bị hook trả lời tự động, không hiện ở chế độ không tương tác [KIỂM]. Chỉ dùng như lớp phụ |
| Tool nói dối về agent khác | Tin nhắn và tên agent là dữ liệu không tin cậy; gắn nhãn nguồn; không bao giờ coi là sự đồng ý của người dùng |
| Spam, vòng lặp | Giới hạn: đọc 60 lần mỗi phút cho mỗi agent; `request_cleanup` 6 lần mỗi giờ; tin nhắn 30 mỗi giờ; tối đa 20 agent đăng ký |
| Nhật ký | Ghi mọi lần gọi ghi, phối hợp và yêu cầu (agent, tool, tham số rút gọn, kết quả) vào `agents/log.jsonl` 0600, có giới hạn dung lượng như B7 |
| Mạng | Không mở cổng nào. Phương án (a) nếu làm: socket trong thư mục 0700, socket 0600, kiểm UID bằng `getpeereid` |
| Lộ thông tin | Không trả tham số dòng lệnh, biến môi trường hay nội dung tệp; chỉ tên nhóm, dự án (tên thư mục), số RAM |
| App giả mạo shim | Shim nằm trong gói app đã ký Developer ID và notarize; đường dẫn cài trỏ vào `/Applications/8GB Vibe.app/...` |

Quy tắc dự án vẫn giữ nguyên: không tự tắt tiến trình, không xoá tệp, không đổi cài đặt hệ thống nếu chưa được đồng ý từng lần.

## 5. Liên hệ lộ trình đã chốt

| Lộ trình (CHUC_NANG mục 3, phản biện mục 12) | MCP |
|---|---|
| Bước 1, Đo | Đã có dữ liệu cho `machine_status` (số đo mỗi phút, tốc độ swap, việc nặng) |
| Bước 2, `8gb status` tối thiểu | MCP mức Đọc là `8gb status` có cấu trúc. Đề xuất dùng chung một lõi: `8gbvibe-mcp status --json` cho CLI, và tool `machine_status` cho MCP |
| Bước 3, Thu hồi theo phiên | `request_cleanup` dựa đúng trên nền này (mồ côi gộp theo phiên, có duyệt) |
| Bước 4, Hàng đợi việc nặng (chỉ làm nếu dữ liệu cần) | `acquire_slot` là hàng đợi ở mức tự giác. Bắt buộc thật cần hook `PreToolUse`: hook gọi shim xin chỗ trước `xcodebuild`, `gradle`... Theo quyết định đã chốt, hook là tuỳ chọn, mặc định tắt |
| Điều khiển từ xa | Không liên quan. MCP chỉ local |

**MCP hay hook?**

- Bổ sung cho nhau. Tài liệu Claude Code: CLAUDE.md "is context, not enforced configuration... use a PreToolUse hook" [KIỂM].
- Hook dùng cho vòng đời và cưỡng chế: SessionStart thì đăng ký, Stop thì trả chỗ, PreToolUse thì xin chỗ.
- MCP dùng cho câu hỏi chủ động và phối hợp. Codex cũng có `PreToolUse` [KIỂM].

**Sản phẩm tương tự:**

| Sản phẩm | Làm gì | Khác 8GB Vibe | Nguồn |
|---|---|---|---|
| kill-process-mcp | Liệt kê và kill tiến trình | Kill trực tiếp, không có danh sách bảo vệ, không duyệt | [KIỂM] README |
| mac-monitor-mcp, System Monitor MCP | Đọc CPU, RAM; có cái cho kill | Không đo áp lực bộ nhớ hay swap của macOS | [PHỤ] |
| MCP Agent Mail | Đăng ký agent, hộp thư, giữ tệp (lease có TTL, tự giác), HTTP local có token | Giữ tệp, không giữ tài nguyên máy. Agent hay quên đọc hộp thư | [KIỂM] README |
| Claude Code agent teams | Danh sách việc, hộp thư, khoá tệp | Chỉ trong một phiên Claude, không giữa các hãng | [KIỂM] |
| Claude Squad, Conductor, Vibe Kanban | Chạy song song theo worktree | Không giữ chỗ RAM hay CPU | [PHỤ] |

Chưa thấy sản phẩm nào kết hợp giám sát RAM và swap macOS, giữ chỗ việc nặng giữa các agent khác hãng, và duyệt dọn dẹp ngoài kênh [PHỤ, tìm chưa thấy không có nghĩa là không có].

## 6. Giai đoạn, rủi ro, công sức

Ước tính theo phiên làm việc, mỗi phiên 1 đến 3 giờ [GIẢ ĐỊNH].

| Giai đoạn | Nội dung | Điều kiện xong | Công sức |
|---|---|---|---|
| 0. Thử | Executable `8gbvibe-mcp` tối giản (stdio, JSON-RPC tự viết) và một bản dùng swift-sdk; đo RAM, thời gian khởi động, kích thước; nhóm phát triển tự cài vào Claude Code một phiên để thử | Chọn SDK hay tự viết; số đo ghi vào tài liệu | 1 |
| 1. Đọc + `8gb status` | `machine_status`, `heavy_processes`, `agent_sessions`, `hardware_profile`, `can_start`; app ghi `status.json` mỗi 5 giây khi có shim đang dùng (hoặc shim tự đọc) | Một agent thật đọc được và làm theo lời khuyên trong demo | 2 |
| 2. Phối hợp | `register_agent`, `heartbeat`, giữ chỗ, bảng tin; app hiện "ai đang giữ gì" | Hai phiên Claude không build Xcode cùng lúc khi cả hai tự giác dùng tool | 2 |
| 3. Yêu cầu dọn dẹp | `request_cleanup`, `cleanup_status`, duyệt trong chuông thông báo của app | Không có đường nào để agent dừng tiến trình mà không qua người duyệt; nhật ký đủ | 2 |
| 4. Tuỳ chọn: cưỡng chế | Hook `PreToolUse` cho Claude Code và Codex gọi `can_start`/`acquire_slot`; cài và gỡ có xác nhận | Chỉ làm nếu dữ liệu bước 1 của lộ trình cho thấy việc nặng chồng nhau là nguyên nhân căng | 1 đến 2 |

Rủi ro:

- **Agent không gọi tool.** Hướng dẫn trong CLAUDE.md không được tuân thủ ổn định [PHỤ]. Giảm rủi ro: mô tả tool rõ, câu mẫu cho CLAUDE.md và AGENTS.md, hook ở giai đoạn 4.
- **Đặc tả đổi nhanh.** Bản 2026-07-28 vừa bỏ trạng thái phiên. Giữ giao thức tối giản và hỗ trợ cả hai kiểu.
- **swift-sdk còn 0.x.** Nếu dùng thì ghim phiên bản.
- **Tranh chấp tệp khi nhiều agent cùng ghi.** Dùng `flock`, ghi nguyên tử, dọn chỗ giữ hết hạn khi đọc.
- **Định danh agent tự khai.** Không dựa vào nó cho quyết định an toàn; mọi hành động vẫn qua người duyệt.
- **Mỗi phiên một tiến trình:** khoảng 2 MB mỗi phiên là chấp nhận được. Nếu dùng SDK làm tăng nhiều thì quay về JSON-RPC tự viết.

## 7. Câu cần BEECA quyết

1. Đồng ý hướng "MCP chỉ đọc và phối hợp; dọn dẹp chỉ tạo yêu cầu, anh duyệt trong app" không?
2. Chọn kiến trúc (c) cho giai đoạn 1 (không socket, không cổng; phối hợp qua tệp có khoá) không?
3. Có cho phép, sau này, một quy tắc duyệt trước: "agent được dừng tiến trình mồ côi do chính phiên của nó tạo ra" không? Mặc định là không.
4. Cài MCP vào client: chỉ hướng dẫn và chép lệnh cho anh tự chạy, hay app có nút "Cài vào Claude Code" (có xác nhận, hiện đoạn sẽ thêm, có nút gỡ)?
5. Thứ tự với lộ trình: làm giai đoạn 0 và 1 như phần mở rộng của bước 2 (`8gb status`) ngay, hay chờ thêm dữ liệu đo?

### 7.1. Quyết định của BEECA (08/11/2026)

1. **Mặc định chỉ đọc và phối hợp; dọn dẹp chỉ tạo yêu cầu chờ duyệt trong app.** Cài đặt có mức quyền rõ ràng, người dùng tự chọn: "Chỉ đọc", "Đọc + phối hợp" (mặc định), "Cho phép tự làm việc rủi ro thấp" (mặc định tắt, làm ở giai đoạn sau). Mọi hành động vẫn qua `ProcessGuard`.
2. **Agent tự dừng tiến trình mồ côi do chính phiên của nó tạo:** mặc định luôn hỏi. Cài đặt có công tắc cho phép, có nhật ký, và chỉ có hiệu lực khi máy thiếu RAM (áp lực bộ nhớ từ mức cảnh báo, hoặc theo hồ sơ máy). Ngoài lúc đó vẫn phải hỏi. Làm ở giai đoạn sau; giai đoạn 1 đã có sẵn chỗ trong tệp chính sách.
3. **Cài vào client:** app có nút "Cài vào Claude Code" (hiện đoạn sẽ thêm, xác nhận, có nút gỡ). Client khác chỉ hiện lệnh hoặc đoạn cấu hình để chép.
4. **Làm ngay giai đoạn 0 và 1** (đọc + phối hợp), coi như bước 2 `8gb status`. Kiến trúc (c).

### 7.2. Kết quả giai đoạn 0 và 1 (08/11/2026)

- **Tự viết JSON-RPC, không dùng swift-sdk.** Lý do: chỉ cần stdio và tools; tránh swift-nio và API 0.x; nói được cả `initialize` (2025) và `server/discover` (2026-07-28). Chưa đo bản dùng swift-sdk; không cần vì bản tự viết đã đủ nhẹ.
- Chương trình: `8gbvibe-mcp` (target `VibeMCP`), nằm trong `8GB Vibe.app/Contents/Helpers/`, được ký cùng app. Phần xử lý nằm ở `VibeCore/VibeMCPServer.swift` và `VibeCore/AgentHub.swift`, có test.
- Đo bản release trên máy này [KIỂM]:

| Tình huống | Khởi động + `initialize` | `machine_status` | Footprint |
|---|---|---|---|
| App đang chạy (đọc `agents/status.json`) | 12 ms (đã nạp sẵn) | 3 ms | 2,6 MB lúc nhàn; 5,6 đến 5,9 MB sau khi quét tiến trình |
| App tắt (tự đo, lấy hai mẫu cách 1 giây) | 476 ms (lần đầu) | khoảng 1 giây | như trên |

  Kích thước tệp 1,8 MB. Với 10 phiên agent: khoảng 26 đến 60 MB tổng.
- App chỉ ghi `agents/status.json` (khoảng 1 KB mỗi 5 giây) khi có agent đã đăng ký và còn hoạt động trong 10 phút.
- Tệp: `~/Library/Application Support/8GB Vibe/agents/` (0700): `state.json`, `policy.json`, `status.json`, `log.jsonl` (0600, tối đa 1 MB).
- Mức quyền "Chỉ đọc" ẩn các tool phối hợp. Mức "Tự làm việc rủi ro thấp" và công tắc tự dừng mồ côi đã có chỗ trong `policy.json`, nhưng chưa có việc nào được tự làm.
- Thử chạy tay bằng stdin (không cài vào cấu hình Claude của máy): `initialize`, `tools/list`, `machine_status`, `can_start` (trả "wait" vì máy đang căng), `register_agent`, `acquire_slot` (granted), `heavy_processes` đều đúng.

### 7.3. Đợt 1 nâng cấp (08/11/2026)

Theo phạm vi nâng cấp đã duyệt nội bộ. Phối hợp vẫn là tự giác; không tool nào dừng tiến trình.

- **`acquire_slot` tách lượt và lời khuyên.** Trả `slot` (`granted`, `already_held`, `queued` kèm `position`, `holder`, `seconds_left`), `advice` (`decision`, `reason`, `data_age_s`, `retry_after_s`, `confidence`, `window_s`) và `start_now` (chỉ `true` khi đã có lượt và lời khuyên là `go`). Có lượt không có nghĩa là máy đủ RAM.
- **`can_start` tính cả hàng đợi.** Chủ slot không thấy mình là đối thủ. Có người chờ trước thì trả `wait` kèm số thứ tự.
- **`renew_slot`** (chỉ chủ slot, mỗi lần tối đa 30 phút, tổng tối đa 2 giờ, quá thì trả lý do và giờ muộn nhất), **`my_slots`** (lấy lại slot và vị trí khi agent mất ngữ cảnh). Trả slot lần 2: `already_released`.
- **Sống theo tiến trình MCP.** Tiến trình `8gbvibe-mcp` tự cập nhật `lastSeen` mỗi 60 giây. Agent hết khi đúng tiến trình đó (pid và giờ khởi động) không còn; pid bị tái dùng không được tính là còn sống. Hạn 10 phút chỉ còn là lưới an toàn.
- **`lease` và `task` tách biệt.** `lease`: `active` (trong hạn), `expired` (hết hạn, việc còn chạy), `overdue` (quá tổng 2 giờ, việc còn chạy). `task`: `running` (thấy việc nặng con cháu của phiên giữ slot, tức tiến trình cha của MCP), `ended` (biết phiên, không thấy việc nặng nào lúc này; có thể là chưa bắt đầu), `unknown` (không biết phiên). Slot hết hạn mà việc còn chạy không cấp cho người khác, ghi `busy_with`, không dừng gì; việc nặng xong thì slot tự giải phóng. `overdue` không bao giờ tự coi là trống: app báo ở chuông và có nút "Nhả chỗ" (hỏi trước, ghi nhật ký, không đụng tiến trình).
- **Hàng đợi công bằng.** Người đầu hàng không hỏi lại trong 2 lần `retry_after_s` thì nhường lượt (vẫn giữ chỗ phía sau). Agent chết thì rời hàng.
- **`state.json` hỏng** được đổi tên thành `state.json.bad-<giờ>`, ghi nhật ký, app báo ở chuông. Không ghi đè âm thầm.
- **Không đoán số.** Swap chưa đo được thì `swap_mb_per_min: "unknown"`, lời khuyên `go` kèm `confidence: low`; thiếu cả áp lực thì `unknown`. Đọc trực tiếp khi app tắt có `source: direct`, `window_s: 1`.
- **Một chỗ việc nặng cho mọi bậc máy** (bỏ 2 chỗ cho 24 GB). Đây là chính sách phối hợp bảo thủ, không phải giới hạn của máy; `hardware_profile` trả kèm câu này. Chưa có tuỳ chọn tăng số chỗ. Bỏ hệ số Intel 0,6.

Kiểm bằng 125 test đơn vị và bộ chạy thật nhiều tiến trình `8gbvibe-mcp` trong thư mục tạm (`VIBE_AGENTS_DIR`), việc nặng giả là bản chép của `/bin/sleep` đặt tên `xcodebuild`. Chưa cài MCP vào Claude Code của máy này (bài 23 chờ duyệt).

Đo bản release sau đợt 1 trên máy này, 08/11/2026 [KIỂM] (`footprint`, CPU tính trên 120 giây, app chạy với thư mục dữ liệu tạm):

| Đối tượng | Kết quả | Mức yêu cầu |
|---|---|---|
| App chạy nền | 18 MB, CPU 0,41 % | dưới 30 MB, dưới 1 % |
| `8gbvibe-mcp` lúc nhàn | 2,6 MB, CPU 0 % (có nhịp 60 giây) | dưới 8 MB |
| `8gbvibe-mcp` sau `machine_status` (đọc trực tiếp) và quét tiến trình | 3,4 MB | |

## 8. Cài vào các client agent trên máy (08/11/2026)

Theo yêu cầu của BEECA: không chỉ Claude Code; client nào có trên máy thì cài được. Mã: `VibeCore/MCPClients.swift`, giao diện `EightGBVibe/MCPClientsView.swift`.

### 8.1. Đường dẫn và lệnh theo tài liệu chính thức (đọc 08/11/2026)

| Client | Nhận diện (chỉ kiểm tồn tại) | Cách cài | Tệp đọc trạng thái | Nguồn |
|---|---|---|---|---|
| Claude Code | lệnh `claude` (PATH của shell đăng nhập, `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`) | `claude mcp add --transport stdio --scope user 8gbvibe -- <server>`; gỡ `claude mcp remove --scope user 8gbvibe`. Mặc định là phạm vi local nên phải ghi `--scope user` | `~/.claude.json`, mục `mcpServers` cấp cao nhất (tài liệu nói máy chủ phạm vi user nằm "at the top level", không ghi tên khoá; tên khoá là suy ra) | https://code.claude.com/docs/en/mcp |
| Codex | lệnh `codex`, kể cả bản trong `ChatGPT.app/Contents/Resources/codex-cli/bin/codex` | `codex mcp add 8gbvibe -- <server>`; gỡ `codex mcp remove 8gbvibe` (kiểm bằng `codex mcp --help` trên máy này). Không có lệnh mà có `~/.codex/config.toml` thì sửa tệp | `~/.codex/config.toml`, bảng `[mcp_servers.8gbvibe]` | https://developers.openai.com/codex/mcp (chuyển tới learn.chatgpt.com/docs/extend/mcp) |
| Gemini CLI | lệnh `gemini` | `gemini mcp add -s user 8gbvibe <server>`; gỡ `gemini mcp remove -s user 8gbvibe`. Mặc định là phạm vi project nên phải ghi `-s user` | `~/.gemini/settings.json`, `mcpServers` | https://geminicli.com/docs/tools/mcp-server/ (trang ghi Gemini CLI đã được thay bằng Antigravity CLI từ 18/06/2026) |
| Cursor | `Cursor.app` hoặc thư mục `~/.cursor` | sửa tệp | `~/.cursor/mcp.json`, `mcpServers` | https://cursor.com/docs/context/mcp |
| Claude Desktop | `Claude.app` | sửa tệp; phải thoát hẳn rồi mở lại app | `~/Library/Application Support/Claude/claude_desktop_config.json`, `mcpServers` | https://modelcontextprotocol.io/docs/develop/connect-local-servers |
| Antigravity (app và CLI) | `Antigravity.app` hoặc tệp cấu hình | sửa tệp | `~/.gemini/config/mcp_config.json`, `mcpServers`, `command` và `args` cho stdio. Tài liệu chính thức không còn nhắc `~/.gemini/antigravity/mcp_config.json` (đường dẫn cũ trong vài hướng dẫn) | https://antigravity.google/docs/mcp |

Chưa thấy trong tài liệu chính thức: Cursor có tự nạp lại cấu hình không; Codex CLI có cần mở lại không. App luôn ghi "Cần mở lại <client> để nhận thay đổi".

### 8.2. An toàn khi ghi cấu hình của app khác

- Ưu tiên lệnh chính thức của client. Chỉ sửa tệp khi client không có lệnh (Cursor, Claude Desktop, Antigravity) hoặc không tìm thấy lệnh `codex`.
- Hộp xác nhận hiện đúng lệnh sẽ chạy, hoặc đường dẫn tệp và đúng đoạn sẽ thêm.
- Sửa tệp:
  - Sao lưu trước thành `<tên>.bak-8gbvibe-<yyyyMMdd-HHmmss>`, cùng quyền tệp.
  - Chỉ thêm hoặc xoá đúng khoá `8gbvibe`. Sửa trực tiếp trên văn bản, mọi phần khác giữ nguyên từng byte (khoảng trắng, thứ tự, máy chủ khác). Sau khi sửa, app đọc lại và so: ngoài khoá `8gbvibe` phải giống hệt trước, không khớp thì không ghi.
  - Ghi nguyên tử (tệp tạm trong cùng thư mục rồi đổi tên), giữ quyền tệp cũ, đi theo liên kết tượng trưng.
  - Tệp hỏng, có chú thích hay không phải JSON thường, hoặc `mcpServers` không phải đối tượng: không ghi, báo lỗi. Tệp rỗng (như tệp Antigravity trên máy này) được coi là `{}`.
  - Gỡ chỉ xoá khoá của mình và trả tệp về đúng từng byte như trước khi cài. Lúc cài, app ghi dấu tệp trước đó trông thế nào vào `~/Library/Application Support/8GB Vibe/mcp-installs.json` (0600): chưa có tệp, tệp rỗng, chưa có `mcpServers`, hay đã có. Lúc gỡ, nếu `mcpServers` chỉ còn rỗng và do 8GB Vibe tạo thì xoá luôn; tệp rỗng thì trả lại đúng nội dung rỗng cũ; tệp do 8GB Vibe tạo thì xoá tệp (bản sao lưu vẫn còn). `mcpServers` có sẵn từ trước, hoặc người dùng đã thêm máy chủ khác vào sau, thì giữ nguyên. Cài bằng bản cũ (chưa có dấu) thì chỉ xoá khoá.
- Mỗi lần cài hoặc gỡ ghi vào nhật ký của app ("Cài MCP" / "Gỡ MCP", client, lệnh hoặc tệp, kết quả).
- "Đã cài" là đã ghi cấu hình. "Đã kết nối" là có agent đã gọi `register_agent` với tên client đó (tên tự khai, không xác thực). Hai thứ hiện riêng.

### 8.3. Kiểm thử

- `MCPClientsTests` (HOME và /Applications giả trong thư mục tạm): nhận diện chỉ client có mặt; lệnh đúng cờ phạm vi; JSON có sẵn máy chủ khác (cài rồi gỡ trả lại đúng văn bản gốc, giữ quyền 0644, có 2 bản sao lưu); thiếu `mcpServers`, `{}`, tệp rỗng; tệp hỏng không bị ghi và không có bản sao lưu; TOML có bảng con và bảng khác; "đã kết nối" tách khỏi "đã cài".
- Chạy cài rồi gỡ trên bản sao trong thư mục tạm của tệp cấu hình thật trên máy này: Codex, Claude Desktop và Antigravity (tệp rỗng) đều trả lại đúng từng byte. Không ghi vào tệp thật, chưa bấm cài thật (bài 23 chờ duyệt).

## Nguồn chính

- Đặc tả MCP: https://modelcontextprotocol.io/specification/latest ; changelog 2026-07-28 ; transports ; authorization ; server/tools ; client/elicitation ; security best practices (mục Local MCP Server Compromise).
- Swift SDK: https://github.com/modelcontextprotocol/swift-sdk (Package.swift, README, releases).
- Claude Code MCP: https://code.claude.com/docs/en/mcp ; hooks: https://code.claude.com/docs/en/hooks ; memory: https://code.claude.com/docs/en/memory ; agent teams: https://code.claude.com/docs/en/agent-teams
- Issue nhân bản MCP theo phiên: https://github.com/anthropics/claude-code/issues/28860
- Codex MCP và hooks: https://learn.chatgpt.com/docs/extend/mcp?surface=cli ; https://learn.chatgpt.com/docs/hooks
- Antigravity MCP: https://antigravity.google/docs/mcp ; Gemini CLI: https://geminicli.com/docs/tools/mcp-server/ ; Cursor: https://cursor.com/docs/context/mcp
- Sản phẩm tương tự: https://github.com/misiektoja/kill-process-mcp ; https://github.com/Dicklesworthstone/mcp_agent_mail
- An toàn: https://invariantlabs.ai/blog/mcp-security-notification
