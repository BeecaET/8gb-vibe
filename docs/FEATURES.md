# 8GB Vibe: features and roadmap

- Last updated: 2026-11-08 (following the roadmap agreed by BEECA the same day)
- Positioning: **8GB Vibe, vibe coding on a budget Mac.** A RAM control station for people who vibe code and run AI agents on low-spec Macs.
- Status labels: **Done** (in a released version), **Done (1.1.0)** (new in version 1.1.0, released 2026-11-08), **Planned** (not built yet, with the target version).

---

## 1. Overview by area

| Area | Purpose | Status |
|---|---|---|
| A. Mac monitoring | Know whether the Mac is healthy or strained, and what is using resources | Done |
| B. AI agent monitoring | Know what agents are running, what they cost, whether there is room for more | Done (1.1.0) |
| C. Free RAM | Quit apps, services, orphaned processes, always asking first | Done |
| D. Alerts | Warn early when the Mac is about to stall, or when an agent has finished | Partly done |
| E. Disk | Know what fills the disk, clean caches safely | Viewing done, cleaning in 1.2 |
| F. Dev servers and builds | Manage servers, ports, heavy builds | Done (dev servers, 1.1.0), build queue in 1.3 |
| G. Remote control | Control a Mac at home from another Mac | Planned, after 2.0 |
| H. For agents | Agents know the Mac's limits before starting heavy work | Planned 1.3, 2.0 |
| I. Product | About, license, languages, releases | Done |

---

## 2. Details

### A. Mac monitoring

| Feature | Description | Status |
|---|---|---|
| Menu bar icon | A ring filled by % RAM, colored by pressure, plus swap used | Done |
| Popover | Health score, RAM, swap, free disk, 1 hour swap chart, apps using the most RAM | Done |
| Floating bubble | Small panel above other windows: health score ring, RAM %, swap, swap rate while swapping hard, optional agent sessions. Off by default; Settings > Look: when the window is minimized, or always. Click opens the main window, right click hides it. Reuses the Monitor samples | Done (unreleased) |
| Health score | From 0 to 100, with a sentence explaining why the Mac is slow | Done |
| Overview | RAM, swap, CPU load and free disk cards with charts; "What is using RAM" with real app icons | Done |
| RAM budget | Compares what apps need with the Mac's RAM; the excess must be compressed or swapped | Done |
| Grouping by kind of work | Claude, Xcode and Simulator, Android, Docker, browsers, chat, sync, other IDEs and AI, system | Done |
| Processes | Table of every process, sortable, searchable | Done |
| Background | Services that start at login or boot (view only) | Done |
| 24 hour and 7 day history | One sample per minute (RAM, swap, pressure, top 5 groups), chart in Overview, capped file size | Planned 1.2 |
| Weekly report | Highest swap, most expensive tools, whether a RAM upgrade is worth it | Planned 2.0 |

### B. AI agent monitoring

| Feature | Description | Status |
|---|---|---|
| AI Agents page | In the Vibe group of the sidebar, replacing the old Claude Code page. Covers CLI agents (Claude Code, Codex CLI...), AI apps (Claude including its virtual machine, ChatGPT...), AI IDEs (Cursor, Antigravity...) | Done (1.1.0) |
| Room for new sessions | "Estimated room for about N more agent sessions"; when RAM is nearly full: "better not open more sessions yet"; when apps already need more than the Mac's RAM: a RAM shortage warning with the GB over. Always labeled as an estimate, never a guarantee against swapping | Done (1.1.0, wording revised in 1.1.1) |
| MCP servers per session | Number of MCP servers and the RAM of each session; flags an MCP server running several copies ("Playwright MCP running 5 copies, using 2.1 GB") | Done (1.1.0) |
| Memory growth alert | A session whose RAM grows steadily for 30 minutes or exceeds 2 GB gets a suggestion to quit and reopen it (never done automatically); flags unusual growth in wired RAM | Done (1.1.0) |
| More detection | Antigravity CLI (`agy`), the child tree of `sandbox-exec` (Codex), Claude's Cowork virtual machine shown separately | Done (1.1.0) |
| Token limits (minor) | Only shows the 5 hour and 7 day % from Claude Code's official data; does not read the Keychain or cookies | Planned 1.4 |

