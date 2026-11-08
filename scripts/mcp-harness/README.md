# Bộ chạy thử MCP nhiều tiến trình (đợt 1)

Chạy nhiều tiến trình `8gbvibe-mcp` thật, mỗi bài một thư mục tạm (`VIBE_AGENTS_DIR`). Việc nặng giả là chương trình C chỉ ngủ, tên `xcodebuild`. Bộ thử chỉ dừng tiến trình con do chính nó mở.

```bash
swift build -j 2 --product 8gbvibe-mcp
cc -O0 -o /tmp/fake/xcodebuild scripts/mcp-harness/fake_xcodebuild.c
FAKE_JOB=/tmp/fake/xcodebuild python3 -I scripts/mcp-harness/mcp_harness.py "$(swift build --show-bin-path)/8gbvibe-mcp" 2 10 11 12 17
```

Bài 9 chờ `SILENT_S` giây (mặc định 720): `python3 -I scripts/mcp-harness/mcp_harness.py <bin> 9`.
