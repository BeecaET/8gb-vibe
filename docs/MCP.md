# 8GB Vibe MCP server: design and research

- Date: 08/11/2026. Author: the development team. Research first, then implementation (status in section 7).
- Goal: give AI agents an MCP server through which they can read the Mac's hardware state, request cleanup and coordinate with each other, researched carefully before any code was written.
- Source tags:
  - **[VERIFIED]**: read in official documentation or measured on the test Mac (MacBook Air M2, 8 GB).
  - **[SECONDARY]**: secondary source (blog, issue, directory).
  - **[ASSUMPTION]**: inference or estimate, not verified.

## 0. Summary

1. **Worth building, as "MCP is read-only plus coordination; every destructive action is approved by a person in the app".** No existing product combines macOS RAM and swap monitoring, heavy-job slots shared between agents from different vendors, and cleanup approval outside the agent channel [SECONDARY].
2. **Every agent session gets its own MCP process.** Claude Code starts one stdio process per session, not a shared one [VERIFIED, documentation and issue #28860]. With 5 to 10 sessions, the RAM of the MCP process is the deciding factor. Measured on the test Mac: a minimal Swift stdio process has a **1.8 MB** footprint, Python 6.9 MB, Node 16 MB [VERIFIED]. So the MCP server must be a very thin Swift program, not Node or Python.
3. **No HTTP port.** The project rule is "no HTTP server on the machine". Use stdio; share state between sessions through locked files in Application Support (phase 1), or a 0600 Unix socket to the app (later, if needed).
4. **Elicitation and tool annotations are not a safety layer.** The MCP specification says clients MUST treat annotations as untrusted [VERIFIED]. Elicitation is shown inside the agent's own client and can be auto-answered by a hook [VERIFIED]. Cleanup must be approved in the 8GB Vibe app.
5. **MCP complements hooks, it does not replace them.** MCP is for when the agent asks on its own initiative. Hooks (`PreToolUse`) are for enforcement, because CLAUDE.md is context, not an enforced rule [VERIFIED, Claude Code documentation].

## 1. State of MCP

### 1.1. Specification

| Item | Content | Source |
|---|---|---|
| Latest version | 2026-07-28; previous 2025-11-25 | [VERIFIED] modelcontextprotocol.io/specification/latest |
| Major changes in 2026-07-28 | Stateless: the `initialize` handshake is removed, each request carries `protocolVersion` and client capabilities in `_meta`; adds `server/discover` (required); removes `Mcp-Session-Id`; `subscriptions/listen` replaces `resources/subscribe`; removes `ping` and `logging/setLevel`; elicitation returns `InputRequiredResult` instead of the server sending a request back | [VERIFIED] .../2026-07-28/changelog |
| No longer recommended | Roots, Sampling, Logging (write to stderr), HTTP+SSE, Dynamic Client Registration | [VERIFIED] |
| Transport | stdio and Streamable HTTP. HTTP+SSE no longer recommended. Local HTTP: server MUST check the `Origin` header, SHOULD bind 127.0.0.1, SHOULD authenticate | [VERIFIED] .../basic/transports |
| Authorization | Optional. HTTP should follow OAuth 2.1. stdio SHOULD NOT use OAuth, takes credentials from environment variables | [VERIFIED] .../basic/authorization |
| Tool annotations | `readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint`. "clients MUST consider tool annotations to be untrusted unless they come from trusted servers". There SHOULD always be a human able to deny | [VERIFIED] .../server/tools |
| Elicitation | Two modes: form (flat schema, must not ask for secrets) and URL. Result: accept, decline or cancel. Client MUST clearly show which server is asking | [VERIFIED] .../client/elicitation |
| Resources, notifications | Exist, but client support is uneven. Rely on tools only | [VERIFIED, section 1.3] |

Consequence: use stdio, no OAuth needed. Clients on 2025-11-25 are still common, so the server must speak both the old style (`initialize`) and the new one [ASSUMPTION: small effort with hand-written JSON-RPC].

### 1.2. Official Swift SDK (modelcontextprotocol/swift-sdk)

| Item | Content | Source |
|---|---|---|
| Version | 0.12.1 (07/05/2026), still 0.x so minor versions may change the API | [VERIFIED] GitHub releases |
| Supported spec | 2025-11-25 (except Tasks, Sampling-with-tools, part of authorization). No sign of 2026-07-28 support | [VERIFIED] / [ASSUMPTION] for 2026-07-28 |
| Minimum macOS | `.macOS("13.0")`, so it runs on macOS 13 | [VERIFIED] Package.swift |
| Tooling | swift-tools-version 6.1 (README says Swift 6.0+) | [VERIFIED] |
| Dependencies | swift-system, swift-log, eventsource, swift-nio 2.65+, swift-docc-plugin (main branch) | [VERIFIED] |
| Server transports | `StdioTransport`, stateful and stateless HTTP | [VERIFIED] README |

Assessment:

- The SDK is functionally sufficient.
- But it pulls in swift-nio and is itself still 0.x. Impact on RAM and build time not measured [ASSUMPTION].
- 8GB Vibe only needs stdio, JSON-RPC and a few tools. A hand-written JSON-RPC layer of a few hundred lines may be lighter with fewer dependencies [ASSUMPTION].
- Proposal: phase 0 measures both approaches, then picks one.

### 1.3. Clients and installation (stdio)

| Client | Command or config file | Scope | Notes | Source |
|---|---|---|---|---|
| Claude Code | `claude mcp add --transport stdio --scope user 8gbvibe -- <path>` | local (default, per project, `~/.claude.json`); project (`.mcp.json`, requires approval); user (`~/.claude.json`) | One process per session. Annotations are not used for auto-approval; `readOnlyHint` only allows parallel execution. `_meta["anthropic/requiresUserInteraction"]: true` forces a user prompt, even in auto-approve mode. Elicitation supports form and URL, only in an interactive terminal | [VERIFIED] code.claude.com/docs/en/mcp |
| Codex CLI | `codex mcp add 8gbvibe -- <path>`, file `~/.codex/config.toml` table `[mcp_servers.8gbvibe]` | user; `.codex/config.toml` for trusted projects | `default_tools_approval_mode` (`writes` mode prompts for tools that are not read-only) | [VERIFIED] |
| Gemini CLI | `gemini mcp add -s user 8gbvibe <path>`, `~/.gemini/settings.json` | user or project | Replaced by Antigravity CLI for many accounts since 18/06/2026 | [VERIFIED] |
| Antigravity (agy) | `~/.gemini/config/mcp_config.json`, `<workspace>/.agents/mcp_config.json` | global or workspace | No add command | [VERIFIED] antigravity.google/docs/mcp |
| Cursor | `~/.cursor/mcp.json` or `.cursor/mcp.json` | global or project | Has elicitation (mode unclear) | [VERIFIED] |

Installing into a client **modifies the agent's configuration**. Following the existing decision on hooks: off by default, installed only when the user clicks, the exact snippet shown, with an uninstall button. Nothing was installed on the test Mac during research.

## 2. Architecture: comparison

| | (a) stdio command + Unix socket to the app | (b) App opens HTTP 127.0.0.1 with token | (c) stdio only, direct reads; coordination via locked files |
|---|---|---|---|
| Processes per session | 1 small process | 0 | 1 small process |
| RAM for 10 sessions (Swift) | about 18 MB [VERIFIED: 1.8 MB per process] | 0 extra | about 18 MB |
| When the app is closed | Shim returns "unknown" or reads basic metrics itself | MCP is fully down | Still works: reads sysctl, coordinates via files |
| Shared state (slots, messages) | In the app, single source of truth | In the app | JSON files + `flock` in Application Support |
| Attack surface | Socket 0600, UID check with `getpeereid` | Local network port: DNS rebinding, Origin check, token stored in the client's config file | No port, no socket. Only 0600 files |
| Matches project rules | Yes | **No** ("no HTTP server on the machine") | Yes |
| Complexity | Medium: app runs a socket server, internal protocol | Medium: HTTP, token, Origin | Lowest. Needs care with file locking and cleaning up expired slots |
| Metric freshness | Good: app samples every 5 seconds | Good | Read directly on request. Swap rate needs two samples: read the app's metrics file if fresh, otherwise sample over 1 second |

Proposal: **(c) first, then (a) if needed.**

- Phase 1 uses (c). `8gbvibe-mcp` is a separate Swift executable inside the app bundle, without SwiftUI. It reads sysctl through VibeCore, reads the status file the app writes, and writes slots, messages and cleanup requests to `~/Library/Application Support/8GB Vibe/agents/` (0700, files 0600).
- The app reads these files to show who holds what, and to show pending cleanup requests.
- Move to (a) when many sessions cause file contention, or when instant notifications are needed.

Measured on the test Mac (MacBook Air M2, 8 GB, memory pressure at warning level, 08/11/2026). Each program reads one JSON line and writes one JSON line, 5 runs [VERIFIED]:

| Program | Startup and first reply (warm) | Footprint | RSS |
|---|---|---|---|
| Minimal Swift (Foundation) | 3 ms | 1.8 MB | 4 MB |
| Swift linking AppKit and SwiftUI | 4 ms | 1.8 MB | 4 MB |
| Python 3 | 19 ms | 6.9 MB | 13 MB |
| Node | 63 ms | 16 MB | 33 MB |

- The first cold run took 0.4 to 0.9 seconds (machine was swapping) [VERIFIED].
- User-reported figures: Node via npx about 45 to 50 MB per process (including the npm wrapper); Python via uvx about 17 MB [SECONDARY, issue #28860].
- The swift-sdk build (with swift-nio) was not measured [ASSUMPTION: a few MB more, to be measured in phase 0].
- Conclusion: thin hand-written Swift, about 2 MB per session. For 10 sessions about 20 MB, less than one browser tab.

## 3. Proposed tool set

Every tool returns `measured_at` and `data_age_s`, and returns "unknown" when data is missing. This is the agreed requirement for `8gb status` in step 2.

### 3.1. Read level (`readOnlyHint: true`)

| Tool | Returns |
|---|---|
| `machine_status` | RAM used, swap used, swap rate (MB/min), pressure, health score, hardware profile (8/16/24 GB), whether the machine is "strained", the "Mac about to freeze" warning if any |
| `heavy_processes(limit)` | Groups and processes using the most RAM, grouped (no command-line arguments, to avoid leaking tokens) |
| `agent_sessions` | Running agent sessions: tool, project, RAM, idle time, child MCP servers |
| `hardware_profile` | Contents of `hardware.json` and the active profile |
| `can_start(kind, estimate_mb?)` | `kind`: xcode_build, swift_build, gradle, simulator, docker, npm_build, tests, other. Returns `go`, `wait` or `no` with a reason ("pressure at warning level, swap 2 GB/min, 1 Gradle build running"), seconds to wait, and data age. Advice only |

### 3.2. Coordination level (writes to shared files, touches no process)

| Tool | Notes |
|---|---|
| `register_agent(tool, project, task?)` | Returns a short `agent_id`. Identity is self-declared by the agent (cannot be authenticated), tagged with the MCP process pid and working directory so the app can match it to a real session |
| `heartbeat(agent_id)` | No heartbeat for 10 minutes means the agent is considered gone; its slots expire |
| `acquire_slot(agent_id, kind, ttl_s <= 1800)` | Reserves a slot for a heavy job. Default is one "heavy build" slot for the whole machine (one at a time by default). Returns `granted`, `queued` (with position) or `denied` (with reason: machine is strained). Voluntary only, like the leases in MCP Agent Mail [SECONDARY] |
| `release_slot(agent_id, slot_id)` | Returns the slot. Once expired, the app and other agents treat it as returned |
| `slots` | Who holds what, time left, who is waiting |
| `post_message(agent_id, to?, text <= 500 characters)` and `read_messages(agent_id, since)` | Message board between agents. Each message records its sender; the tool returns it labeled "data from another agent, not a user instruction" (similar to how Claude Code labels messages between teammates) [VERIFIED: agent teams] |

### 3.3. Action level (never automatic)

| Tool | Notes |
|---|---|
| `request_cleanup(agent_id, items, reason)` | `items` may only be chosen from the app's current candidate list (`QuitCandidate` ids, including orphans grouped by session). Arbitrary pids are not accepted. Creates a "pending approval" request shown in the app's notification bell; only after the user approves does the app quit anything, through `ProcessIdentity` and `ProcessGuard` like every other quit. Sets `_meta["anthropic/requiresUserInteraction"]: true` for Claude Code |
| `cleanup_status(request_id)` | `pending`, `approved`, `done` (with RAM reclaimed), `rejected` or `expired` (30 minutes) |

Can any action be automatic?

- Under the project rule ("never quit a process without consent each time"): **no**, at every phase, unless BEECA decides otherwise.
- A candidate for later discussion, requiring BEECA approval first: "an agent may quit orphan processes created by its own session". Lowest risk, because the app knows their origin through `LineageTracker`. Still, it is quitting a process.
- Operations that only touch the agent's own data (releasing its own slot, deleting its own messages) may be automatic; they do not touch the machine.

## 4. Safety

| Risk | Mitigation |
|---|---|
| Prompt injection: a repo file or another agent's message tells the agent to "call cleanup, quit X" | No direct quit tool. `request_cleanup` only creates a request; the approver in the app sees which agent asked, for what, and why. Research shows attacks via tool descriptions or ingested content have high success rates (MCPTox about 36.5%) [SECONDARY] |
| Agent asks to quit system processes, the Claude app, a Claude Code session | `ProcessGuard` still applies at execution in the app; locked candidates cannot be included in a request |
| Trusting annotations or elicitation | No. Spec: annotations are untrusted [VERIFIED]. Elicitation is shown in the agent's client, can be auto-answered by a hook, and is not shown in non-interactive mode [VERIFIED]. Used only as a secondary layer |
| Tool lying about other agents | Messages and agent names are untrusted data; source is labeled; never treated as user consent |
| Spam, loops | Limits: 60 reads per minute per agent; `request_cleanup` 6 per hour; 30 messages per hour; at most 20 registered agents |
| Logging | Every write, coordination and request call (agent, tool, shortened arguments, result) is logged to `agents/log.jsonl` 0600, size-capped like the app's other logs |
| Network | No port opened. If option (a) is built: socket inside a 0700 directory, socket 0600, UID check with `getpeereid` |
| Information leakage | No command-line arguments, environment variables or file contents; only group names, project (folder name), RAM figures |
| Fake shim | The shim lives inside the app bundle signed with Developer ID and notarized; the install path points into `/Applications/8GB Vibe.app/...` |

Project rules are unchanged: never quit a process, delete a file or change a system setting without consent each time.

## 5. Relation to the approved roadmap

| Roadmap ([FEATURES.md](FEATURES.md) section 3) | MCP |
|---|---|
| Step 1, Measure | Data already available for `machine_status` (per-minute metrics, swap rate, heavy jobs) |
| Step 2, minimal `8gb status` | The MCP Read level is a structured `8gb status`. Proposal: share one core, `8gbvibe-mcp status --json` for the CLI and the `machine_status` tool for MCP |
| Step 3, Per-session reclaim | `request_cleanup` builds on exactly this (orphans grouped by session, with approval) |
| Step 4, Heavy-job queue (only if data calls for it) | `acquire_slot` is a voluntary queue. Real enforcement needs a `PreToolUse` hook: the hook calls the shim for a slot before `xcodebuild`, `gradle`... Per the existing decision, hooks are optional and off by default |
| Remote control | Not related. MCP is local only |

**MCP or hooks?**

- Complementary. Claude Code documentation: CLAUDE.md "is context, not enforced configuration... use a PreToolUse hook" [VERIFIED].
- Hooks handle lifecycle and enforcement: register on SessionStart, release slots on Stop, request a slot on PreToolUse.
- MCP handles on-demand questions and coordination. Codex also has `PreToolUse` [VERIFIED].

**Similar products:**

| Product | What it does | Difference from 8GB Vibe | Source |
|---|---|---|---|
| kill-process-mcp | Lists and kills processes | Kills directly, no protection list, no approval | [VERIFIED] README |
| mac-monitor-mcp, System Monitor MCP | Reads CPU, RAM; some can kill | Does not measure macOS memory pressure or swap | [SECONDARY] |
| MCP Agent Mail | Agent registration, mailboxes, file reservations (TTL leases, voluntary), local HTTP with token | Reserves files, not machine resources. Agents often forget to read the mailbox | [VERIFIED] README |
| Claude Code agent teams | Task list, mailbox, file locks | Only within one Claude session, not across vendors | [VERIFIED] |
| Claude Squad, Conductor, Vibe Kanban | Parallel runs per worktree | No RAM or CPU slots | [SECONDARY] |

No product found that combines macOS RAM and swap monitoring, heavy-job slots across agents from different vendors, and out-of-band cleanup approval [SECONDARY; not finding one does not mean none exists].

## 6. Phases, risks, effort

Estimated in work sessions of 1 to 3 hours each [ASSUMPTION].

| Phase | Content | Done when | Effort |
|---|---|---|---|
| 0. Prototype | Minimal `8gbvibe-mcp` executable (stdio, hand-written JSON-RPC) and a swift-sdk version; measure RAM, startup time, size; a manual install into one Claude Code session for testing | SDK or hand-written chosen; measurements recorded in this document | 1 |
| 1. Read + `8gb status` | `machine_status`, `heavy_processes`, `agent_sessions`, `hardware_profile`, `can_start`; the app writes `status.json` every 5 seconds while a shim is in use (or the shim reads directly) | A real agent reads it and follows the advice in a demo | 2 |
| 2. Coordination | `register_agent`, `heartbeat`, slots, message board; the app shows "who holds what" | Two Claude sessions do not build Xcode at the same time when both voluntarily use the tools | 2 |
| 3. Cleanup requests | `request_cleanup`, `cleanup_status`, approval in the app's notification bell | No path for an agent to quit a process without a human approver; complete logging | 2 |
| 4. Optional: enforcement | `PreToolUse` hooks for Claude Code and Codex calling `can_start`/`acquire_slot`; install and uninstall with confirmation | Only if roadmap step 1 data shows overlapping heavy jobs cause the strain | 1 to 2 |

Risks:

- **Agents do not call the tools.** Instructions in CLAUDE.md are not followed reliably [SECONDARY]. Mitigation: clear tool descriptions, sample text for CLAUDE.md and AGENTS.md, hooks in phase 4.
- **The spec changes fast.** 2026-07-28 just dropped session state. Keep the protocol minimal and support both styles.
- **swift-sdk is still 0.x.** If used, pin the version.
- **File contention when many agents write.** Use `flock`, atomic writes, clean up expired slots on read.
- **Self-declared agent identity.** Never relied on for safety decisions; every action still goes through a human approver.
- **One process per session:** about 2 MB per session is acceptable. If the SDK adds a lot, fall back to hand-written JSON-RPC.

## 7. Open questions and decisions

Questions put to BEECA:

1. Agree on "MCP is read-only plus coordination; cleanup only creates a request, approved in the app"?
2. Choose architecture (c) for phase 1 (no socket, no port; coordination through locked files)?
3. Allow, later, a pre-approved rule: "an agent may quit orphan processes created by its own session"? Default is no.
4. Client installation: only show commands for the user to run, or an "Install into Claude Code" button in the app (with confirmation, the exact snippet shown, and an uninstall button)?
5. Order relative to the roadmap: build phases 0 and 1 now as an extension of step 2 (`8gb status`), or wait for more measurement data?

### 7.1. BEECA's decisions (08/11/2026)

1. **Read-only plus coordination by default; cleanup only creates a request pending approval in the app.** Settings have explicit permission levels chosen by the user: "Read only", "Read + coordinate" (default), "Allow low-risk actions" (off by default, later phase). Every action still goes through `ProcessGuard`.
2. **Agent quitting orphans created by its own session:** always asks by default. Settings have an allow switch, with logging, effective only when the machine is short on RAM (memory pressure at warning level or above, or per the machine profile). Otherwise it still asks. Later phase; phase 1 already reserves a slot for it in the policy file.
3. **Client installation:** the app has an "Install into Claude Code" button (shows the snippet, confirms, has an uninstall button). Other clients only show the command or config snippet to copy.
4. **Build phases 0 and 1 now** (read + coordination), treated as step 2 `8gb status`. Architecture (c).

### 7.2. Phase 0 and 1 results (08/11/2026)

- **Hand-written JSON-RPC, no swift-sdk.** Reasons: only stdio and tools are needed; avoids swift-nio and a 0.x API; speaks both `initialize` (2025) and `server/discover` (2026-07-28). The swift-sdk build was not measured; not needed since the hand-written one is light enough.
- Program: `8gbvibe-mcp` (target `VibeMCP`), located in `8GB Vibe.app/Contents/Helpers/`, signed with the app. Logic lives in `VibeCore/VibeMCPServer.swift` and `VibeCore/AgentHub.swift`, with tests.
- Release build measured on the test Mac [VERIFIED]:

| Situation | Startup + `initialize` | `machine_status` | Footprint |
|---|---|---|---|
| App running (reads `agents/status.json`) | 12 ms (warm) | 3 ms | 2.6 MB idle; 5.6 to 5.9 MB after a process scan |
| App closed (measures itself, two samples 1 second apart) | 476 ms (first run) | about 1 second | same as above |

  Binary size 1.8 MB. For 10 agent sessions: about 26 to 60 MB in total.
- The app writes `agents/status.json` (about 1 KB every 5 seconds) only while a registered agent has been active within 10 minutes.
- Files: `~/Library/Application Support/8GB Vibe/agents/` (0700): `state.json`, `policy.json`, `status.json`, `log.jsonl` (0600, at most 1 MB).
- The "Read only" level hides the coordination tools. The "Allow low-risk actions" level and the auto-quit-orphans switch are reserved in `policy.json`, but nothing is done automatically yet.
- Manual run over stdin (not installed into any Claude configuration on the test Mac): `initialize`, `tools/list`, `machine_status`, `can_start` (returned "wait" because the machine was strained), `register_agent`, `acquire_slot` (granted), `heavy_processes` all correct.

### 7.3. Upgrade round 1 (08/11/2026)

Implements the approved upgrade scope, items 1.1 to 1.7. Coordination is still voluntary; no tool quits a process.

- **`acquire_slot` separates the slot from the advice.** Returns `slot` (`granted`, `already_held`, `queued` with `position`, `holder`, `seconds_left`), `advice` (`decision`, `reason`, `data_age_s`, `retry_after_s`, `confidence`, `window_s`) and `start_now` (`true` only when the slot is held and the advice is `go`). Holding a slot does not mean the machine has enough RAM.
- **`can_start` accounts for the queue.** A slot holder does not see itself as a competitor. If someone is waiting ahead, it returns `wait` with the queue position.
- **`renew_slot`** (holder only, at most 30 minutes per renewal, at most 2 hours in total; beyond that it returns the reason and the latest allowed time), **`my_slots`** (recovers slots and queue positions when an agent loses context). Releasing a slot twice returns `already_released`.
- **Liveness follows the MCP process.** The `8gbvibe-mcp` process updates `lastSeen` every 60 seconds. An agent is gone when that exact process (pid and start time) no longer exists; a reused pid does not count as alive. The 10-minute timeout is only a safety net.
- **`lease` and `task` are separate.** `lease`: `active` (within term), `expired` (term over, job still running), `overdue` (over the 2-hour total, job still running). `task`: `running` (a heavy job is seen among the descendants of the slot holder's session, i.e. the MCP process's parent), `ended` (session known, no heavy job seen right now; may not have started yet), `unknown` (session not known). An expired slot whose job is still running is not given to anyone else; it records `busy_with` and quits nothing; when the heavy job finishes the slot frees itself. `overdue` is never treated as free automatically: the app shows it in the notification bell with a "Release slot" button (asks first, logs, touches no process).
- **Fair queue.** If the head of the queue does not ask again within 2 times `retry_after_s`, it yields its turn (keeping a place further back). A dead agent leaves the queue.
- **A corrupt `state.json`** is renamed to `state.json.bad-<time>`, logged, and reported in the app's bell. Never silently overwritten.
- **No guessed numbers.** If swap has not been measured, `swap_mb_per_min: "unknown"` and the advice is `go` with `confidence: low`; if pressure is also missing, `unknown`. Direct reads while the app is closed report `source: direct`, `window_s: 1`.
- **One heavy-job slot for every machine tier** (the 2 slots for 24 GB were dropped). This is a conservative coordination policy, not a machine limit; `hardware_profile` returns this sentence with its data. No option yet to raise the number of slots. The Intel 0.6 factor was dropped.

Verified with 125 unit tests and a live harness running several `8gbvibe-mcp` processes in a temporary directory (`VIBE_AGENTS_DIR`), with a fake heavy job made from a copy of `/bin/sleep` named `xcodebuild`. MCP not yet installed into Claude Code on the test Mac (pending approval).

Release build after round 1, measured on the test Mac, 08/11/2026 [VERIFIED] (`footprint`, CPU over 120 seconds, app running with a temporary data directory):

| Target | Result | Requirement |
|---|---|---|
| App in background | 18 MB, CPU 0.41 % | under 30 MB, under 1 % |
| `8gbvibe-mcp` idle | 2.6 MB, CPU 0 % (60-second heartbeat) | under 8 MB |
| `8gbvibe-mcp` after `machine_status` (direct read) and a process scan | 3.4 MB | |

## 8. Installing into agent clients on the Mac (08/11/2026)

Not only Claude Code: any client present on the Mac can be installed into. Code: `VibeCore/MCPClients.swift`, UI `EightGBVibe/MCPClientsView.swift`.

### 8.1. Paths and commands per official documentation (read 08/11/2026)

| Client | Detection (existence check only) | Install method | State file read | Source |
|---|---|---|---|---|
| Claude Code | `claude` command (login shell PATH, `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`) | `claude mcp add --transport stdio --scope user 8gbvibe -- <server>`; uninstall `claude mcp remove --scope user 8gbvibe`. Default scope is local, so `--scope user` is required | `~/.claude.json`, top-level `mcpServers` (the docs say user-scope servers live "at the top level" without naming the key; the key name is inferred) | https://code.claude.com/docs/en/mcp |
| Codex | `codex` command, including the copy in `ChatGPT.app/Contents/Resources/codex-cli/bin/codex` | `codex mcp add 8gbvibe -- <server>`; uninstall `codex mcp remove 8gbvibe` (checked with `codex mcp --help` on the test Mac). If there is no command but `~/.codex/config.toml` exists, edit the file | `~/.codex/config.toml`, table `[mcp_servers.8gbvibe]` | https://developers.openai.com/codex/mcp (redirects to learn.chatgpt.com/docs/extend/mcp) |
| Gemini CLI | `gemini` command | `gemini mcp add -s user 8gbvibe <server>`; uninstall `gemini mcp remove -s user 8gbvibe`. Default scope is project, so `-s user` is required | `~/.gemini/settings.json`, `mcpServers` | https://geminicli.com/docs/tools/mcp-server/ (the page says Gemini CLI was replaced by Antigravity CLI from 18/06/2026) |
| Cursor | `Cursor.app` or `~/.cursor` folder | edit file | `~/.cursor/mcp.json`, `mcpServers` | https://cursor.com/docs/context/mcp |
| Claude Desktop | `Claude.app` | edit file; the app must be fully quit and reopened | `~/Library/Application Support/Claude/claude_desktop_config.json`, `mcpServers` | https://modelcontextprotocol.io/docs/develop/connect-local-servers |
| Antigravity (app and CLI) | `Antigravity.app` or config file | edit file | `~/.gemini/config/mcp_config.json`, `mcpServers`, `command` and `args` for stdio. Official docs no longer mention `~/.gemini/antigravity/mcp_config.json` (an old path in some guides) | https://antigravity.google/docs/mcp |

Not found in official docs: whether Cursor reloads config automatically; whether Codex CLI needs a restart. The app always says "Reopen <client> to pick up the change".

### 8.2. Safety when writing another app's configuration

- Prefer the client's official command. Edit files only when the client has no command (Cursor, Claude Desktop, Antigravity) or the `codex` command cannot be found.
- The confirmation dialog shows the exact command to run, or the file path and the exact snippet to add.
- File edits:
  - Back up first to `<name>.bak-8gbvibe-<yyyyMMdd-HHmmss>`, with the same permissions.
  - Only add or remove the `8gbvibe` key. Edits are made on the text directly; everything else stays byte-for-byte (whitespace, order, other servers). After editing, the app re-reads and compares: apart from the `8gbvibe` key the content must be identical, otherwise nothing is written.
  - Atomic write (temp file in the same folder, then rename), keeps the old file permissions, follows symbolic links.
  - Corrupt file, comments or non-plain JSON, or `mcpServers` not an object: no write, report an error. An empty file (like the Antigravity file on the test Mac) is treated as `{}`.
  - Uninstall removes only its own key and returns the file to exactly the bytes it had before install. On install, the app records what the file looked like in `~/Library/Application Support/8GB Vibe/mcp-installs.json` (0600): no file, empty file, no `mcpServers`, or existing `mcpServers`. On uninstall, if `mcpServers` is left empty and was created by 8GB Vibe it is removed too; an empty file is restored to the same empty content; a file created by 8GB Vibe is deleted (the backup remains). A pre-existing `mcpServers`, or one where the user later added other servers, is left as is. Installs made by an older version (no record) only remove the key.
- Every install or uninstall is logged in the app's log ("Install MCP" / "Uninstall MCP", client, command or file, result).
- "Installed" means the config was written. "Connected" means an agent has called `register_agent` with that client's name (self-declared, not authenticated). The two are shown separately.

### 8.3. Testing

- `MCPClientsTests` (fake HOME and /Applications in a temporary folder): detects only present clients; commands use the correct scope flags; JSON with other servers already present (install then uninstall restores the original text exactly, keeps 0644 permissions, 2 backups); missing `mcpServers`, `{}`, empty file; a corrupt file is not written and gets no backup; TOML with sub-tables and other tables; "connected" separate from "installed".
- Install then uninstall run against temporary copies of the real config files on the test Mac: Codex, Claude Desktop and Antigravity (empty file) were all restored byte-for-byte. No real config file was written and no real install was clicked (pending approval).

## Main sources

- MCP specification: https://modelcontextprotocol.io/specification/latest ; 2026-07-28 changelog ; transports ; authorization ; server/tools ; client/elicitation ; security best practices (Local MCP Server Compromise section).
- Swift SDK: https://github.com/modelcontextprotocol/swift-sdk (Package.swift, README, releases).
- Claude Code MCP: https://code.claude.com/docs/en/mcp ; hooks: https://code.claude.com/docs/en/hooks ; memory: https://code.claude.com/docs/en/memory ; agent teams: https://code.claude.com/docs/en/agent-teams
- Issue on per-session MCP duplication: https://github.com/anthropics/claude-code/issues/28860
- Codex MCP and hooks: https://learn.chatgpt.com/docs/extend/mcp?surface=cli ; https://learn.chatgpt.com/docs/hooks
- Antigravity MCP: https://antigravity.google/docs/mcp ; Gemini CLI: https://geminicli.com/docs/tools/mcp-server/ ; Cursor: https://cursor.com/docs/context/mcp
- Similar products: https://github.com/misiektoja/kill-process-mcp ; https://github.com/Dicklesworthstone/mcp_agent_mail
- Safety: https://invariantlabs.ai/blog/mcp-security-notification