### C. Free RAM

| Feature | Description | Status |
|---|---|---|
| Free RAM | List of apps, Simulator, Gradle, emulators using RAM; suggests items idle for over 30 minutes | Done |
| Confirmation dialog | Lists each item with the RAM it frees; Esc cancels | Done |
| Clean quit | The app saves and closes itself; if it has not closed after 10 seconds, force quit is offered (second confirmation) | Done |
| Quit from the Processes table | Right-click one of your own processes | Done |
| Protection (bug fix) | The app itself, loginwindow, Finder, Dock, the Claude app and Claude Code sessions can never be quit from anywhere, including the Processes table and the Stop button on Dev Servers | Done (1.1.0) |
| Log | Records every quit: time, target, RAM, result | Done |
| Orphaned processes | Dev servers, MCP servers, Playwright still running after the agent has finished; stopped with confirmation | Done (1.1.0) |
| Orphans with known origin | Remembers the parent tree while the agent is alive; shows "from the Claude Code session in project X, ended 2 hours ago"; groups by originating session so they can be stopped at once | Done (1.1.0) |
| Stop button tested on real processes | A fake server in a temporary folder, stopped through the app, log checked; bug fix (identity checked before stopping) | Done (1.1.0) |
| Vibe modes | "Claude only", "Claude + iOS", "Claude + Web": one click clears the Mac for the work ahead, with confirmation | Planned 1.4 |
| Lower priority of background apps | `taskpolicy -b` for cloud sync and chat while building; click again to restore | Planned 1.4 |

### D. Alerts

| Feature | Description | Status |
|---|---|---|
| Mac is slow | Notification with what to quit; clicking opens Free RAM | Done |
| Disk nearly full, too many sessions | At most once every 30 minutes per kind | Done |
| Adjustable thresholds | Swap, free disk, CPU load, number of sessions, how long counts as idle | Done |
| Agent finished, permission needed | Through each tool's hook, calling the `8gb notify` command (no HTTP server is opened), sending only the event type, session id and project folder. Off by default; enabled per tool in Settings; shows the exact snippet that will be added to the agent's settings file, backs it up, has a remove button, logs it. Claude Code first, then Codex, finally Cursor and Antigravity | Planned 1.2 |
| Early warning | Warn when swap rises fast, before the Mac stalls | Planned 2.0 |

### E. Disk

| Feature | Description | Status |
|---|---|---|
| Measure caches and large data | Split into three levels: safe, review, other apps' data | Done |
| Safe cache cleaning | DerivedData, npm, pip, uv, Homebrew, Gradle, Codex, Playwright, npx, Cursor, broken Simulators. Size preview, confirmation dialog, log. A Settings option: "Move to Trash" (default) or "Delete immediately"; the confirmation dialog states which one is selected | Planned 1.2 |
| Items to review | Agent worktrees unused for a long time, `node_modules` not opened in 30 days, AI models unused for a long time. Listed only, the user picks each item; worktrees with uncommitted changes are never deleted | Planned 1.2 |

### F. Dev servers and builds

| Feature | Description | Status |
|---|---|---|
| Dev servers and ports | Dev Servers page: project, kind (Next.js, Vite, Python...), ports, ports open to the network, who started it, RAM, idle time; open in a browser; stop with confirmation | Done (1.1.0) |
| Build queue | `8gb build -- xcodebuild ...`: one heavy build at a time; waits while pressure is red; the app shows the queue | Planned 1.3 |
| Keep the Mac awake while agents run | `caffeinate -w <pid>` per running session, ends by itself when the agent finishes; toggled in the menu | Planned 1.3 |

### G. Remote control (owner only)

Moved to after version 2.0 (decided 2026-11-08): it needs a tunnel through a server, pairing and encryption, which is a large attack surface and needs its own security review.

| Feature | Description | Status |
|---|---|---|
| Pairing | One-time pairing code between two of your Macs | Planned, after 2.0 |
| Tunnel through 8gb.beeca.vn | End-to-end encrypted, no Tailscale needed, no open ports | Planned, after 2.0 |
| Open the screen, open Terminal | macOS Screen Sharing and SSH through the tunnel | Planned, after 2.0 |
| My Mac, Away mode | Status of the Mac at home, Free RAM remotely, keep the Mac awake while plugged in | Planned, after 2.0 |

