import AppKit
import SwiftUI
import VibeCore

/// Small window shown when clicking the menu bar icon.
/// macOS keeps this window alive even when closed, so content is only drawn while visible to save CPU.
struct PopoverView: View {
    @EnvironmentObject var monitor: Monitor

    // Content is always built. Gating it on a visibility notice left the panel blank on many Macs
    // (Apple silicon and Intel, 1.2.0): macOS does not reliably report the menu bar panel's visibility.
    // The tracker now only tells the Monitor to sample faster while the panel is open.
    var body: some View {
        PopoverContent()
            .background(VisibilityTracker(requireUnoccluded: false) { v in
                monitor.reportVisibility("popover", v)
            })
    }
}

struct PopoverContent: View {
    @EnvironmentObject var monitor: Monitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            // Newest unread alert, if any.
            InboxStrip { page in open(page) }.padding(.top, 10)
            if let h = monitor.system {
                // The one thing to do now; acting on it opens the main window on the right page.
                AdviceCard(compact: true) { action in
                    if action == .freeRAM { open(.freeRAM) }
                    if action == .reviewSessions { open(.agents) }
                    if action == .reviewDisk { open(.disk) }
                }
                .padding(.top, 12)
                metric(h).padding(.top, 12)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Swap · recent history").font(.callout.weight(.medium)).foregroundStyle(.secondary)
                        Spacer()
                        Text(Format.bytes(h.swap.used)).font(.callout).monospacedDigit().foregroundStyle(.secondary)
                    }
                    AreaChart(value: monitor.history.map(\.swapGB), thresholds: monitor.thresholds.swapYellowGB,
                               color: (monitor.levels[.swap] ?? .ok) == .ok ? .teal : (monitor.levels[.swap] ?? .ok).color, high: 30)
                        .collecting(monitor.history.count < 6)
                }
                .padding(.top, 14)
                topApp.padding(.top, 14)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(30)
            }
            Divider().padding(.vertical, 10)
            footer
        }
        .padding(16)
        .frame(width: 320)
    }

    /// Status readable in one second: score ring, one line, and the command palette shortcut.
    private var head: some View {
        HStack(spacing: 12) {
            HealthRing(score: monitor.score, size: 44, label: nil)
            VStack(alignment: .leading, spacing: 1) {
                Text(HealthScore.summary(monitor.score)).font(.title3.weight(.bold))
                if let h = monitor.system {
                    Text("Swap \(Format.bytes(h.swap.used)) · RAM \(Format.percent(h.memory.usedRatio))")
                        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Spacer(minLength: 0)
            Button { openPalette() } label: { KeyHint("⌘K") }
                .buttonStyle(.plain)
                .help("Search or run a command")
                .accessibilityLabel("Open command palette")
        }
    }

    private func metric(_ h: SystemSnapshot) -> some View {
        HStack(spacing: 8) {
            o("RAM", Format.percent(h.memory.usedRatio), h.memory.usedRatio, color(.pressure, .blue))
            o("Swap", Format.bytes(h.swap.used),
              Double(h.swap.used) / Format.GB / max(1, monitor.thresholds.swapRedGB), color(.swap, .teal))
            // Every agent session (Claude Code, Codex, Gemini...), counted like the AI Agents page and MCP.
            let sessions = AIToolBuilder.from(monitor.processes).flatMap(\.sessions).count
            VStack(alignment: .leading, spacing: 5) {
                Text("AI sessions").font(.callout).foregroundStyle(.secondary)
                Text("\(sessions)").font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("Open").font(.callout).foregroundStyle(.secondary)
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        }
    }

    private func o(_ label: LocalizedStringKey, _ value: String, _ ratio: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit().motionCount()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(color.gradient).frame(width: geo.size.width * max(0.03, min(1, ratio)))
                }
            }
            .frame(height: 4)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    /// Real top RAM users across every group (apps, the Claude VM, agent sessions, system), including protected ones,
    /// shown as observation. Only items that can be quit get a button, which opens Free RAM with that app selected.
    private var topApp: some View {
        let items = monitor.processes.groups.flatMap(\.items).sorted { $0.footprint > $1.footprint }.prefix(4)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Top RAM users").font(.callout.weight(.medium)).foregroundStyle(.secondary)
            ForEach(Array(items)) { item in
                let u = monitor.candidates.first { $0.name == item.name }
                HStack(spacing: 10) {
                    if let u { CandidateIcon(u: u, size: 22) } else { GroupIcon(group: item.group, size: 22) }
                    Text(item.name).lineLimit(1)
                    // Anything that cannot be quit from here (protected app, VM, system, agent sessions) shows a lock.
                    if u == nil || u?.blockedReason != nil {
                        Image(systemName: "lock.fill").font(.callout).foregroundStyle(.tertiary)
                            .help(u?.blockedReason ?? String(localized: "Not quit from here", bundle: .main))
                            .accessibilityLabel("Not quit from here")
                    }
                    Spacer()
                    Text(Format.bytes(item.footprint)).monospacedDigit().foregroundStyle(.secondary)
                    if let u, u.blockedReason == nil {
                        Button {
                            monitor.freeRAMPreselect = [u.id]
                            open(.freeRAM)
                        } label: { Image(systemName: "xmark.circle") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary)
                            .help("Close \(u.name)… (asks first)").accessibilityLabel("Close \(u.name)")
                    }
                }
                .font(.callout)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button { open(monitor.page) } label: { Label("Open \(Product.name)", systemImage: "macwindow") }
                .keyboardShortcut("1")
            Spacer()
            Button { open(.about) } label: { Image(systemName: "info.circle") }
                .help("About \(Product.name)").accessibilityLabel("About \(Product.name)")
            Button { open(.settings) } label: { Image(systemName: "gearshape") }
                .help("Settings").accessibilityLabel("Settings")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .keyboardShortcut("q")
                .help("Quit \(Product.name)").accessibilityLabel("Quit \(Product.name)")
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private func color(_ c: Metric, _ defaultValue: Color) -> Color {
        let m = monitor.levels[c] ?? .ok
        return m == .ok ? defaultValue : m.color
    }

    /// Opens the main window with the command palette showing.
    private func openPalette() {
        openWindow(id: StoredName.mainWindow)
        NSApp.activate(ignoringOtherApps: true)
        monitor.showPalette = true
    }

    private func open(_ page: Page) {
        monitor.page = page
        openWindow(id: StoredName.mainWindow)
        NSApp.activate(ignoringOtherApps: true)
    }
}
