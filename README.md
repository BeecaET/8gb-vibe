# 8GB Vibe

*Vibe coding on a budget Mac.*

English | [Tiếng Việt](README.vi.md)

**100 % free.** Download at [8gb.beeca.vn](https://8gb.beeca.vn). A BEECA product.

A helper for people who vibe code on an 8 GB Mac. It is a macOS menu bar app that keeps low-spec Macs (MacBook Air M2, 8 GB RAM) responsive under heavy work: several Claude Code sessions, Xcode, Gradle, Docker.

- Features and roadmap (Vietnamese): [docs/CHUC_NANG.md](docs/CHUC_NANG.md)
- Status: **MVP 1 (view only)** is done, plus the **quit apps** part of MVP 2, the AI Agents page and the Dev Servers page. Cache cleaning, work modes and the build queue are not there yet.
- The app never quits or deletes anything on its own. Every quit is chosen and confirmed by the user.

## Features

| Area | What it does |
|---|---|
| Menu bar | A ring filled by % RAM, colored by pressure (green, orange, red), plus swap used. |
| Popover | RAM, swap and disk gauges; 1 hour swap chart; top 3 groups; total RAM that can be freed. |
| Overview | RAM, swap, free disk, load; swap chart; suggestions; threshold status. |
| Memory | RAM budget; table of work categories (Claude, Xcode, Android, Docker...) that expand. |
| AI Agents | Vibe group. CLI agents (Claude Code, Codex CLI, Gemini CLI...) per session, AI apps, AI IDEs. A rough estimate of how many more sessions fit in the RAM budget (not a guarantee against swapping); says when the Mac is already short of RAM. |
| Dev Servers | Servers with open ports (Next.js, Vite, Python...): project, ports, ports open to the network, who started them, RAM, idle time. Flags orphaned processes (the agent or Terminal has closed but the server still runs). Right-click to open in a browser or stop, through a confirmation dialog. |
| Processes | Table of every process, sortable, searchable, grouped. Right-click your own processes to quit them (with confirmation). |
| Disk | Measures known caches and large data, split into safe, review, and other apps' data. |
| Background | Services that start at login or boot (LaunchAgents, LaunchDaemons). |
| Settings | Alert thresholds, menu bar style, notifications, launch at login, language. |
| Free RAM | Apps, Simulator, Gradle daemon and emulators using RAM. Suggests items idle for over 30 minutes. Pick and quit through a confirmation dialog. If an app has not quit after 10 seconds, offers force quit (second confirmation). |
| Log | Records every quit: time, target, RAM, result. File: `~/Library/Application Support/8GB Vibe/nhat-ky.jsonl`. |
| Notifications | "Mac is slow" with what to quit; clicking opens Free RAM. Also warns when the disk is nearly full or too many Claude Code sessions are open. At most once every 30 minutes per kind. |

Never quit from the app: the app itself, Finder, Dock, macOS system processes, the Claude app (quitting it ends every Claude Code session). Claude Code sessions are only suggested for archiving in the Claude app.

Also included: a health score (0 to 100), real app icons, an About page with copyright.

## Build and run

No Xcode needed. Local test build (ad hoc signature):

```bash
./scripts/package.sh
```

```bash
open "build/8GB Vibe.app"
```

## Release

Release builds are universal (Apple silicon and Intel), Developer ID signed, hardened runtime, notarized, packaged as a DMG.

Release builds need BEECA's Developer ID certificate and a notarization profile, so only maintainers run them. Create the profile once (stores the Apple ID app-specific password in the Keychain):

```bash
xcrun notarytool store-credentials <profile> --apple-id <email> --team-id 59SQ2V25T2
```

Build a release:

```bash
NOTARY_PROFILE=<profile> ./scripts/release.sh
```

Output: `build/release/8GB-Vibe-<version>.dmg` and a `.sha256` file. The version comes from the `VERSION` file, the build number is the commit count.

Run the core tests:

```bash
swift test -j 2
```

Launch flags for testing:

- `--window [page]`: open the main window right away. Pages: `overview`, `memory`, `agents`, `devServers`, `processes`, `disk`, `backgroundItems`, `freeRAM`, `log`, `settings`, `about`.
- `--capture-popover <file.png>`: render the popover to an image, then quit.
- `--test-stop-dev-server <port>` (debug builds only): stop the dev server on that port through the same path as the confirmation dialog, to test stopping and the log. Only stops a server whose working directory is in the temporary folder.

## Measurements

To decide what to build next, the app measures how the Mac copes, minute by minute. Nothing leaves the Mac.

- Each minute: highest memory pressure, swap in and out (MB, from the difference between two 5-second samples), compressions and decompressions per second, pageouts, swap used, RAM used, wired, heavy jobs running at once (Xcode, SwiftPM, Gradle, next/vite/webpack/tsc builds, jest/vitest/Playwright tests, cargo, go, pytest, docker build) and, at the start of a strained episode, the group or session whose RAM grew most just before ("may be related": correlation only).
- "Strained" is provisional: memory pressure warning or worse, or at least 20 MB of swap in plus out in the minute. Thresholds will be tuned with data.
- Files: `~/Library/Application Support/8GB Vibe/measurements/<date>.csv`, private to the user (0600), at most 14 days and 5 MB. Only one running copy of the app writes.
- Heavy jobs are seen when processes are sampled: every 5 seconds with a window open, every 60 seconds in the background, so very short jobs can be missed.
- The health score deducts for swap activity, not for the size of the swap file.

```bash
"/Applications/8GB Vibe.app/Contents/MacOS/8GBVibe" --measurement-summary
```

```bash
"/Applications/8GB Vibe.app/Contents/MacOS/8GBVibe" --export-measurements ~/Desktop/8gb-measurements.csv
```

## AI agents (MCP)

`8GB Vibe.app/Contents/Helpers/8gbvibe-mcp` is an MCP server over stdio for AI agents (Claude Code, Codex, Gemini, Antigravity, Cursor). It reads the Mac's state and lets agents coordinate: `machine_status`, `heavy_processes`, `agent_sessions`, `hardware_profile`, `can_start` (advice before a heavy job), `register_agent`, `heartbeat`, `acquire_slot`/`release_slot` (one heavy-job slot, time-limited), `slots`, `post_message`/`read_messages`. No tool quits a process, deletes a file or changes a setting. Settings > AI agents sets the permission level and installs it into Claude Code after confirmation. Details (Vietnamese): [docs/NGHIEN_CUU_MCP.md](docs/NGHIEN_CUU_MCP.md).

```bash
claude mcp add --transport stdio --scope user 8gbvibe -- "/Applications/8GB Vibe.app/Contents/Helpers/8gbvibe-mcp"
```

## Languages

The app ships in Vietnamese (development language) and English. It follows the macOS language by default; Settings has a Language picker (Automatic, Tiếng Việt, English) that applies after a relaunch.

- Code, file names and comments are in English. Translation keys are the Vietnamese sentences. English lives in `Resources/en.lproj/Localizable.strings` and is copied into the .app when packaging.
- SwiftUI `Text("...")` and `Button("...")` are localized automatically. For `String` values write `String(localized: "...", bundle: .main)`.
- Sentences with values use `%@` (strings, formatted numbers) and `%lld` (integers) in the key, for example `"Đã chọn %lld mục" = "%lld selected";`.
- Try English: `open -n "build/8GB Vibe.app" --args -AppleLanguages "(en)"`.

## Layout

| Folder | Contents |
|---|---|
| `Sources/VibeCore` | Core, no UI: system metrics, process reading (libproc), grouping, idle sessions, RAM budget, suggestions, thresholds, dev servers and ports, AI agents, disk scan, LaunchAgents. |
| `Sources/EightGBVibe` | SwiftUI app: menu bar, popover, main window. |
| `Tests/VibeCoreTests` | Core tests. |
| `scripts/package.sh` | Local test build: build, package the `.app`, ad hoc signature. |
| `scripts/release.sh` | Release build: universal, Developer ID, notarization, DMG. |
| `scripts/make-icon.swift` | Draws the app icon and builds `Resources/AppIcon.icns`. |
| `scripts/common.sh` | Shared settings: app name, bundle id, `.app` packaging. |

## Known limitations

- Idle time is counted only from when the app started monitoring. Right after launch the app shows "Monitoring".
- The owner of a virtual machine (Claude or Docker) is guessed from start times.
- "Apps need" is an estimate: each process's real footprint (compressed memory counted at its uncompressed size) plus wired memory.
- When the menu bar is full, macOS may hide new icons. Check System Settings, Menu Bar.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Report security problems privately, see [SECURITY.md](SECURITY.md).

## License

The source code is licensed under the [Apache License 2.0](LICENSE). Copyright 2026 BEECA. See also [NOTICE](NOTICE).

## Trademarks

The name "8GB Vibe", the app icon and the BEECA name and logo are trademarks of BEECA. They are not covered by the Apache License 2.0 (section 6). A fork you distribute must use a different name and icon and must not use the BEECA logo. Details: [TRADEMARKS.md](TRADEMARKS.md).