### H. For agents

| Feature | Description | Status |
|---|---|---|
| `8gb status` command | One line: pressure, swap, room for N sessions, whether to build now; has `--json`. Reads the state the app writes to a file, does not measure again | Planned 1.3 |
| Snippet for CLAUDE.md, AGENTS.md | A "Copy snippet" button, the user pastes it themselves | Planned 1.3 |
| SessionStart hook (optional) | Inserts the Mac's state at the start of each agent session, installed the same way as the "agent finished" hook | Planned 1.3 |
| 8GB Vibe MCP server | Tools `machine_status`, `heavy_processes`, `can_start_session`, over stdio | Planned 2.0 |

### I. Product

| Feature | Description | Status |
|---|---|---|
| About page | Icon, version, 100 % free, privacy, BEECA logo, copyright | Done |
| Settings | Thresholds, menu bar style, notifications, launch at login | Done |
| Languages | Vietnamese and English following the macOS language, with a Language picker in Settings | Done (1.1.0) |
| Emerald icon | A rotating figure-8 hourglass on an emerald background; emerald accent color | Done (1.1.0) |
| Configuration tips for 8 GB Macs | Checks, then guides: limit Docker's RAM or use OrbStack, Colima; fewer heavy MCP servers; Gradle; Spotlight; login items; a single cloud sync app. The user makes the changes | Planned 1.4 |
| Releases | Universal DMG (Apple silicon and Intel), Developer ID signed, notarized | Done |
| Website 8gb.beeca.vn | Introduction and download | In progress, awaiting deployment |

---

## 2b. Mac configuration and tuning profiles

Requirement (2026-11-08): the app tunes itself to each Mac's configuration; it scans the hardware on first use and saves the result.

**Hardware scan** (`VibeCore/HardwareProfile.swift`):
- Uses `sysctl` and IOKit, no network. Collects: model (`hw.model`), Mac name, chip, Apple silicon or Intel, number of performance and efficiency cores, RAM, capacity and format of the internal disk, macOS version. Checks whether Xcode, Docker, OrbStack, Android Studio are in /Applications (existence only, never opened).
- Saved at `~/Library/Application Support/8GB Vibe/hardware.json`, permissions 0600, with the scan date.
- Scans again when: the app is opened for the first time; the schema version changes; the model, RAM or macOS differs from last time (a cheap check on each launch); or the user clicks "Scan again" on the Mac page.

**Mac page** (View group of the sidebar, ⌘I, also in the View menu; the About page keeps only a one-line summary and a button to open the page). Read only, no network, does not run other apps. Any field that cannot be read shows "Could not read", never a guess. Never reads the serial number or UUID.

| Group | Information | Source | Saved |
|---|---|---|---|
| Mac | Mac name, model identifier, year (taken from the Mac name) | IOKit `product-name`, sysctl `hw.model` | hardware.json |
| Chip | Chip name, performance and efficiency cores, GPU cores, architecture | sysctl, IOKit `AGXAccelerator` `gpu-core-count`, `uname` | hardware.json |
| Memory | RAM; RAM type (not published on Apple silicon, shows "Could not read"); used, compressed, wired, swap | sysctl; live numbers from Monitor | RAM saved; live numbers not |
| Disk | Capacity, free space, format, internal/external, disk model, SMART (only whether the disk supports it; health needs another tool, the app does not read it) | resourceValues, IOKit `IOBlockStorageDevice` | except free space |
| Battery | Condition (shown when macOS reports it), cycle count against design, remaining capacity against design (mAh), charge level, charging, power source | IOPowerSources, IOKit `AppleSmartBattery` (only the needed keys, serial number dropped) | no |
| Displays | For each display: pixels, "looks like", refresh rate | CoreGraphics | no |
| System | macOS and build, uptime, thermal state (`thermalState`), Low Power Mode | ProcessInfo, sysctl `kern.osversion`, `kern.boottime` | macOS version saved |
| Developer tools | Xcode, Simulator, Docker, OrbStack, Android Studio, Command Line Tools, with versions from Info.plist | file existence check | hardware.json |
| Tuning profile | Table of the profile's default thresholds; marked "experimental" for 16 and 24 GB; Scan again button | computed from the profile | no |

