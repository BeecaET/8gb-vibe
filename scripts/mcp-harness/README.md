# Multi-process MCP harness (round 1)

Runs several real `8gbvibe-mcp` processes, each test in its own temporary folder (`VIBE_AGENTS_DIR`). The fake heavy job is a C program that only sleeps, named `xcodebuild`. The harness only stops child processes it started itself.

```bash
swift build -j 2 --product 8gbvibe-mcp
cc -O0 -o /tmp/fake/xcodebuild scripts/mcp-harness/fake_xcodebuild.c
FAKE_JOB=/tmp/fake/xcodebuild python3 -I scripts/mcp-harness/mcp_harness.py "$(swift build --show-bin-path)/8gbvibe-mcp" 2 10 11 12 17
```

Test 9 waits `SILENT_S` seconds (default 720): `python3 -I scripts/mcp-harness/mcp_harness.py <bin> 9`.
