# 8GB Vibe

*Vibe coding on a budget Mac.*

English | [Tiếng Việt](README.vi.md)

8GB Vibe is a free macOS menu bar app that keeps low-spec Macs (such as a MacBook Air M2 with 8 GB of RAM) responsive while you vibe code: several Claude Code or Codex sessions, Xcode, Gradle, Docker and dev servers at once. It shows what is using memory, warns before the Mac starts to stall, and helps you free RAM. It never quits or deletes anything without asking you first.

**Download:** [8gb.beeca.vn](https://8gb.beeca.vn) or [GitHub Releases](https://github.com/BeecaET/8gb-vibe/releases). Free, made by BEECA.

- Requirements: macOS 13 Ventura or later, Apple silicon or Intel (universal build).
- Release builds are signed with BEECA's Developer ID and notarized by Apple. Each release lists the DMG's SHA-256.
- Interface in English and Vietnamese.
- Features and roadmap: [docs/FEATURES.md](docs/FEATURES.md). MCP server design: [docs/MCP.md](docs/MCP.md).

## Features

| Area | What it does |
|---|---|
| Menu bar | A ring filled by % RAM, colored by memory pressure (green, orange, red), plus swap used. |
| Popover | RAM, swap and disk gauges; a one-hour swap chart; the top 3 groups; how much RAM can be freed. |
| Overview | A one-line piece of advice, RAM, swap, free disk and load, a swap chart, suggestions and threshold status. |
| Memory | RAM budget and a table of work categories (Claude, Xcode, Android, Docker...) that you can expand. |
| AI Agents | CLI agents (Claude Code, Codex CLI, Gemini CLI...) per session, AI apps and AI IDEs. A rough estimate of how many more sessions fit in the RAM budget (an estimate, not a guarantee against swapping). |
| Dev Servers | Servers with open ports (Next.js, Vite, Python...): project, ports, ports open to the network, who started them, RAM and idle time. Flags orphaned servers whose agent or Terminal has closed. Open in a browser or stop, with confirmation. |
| Processes | Every process, sortable, searchable and grouped. Quit your own processes with confirmation. |
| Disk | Measures known caches and large data, split into safe, review and other apps' data. |
| Background | Services that start at login or boot (LaunchAgents, LaunchDaemons). |
| Mac | Hardware profile of this Mac, used to tune advice and thresholds. |
| Free RAM | Apps, Simulator, Gradle daemons and emulators using RAM. Suggests items idle for more than 30 minutes. Quit with confirmation; force quit needs a second confirmation. |
| Notifications | "Mac is slow" with what to quit, disk nearly full, too many agent sessions. At most once every 30 minutes per kind, and kept on a Notifications page. |
| Log | Every quit you confirmed: time, target, RAM freed (estimated and measured), result. |
| Settings | Tabs for alert thresholds, menu bar style, notifications, launch at login, language, Light/Dark appearance, accent color and AI agents. |

Press ⌘K in the main window for the command palette.

### Safety rules

- Every quit, stop or clean-up is chosen and confirmed by you. Nothing is quit or deleted automatically.
- Never quit from the app: 8GB Vibe itself, Finder, Dock, macOS system processes and the Claude app (quitting it would end every Claude Code session).
- No data leaves your Mac. The app opens no HTTP server and does not read the Keychain or browser cookies.

## AI agents (MCP)

The app ships an MCP server over stdio at `8GB Vibe.app/Contents/Helpers/8gbvibe-mcp`. AI agents (Claude Code, Codex, Claude Desktop, Gemini CLI, Antigravity, Cursor) can read the Mac's state and coordinate heavy work:

- Read: `machine_status`, `heavy_processes`, `agent_sessions`, `hardware_profile`, `can_start` (advice before a heavy job).
- Coordinate: `register_agent`, `heartbeat`, `acquire_slot` / `release_slot` (one time-limited slot for heavy jobs, so two agents do not build at once), `slots`, `post_message` / `read_messages`.

Coordination is voluntary. No tool quits a process, deletes a file or changes a setting. In Settings > AI agents you choose the permission level and install the server into the agents found on your Mac; the app asks first, backs up the agent's config file and can remove it again. To add it to Claude Code by hand:

```bash
claude mcp add --transport stdio --scope user 8gbvibe -- "/Applications/8GB Vibe.app/Contents/Helpers/8gbvibe-mcp"
```

Design, measurements and safety model: [docs/MCP.md](docs/MCP.md).

## Measurements

To decide what to build next, the app records how the Mac copes, minute by minute. Nothing leaves the Mac.

- Each minute: highest memory pressure; swap in and out (MB, from the difference between two 5-second samples); compressions and decompressions per second; pageouts; swap used; RAM used; wired memory; heavy jobs running at once (Xcode, SwiftPM, Gradle, next/vite/webpack/tsc builds, jest/vitest/Playwright tests, cargo, go, pytest, docker build); and, when a strained episode starts, the group or session whose RAM grew most just before (shown as "may be related": correlation only).
- "Strained" is provisional: memory pressure at warning or worse, or at least 20 MB of swap in plus out within the minute. Thresholds will be tuned with data.
- Files: `~/Library/Application Support/8GB Vibe/measurements/<date>.csv`, readable only by you (0600), kept for at most 14 days and 5 MB. Only one running copy of the app writes.
- Heavy jobs are seen when processes are sampled: every 5 seconds with a window open, every 60 seconds in the background, so very short jobs can be missed.
- The health score (0 to 100) deducts for swap activity, not for the size of the swap file.

```bash
"/Applications/8GB Vibe.app/Contents/MacOS/8GBVibe" --measurement-summary
```

```bash
"/Applications/8GB Vibe.app/Contents/MacOS/8GBVibe" --export-measurements ~/Desktop/8gb-measurements.csv
```

## Build from source

You need macOS 13 or later and the Swift toolchain (Xcode or the Command Line Tools). There are no third-party dependencies. `-j 2` keeps the build light on an 8 GB Mac.

Run the core tests:

```bash
swift test -j 2
```

Build a local test app (ad hoc signature, this Mac's chip only):

```bash
./scripts/package.sh
```

```bash
open "build/8GB Vibe.app"
```

Launch flags for testing:

- `--window [page]`: open the main window at a page: `overview`, `memory`, `agents`, `devServers`, `processes`, `disk`, `backgroundItems`, `machine`, `freeRAM`, `log`, `inbox`, `settings`, `about`.
- `--capture-popover <file.png>`: render the popover to an image, then quit.
- `--test-stop-dev-server <port>` (debug builds only): stop the dev server on that port through the same path as the confirmation dialog. Only stops a server whose working folder is in the temporary folder.

## Release (maintainers)

Release builds are universal (Apple silicon and Intel), Developer ID signed with the hardened runtime, notarized and packaged as a DMG. They need BEECA's Developer ID certificate and a notarytool profile. Create the profile once (it stores the Apple ID app-specific password in the Keychain):

```bash
xcrun notarytool store-credentials <profile> --apple-id <email> --team-id 59SQ2V25T2
```

Build a release:

```bash
NOTARY_PROFILE=<profile> ./scripts/release.sh
```

Output: `build/release/8GB-Vibe-<version>.dmg` and its `.sha256` file. The version comes from the `VERSION` file; the build number is the commit count.

## Languages

The app is in Vietnamese and English. It follows the macOS language by default; Settings has a Language picker (Automatic, Tiếng Việt, English) that applies after a relaunch.

- Code, file names and comments are in English. User-facing strings are localized with `Localizable.strings` in `Resources/<language>.lproj`, copied into the app when packaging.
- SwiftUI `Text("...")` and `Button("...")` are localized automatically. For `String` values use `String(localized: "...", bundle: .main)`.
- Values in sentences use `%@` (strings, formatted numbers) and `%lld` (integers).
- Try English: `open -n "build/8GB Vibe.app" --args -AppleLanguages "(en)"`.

## Project layout

| Folder | Contents |
|---|---|
| `Sources/VibeCore` | Core, no UI: system metrics, process reading (libproc), grouping, idle sessions, RAM budget, suggestions, thresholds, dev servers and ports, AI agents, disk scan, LaunchAgents, MCP server logic. |
| `Sources/EightGBVibe` | SwiftUI app: menu bar, popover, main window. |
| `Tests/VibeCoreTests` | Core tests. |
| `scripts/package.sh` | Local test build: build, package the `.app`, ad hoc signature. |
| `scripts/release.sh` | Release build: universal, Developer ID, notarization, DMG. |
| `scripts/common.sh` | Shared settings: app name, bundle id, `.app` packaging. |
| `scripts/make-icon.swift` | Draws the app icon and builds `Resources/AppIcon.icns`. |
| `scripts/mcp-harness` | Multi-process test harness for the MCP server. |
| `web` | The website 8gb.beeca.vn (static). |
| `packaging/homebrew` | Homebrew cask template. |

## Known limitations

- Idle time is counted only from when the app started monitoring. Right after launch the app shows "Monitoring".
- The owner of a virtual machine (Claude or Docker) is guessed from start times.
- "Apps need" is an estimate: each process's real footprint (compressed memory counted at its uncompressed size) plus wired memory.
- When the menu bar is full, macOS may hide new icons. Check System Settings > Menu Bar.

## Contributing

Bug reports, ideas and pull requests are welcome, in English or Vietnamese. See [CONTRIBUTING.md](CONTRIBUTING.md). Report security problems privately, see [SECURITY.md](SECURITY.md).

## License

The source code is licensed under the [Apache License 2.0](LICENSE). Copyright 2026 BEECA. See also [NOTICE](NOTICE).

## Trademarks

The name "8GB Vibe", the app icon and the BEECA name and logo are trademarks of BEECA and are not covered by the Apache License 2.0 (section 6). A fork you distribute must use a different name and icon and must not use the BEECA logo. Details: [TRADEMARKS.md](TRADEMARKS.md).