Live numbers are read every 5 seconds while the page is open and are not saved. hardware.json moves to schema 2 (old files can still be read; the next launch scans again).

**Tuning profiles** (default values; values the user has changed in Settings are kept):

| Value | 8 GB (up to 12 GB) | 16 GB (up to 20 GB) | 24 GB and above | Source |
|---|---|---|---|---|
| Swap yellow / red | 3 / 6 GB | 4 / 8 GB | 6 / 12 GB | 8 GB: previous default kept; 16, 24: estimate |
| Recommended agent sessions below / red alert | 4 / 8 | 8 / 12 | 12 / 20 | Estimate (a user reported about 2 heavy sessions on 16 GB; an idle Claude Code session uses 110 to 250 MB) |
| RAM reserved for the system when estimating room for new sessions | 0.5 GB | 1 GB | 2 GB | Estimate |
| "Swap is very heavy": swap per minute that alerts at once / alerts when doubled | 3 / 1 GB | 4 / 1.5 GB | 6 / 2 GB | 8 GB: set above the everyday levels measured (0.5 to 3.5 GB/minute); others: estimate |
| Process scan interval in the background | 60 seconds | 45 seconds | 30 seconds | Estimate; Macs with less RAM scan less often |
| 5 minute CPU load yellow / red | 2 and 4 times the number of cores | same as left | same as left | By core count (8 core Mac: 16 / 32, unchanged) |

Intel Macs: same thresholds as Apple silicon Macs with the same RAM tier. The old 0.6 factor was removed in MCP batch 1 (2026-11-08) because no measurement showed that Intel Macs stall earlier.

Alert name: "Swap is very heavy" (previously "Mac is about to freeze"; renamed because measurements showed the Mac still responds at this swap level). The text gives the measured swap in/out rate, the measurement window (average of the last 60 seconds) and memory pressure. It never says the Mac is about to freeze; the app whose memory grew the most is only described as "not necessarily the cause".

**Incidents and sleep (batch 1, 2026-11-08):**

- The app listens for the Mac going to sleep and waking, and compares the wall clock with the clock that stops during sleep (`systemUptime`). A gap that includes sleep is only recorded as "Mac asleep", not as an incident.
- Incident titles follow the evidence:

| Evidence | Title |
|---|---|
| No measurement for 30 seconds while the Mac is strained | Monitoring was interrupted while the Mac was strained |
| The app's main loop delayed by 10 seconds or more | 8GB Vibe responded slowly while the Mac was strained |
| The previous run did not exit normally, last sample strained | The app ended abnormally last time while the Mac was strained (also noted if the Mac has restarted since, read from `kern.boottime`) |
| A gap of 60 seconds or more and peak swap of 10 GB/minute or more | Monitoring was interrupted for a long time while swap was very heavy |

No title says the whole Mac froze just because samples are missing or the app responded slowly.

**RAM numbers when freeing RAM (batch 1):**

- Before closing: "Memory these apps are holding: about X (estimate)". The "after" bar is drawn fading out, as a range, not a definite mark.
- After closing: the app records RAM used and swap right before closing and measures again 10 seconds later. The reward card shows "Estimated from the apps" and "Measured: RAM used down Y, swap down Z (may include other activity)".
- The log gains a "Measured after cleanup" entry with the field `doDuoc` (`ram`, `swap`, bytes, may be negative); `giaiPhong` stays as the estimated number. The "This week" line states clearly that it adds up estimates.

How user values are kept: the app remembers the set of defaults it applied last time. A threshold still equal to the old default (not changed by the user) moves to the new profile's default; a changed threshold is kept.

On the first scan, the app sends the notification "Mac recognized: MacBook Air (M2, 2022), 8 GB. Using the 8 GB profile."

## 3. Roadmap (order agreed by BEECA on 2026-11-08)

This order replaces the previous one. It was set after an internal review. Principle: measure before building; each step has a condition for moving on.

| Step | Output | Condition to move on |
|---|---|---|
| 1. Measure | Keep the results of the 1.1.0 stop test. Measure pressure, swap rate (difference between two samples), compression and decompression, overlapping heavy jobs, across many work sessions. Minimal 24 hour history | Representative data from the team's 8 GB Mac; if lacking, add reproduction scenarios |
| 2. `8gb status` over MCP (phases 0 and 1, in progress) | `8gbvibe-mcp` (stdio, inside the app bundle): read tools `machine_status`, `heavy_processes`, `agent_sessions`, `hardware_profile`, `can_start`; coordination tools `register_agent`, `heartbeat`, `acquire_slot` (returns `slot`, `advice` and `start_now`), `renew_slot`, `my_slots`, `release_slot` (one heavy-job slot for any Mac: this is a conservative coordination policy, not a limit of the Mac, with no option to raise it yet; at most 30 minutes per lease, 2 hours in total), `slots`, `post_message`/`read_messages`. An agent counts as alive by its MCP process (pid and start time), not by whether the model calls a tool. Each slot has two separate fields: `lease` (`active`, `expired`, `overdue`) and `task` (`running`, `ended`, `unknown`). When the lease runs out while that session's heavy job is still running: `lease: expired`, `task: running`, the slot is not given to anyone else and the job is not stopped. Past the 2 hour total with the job still running: `lease: overdue`, the app flags it in the bell and in Settings > AI Agents with a "Release slot" button (asks first, logs it, only drops the reservation, never touches the process). Includes the measurement time and data age, returns "unknown" when there is no measurement. Advice and voluntary reservation only. Settings has 3 permission levels and a list of the agent clients found on the Mac (Claude Code, Codex, Gemini CLI, Cursor, Claude Desktop, Antigravity), one row per client: configuration status, number of connected agents, "Install" and "Remove" buttons (section 8 of the MCP document). Details: [docs/MCP.md](MCP.md) | A real agent reads it and follows it in a demo |
| 3. Complete per-session cleanup | Building on 1.1.0 (orphans with known origin, MCP per session): clean up what a session left behind in one go, with approval; `8gb leftovers` | Reliable origin, approval, measurable GB recovered, no wrong stops |
| 4. Choose based on data | One of: deeper cleanup, suggestions to lower parallelism (for example `--maxWorkers`, `org.gradle.workers.max`), or a heavy-job queue (`8gb run`) | Proof of which kinds of work benefit and the time trade-off |
| 5. Validation beyond the team's Mac | 5 to 10 testers, at least 3 Macs with 8 GB; demo; community groundwork | Benefits repeat; promises match the release |

The other planned features (agent finished via hooks, cache cleaning with Trash, Vibe modes, lower priority of background apps, configuration tips, 8GB Vibe MCP server, weekly report) stay in the list in section 2 and are scheduled after step 4 based on measured data. Remote control remains after 2.0.

Decisions made on 2026-11-08:
- Build the public groundwork in parallel from now on: LICENSE, CI build and core tests, Homebrew cask, CONTRIBUTING, SECURITY, issue templates.
- Fix the sentence "Room for N more agent sessions before swapping": done in version 1.1.1 (an estimate, three states: room, nearly full, short of RAM).
- Message: Macs short of RAM when running agents (8 GB, and 16 GB running many agents); keep the name 8GB Vibe.
- Make the repository public once step 3 and the public groundwork are done (using a new, clean repository).
- License: **Apache 2.0** for the source code. Section 6 of the license does not grant trademark rights: the name 8GB Vibe, the app icon and the BEECA logo are reserved, as noted in `TRADEMARKS.md` and the README.

After step 2 (MCP): phase 3 "cleanup requests awaiting approval in the app"; later phases: a "Do low-risk work automatically" permission level and a switch "agents stop their own session's orphans when the Mac is short of RAM" (off by default, logged). A `PreToolUse` hook to enforce slot reservation will only be built if the measured data calls for it.

## 4. Principles

- Every action asks first. Nothing is quit, deleted or hooked automatically.
- By default no data is sent anywhere. Hooks, phone notifications and remote control are optional and must be turned on by the user.
- The app always stays light: under 50 MB of RAM, near 0 % CPU in the background.
- Never turns off macOS services, never uses `purge`, never reads the Keychain or cookies, never opens an HTTP server on the Mac.
- Keeps supporting Intel Macs (universal build).
