import AppKit
import SwiftUI
import VibeCore

/// Main window, laid out like System Settings.
struct MainWindow: View {
    @EnvironmentObject var monitor: Monitor
    @ObservedObject private var inbox = Inbox.shared

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            Group {
                switch monitor.page {
                case .overview: OverviewPage()
                case .memory: MemoryPage()
                case .agents: AgentsPage()
                case .devServers: DevServersPage()
                case .processes: ProcessesPage()
                case .disk: DiskPage()
                case .backgroundItems: BackgroundPage()
                case .machine: MachinePage()
                case .freeRAM: FreeRAMPage()
                case .log: LogPage()
                case .inbox: InboxPage()
                case .settings: SettingsPage()
                case .about: AboutPage()
                }
            }
            .navigationTitle(monitor.page.name)
            // Title bar without its own band: the standard band starts a few points off the sidebar divider (a visible
            // seam the owner rejected). Instead every page is clipped to the area under the title bar, so scrolled
            // content (scroll views, the Settings form, tables) never runs behind the page title.
            .toolbarBackground(.hidden, for: .windowToolbar)
            .clipped()
            .sheet(isPresented: $monitor.showWelcome) { WelcomeSheet().environmentObject(monitor) }
            // Reward after a cleanup: slides up from the bottom of the content area, then hides itself.
            .overlay(alignment: .bottom) {
                if let freed = monitor.lastFreed {
                    RewardCard(summary: freed, close: {
                        if monitor.lastFreed?.id == freed.id { monitor.lastFreed = nil }
                    }, openLog: { monitor.page = .log; monitor.lastFreed = nil })
                    .frame(maxWidth: 460)
                    .padding(20)
                    .id(freed.id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: monitor.lastFreed?.id)
        }
        // Cmd-K command palette over the whole window, with the content dimmed behind it.
        .overlay {
            if monitor.showPalette {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.25).ignoresSafeArea().onTapGesture { monitor.showPalette = false }
                    CommandPalette().padding(.top, 70)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: monitor.showPalette)
        .background {
            // Invisible buttons own the shortcuts while the main window is key (this menu bar app has no menu bar of
            // its own): Cmd-K for the palette, Cmd-1...9 and Cmd-comma for pages.
            ZStack {
                Button("") { monitor.showPalette.toggle() }.keyboardShortcut("k")
                ForEach(Page.allCases) { p in
                    if let k = p.shortcut {
                        Button("") { monitor.page = p; monitor.showPalette = false }.keyboardShortcut(KeyEquivalent(k))
                    }
                }
            }
            .opacity(0).accessibilityHidden(true)
        }
        .background(VisibilityTracker { monitor.reportVisibility("main-window", $0) })
        .sheet(item: Binding(get: { monitor.pendingConfirmation.map { QuitRequest(items: $0) } },
                             set: { if $0 == nil { monitor.pendingConfirmation = nil } })) { g in
            QuitConfirmation(items: g.items).environmentObject(monitor)
        }
        .confirmationDialog("Force quit \(monitor.pendingForceQuit?.name ?? "")?",
                            isPresented: Binding(get: { monitor.pendingForceQuit != nil }, set: { if !$0 { monitor.pendingForceQuit = nil } }),
                            presenting: monitor.pendingForceQuit) { u in
            Button("Force Quit", role: .destructive) { monitor.forceQuit(u) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The app did not quit after 10 seconds. Force quitting may lose unsaved work.")
        }
    }
}

extension MainWindow {
    /// Standard sidebar list: system selection, keyboard navigation and VoiceOver come for free.
    private var sidebar: some View {
        List(selection: Binding<Page?>(get: { monitor.page }, set: { if let p = $0 { monitor.page = p } })) {
            ForEach(Page.sidebarGroups, id: \.pages) { group in
                Section(group.title) {
                    ForEach(group.pages) { sidebarRow($0) }
                }
            }
        }
        .listStyle(.sidebar)
        // Icons follow the chosen accent. The selection fill is drawn by macOS from the app's accent (emerald) and
        // cannot change at runtime; that is the trade-off for the standard sidebar.
        .listItemTint(Palette.tint)
        .safeAreaInset(edge: .top) { sidebarHeader }
        .navigationSplitViewColumnWidth(min: 190, ideal: 210)
    }

    /// Sidebar row: symbol and name. The shortcut is not printed in the row (it cluttered the list); it is in the
    /// tooltip, the View menu and the Cmd-K palette. Notifications carry the unread count as a standard badge.
    func sidebarRow(_ t: Page) -> some View {
        Label(t.name, systemImage: t.symbol)
            .badge(t == .inbox ? inbox.unread.count : 0)
            .help(t.shortcutHint.map { Text("\(t.name) (\($0))") } ?? Text(t.name))
            .tag(t)
    }

    /// Sidebar header: icon, app name, health score.
    var sidebarHeader: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 34, height: 34)
            // The icon already reads "8GB", so no wordmark next to it: just the Mac's status, readable at a glance.
            VStack(alignment: .leading, spacing: 2) {
                Text(HealthScore.summary(monitor.score))
                    .font(.headline)
                    .lineLimit(1).minimumScaleFactor(0.85)
                HStack(spacing: 5) {
                    Circle().fill(Palette.forScore(monitor.score)).frame(width: 8, height: 8)
                    Text("Score \(monitor.score)").font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .accessibilityElement(children: .combine)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 10)
    }
}

/// Wraps the list for use with .sheet(item:).
struct QuitRequest: Identifiable {
    var items: [QuitCandidate]
    var id: String { items.map(\.id).joined(separator: ",") }
}

/// Shared scroll container for pages.
struct PageContainer<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        // Always open at the top. macOS moves focus to the last button on the page and scrolls to it, so scroll back up.
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id("page-top")
                    VStack(alignment: .leading, spacing: 16) { content }
                    Color.clear.frame(height: 0).id("page-bottom")
                }
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                // Three times: on a busy Mac the focus jump can land late; a page left half-scrolled showed its top line cut under the title bar.
                for delay in [0.05, 0.5, 1.2] where !CommandLine.arguments.contains("--scroll-end") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { proxy.scrollTo("page-top", anchor: .top) }
                }
                // --scroll-end: scrolls to the bottom once loaded, to check the title bar over scrolled content (UI testing).
                if CommandLine.arguments.contains("--scroll-end") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { proxy.scrollTo("page-bottom", anchor: .bottom) }
                }
            }
        }
    }
}

struct SectionTitle: View {
    var s: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    init(_ s: LocalizedStringKey, subtitle: LocalizedStringKey? = nil) { self.s = s; self.subtitle = subtitle }
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(s).font(.headline)
            Spacer()
            if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
        }
    }
}

// MARK: Overview

struct OverviewPage: View {
    @EnvironmentObject var monitor: Monitor

    var body: some View {
        PageContainer {
            if let h = monitor.system {
                // Lead with what to do now: the score ring next to one sentence of advice and one button.
                HStack(alignment: .center, spacing: 20) {
                    HealthRing(score: monitor.score, size: 110)
                    AdviceCard()
                }
                // Three cards, three questions: how full is RAM, is swap growing, can I open another session.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    MetricCard(label: "RAM", symbol: "memorychip", value: Format.percent(h.memory.usedRatio),
                             subtitle: "\(Format.bytes(h.memory.used)) / \(Format.bytes(h.memory.total, digits: 0))",
                             color: metricColor(.pressure, defaultValue: .blue), data: monitor.history.map { $0.ramRatio * 100 }, ceiling: 100)
                    MetricCard(label: "Swap", symbol: "arrow.left.arrow.right", value: Format.bytes(h.swap.used),
                             subtitle: "Yellow at \(Format.number(monitor.thresholds.swapYellowGB, digits: 0)) GB",
                             color: metricColor(.swap, defaultValue: .teal), data: monitor.history.map(\.swapGB), thresholds: monitor.thresholds.swapYellowGB)
                        .help("Swap is memory temporarily moved to disk. Space used differs from the rate of swap I/O.")
                    sessionRoomCard
                }
                secondaryLine(h)
                topRAMUsers
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 300)
            }
        }
    }

    /// "Can I open another agent session?" answered in one word, from the RAM budget estimate.
    private var sessionRoomCard: some View {
        let state = monitor.budget.map { SessionHeadroom(budget: $0, sessions: AIToolBuilder.from(monitor.processes).flatMap(\.sessions)).state }
        let (value, color): (String, Color) = {
            switch state {
            case .room(let n)?: return (n > 9 ? "~9+" : "~\(n)", n >= 2 ? .green : .orange)
            case .tight?: return (String(localized: "Tight", bundle: .main), .orange)
            case .short?: return (String(localized: "No room", bundle: .main), .red)
            case nil: return ("-", .secondary)
            }
        }()
        return Button { monitor.page = .agents } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").foregroundStyle(color)
                    Text("Extra sessions (estimate)").foregroundStyle(.secondary)
                }
                .font(.callout)
                Text(value).font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(color)
                Text("\(AIToolBuilder.from(monitor.processes).flatMap(\.sessions).count) agent sessions open").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                Text("View AI Agents ›").font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .card(padding: 14)
    }

    /// CPU and disk in one quiet line; each part opens its page.
    private func secondaryLine(_ h: SystemSnapshot) -> some View {
        HStack(spacing: 16) {
            Button { monitor.page = .processes } label: {
                Label("CPU \(Format.number(h.load.m5, digits: 1)) on \(h.coreCount) cores", systemImage: "cpu")
                    .foregroundStyle(metricColor(.load, defaultValue: .secondary))
            }
            Button { monitor.page = .disk } label: {
                Label("Free disk \(Format.bytes(h.disk.free, digits: 0))", systemImage: "internaldrive")
                    .foregroundStyle(metricColor(.disk, defaultValue: .secondary))
            }
            Spacer()
            // Before the first process scan the timestamp is the reference date: say it is still reading instead of "739,929 days ago".
            if let age = monitor.processesAge {
                Text("Updated \(Format.duration(age)) ago").foregroundStyle(.secondary)
            } else {
                Text("Reading processes…").foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .font(.callout)
        .monospacedDigit()
    }

    private var topRAMUsers: some View {
        let items = Array(monitor.candidates.prefix(6))
        let largest = Double(items.first?.footprint ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle("Who is using RAM", subtitle: nil)
                Spacer()
                Button("Free RAM ›") { monitor.page = .freeRAM }.buttonStyle(.link)
            }
            ForEach(items) { u in
                HStack(spacing: 10) {
                    CandidateIcon(u: u, size: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(u.name).lineLimit(1)
                            Spacer()
                            statusChip(u)
                            Text(Format.bytes(u.footprint)).monospacedDigit().foregroundStyle(.secondary).frame(width: 70, alignment: .trailing)
                        }
                        GeometryReader { geo in
                            Capsule().fill(u.group.color.gradient)
                                .frame(width: max(4, geo.size.width * Double(u.footprint) / largest))
                        }
                        .frame(height: 5)
                    }
                }
            }
            if items.isEmpty { Text("Reading…").foregroundStyle(.secondary) }
        }
        .card()
    }

    @ViewBuilder
    private func statusChip(_ u: QuitCandidate) -> some View {
        if u.blockedReason != nil {
            StatusPill(owner: "Protected", color: .secondary)
        } else if u.isFrontmost {
            StatusPill(owner: "In use", color: .blue)
        } else if let st = monitor.displayStatus(cpu: u.cpu, lastActive: u.lastActive) {
            StatusPill(owner: LocalizedStringKey(st.0), color: st.1)
        }
    }

    private func metricColor(_ c: Metric, defaultValue: Color) -> Color {
        let m = monitor.levels[c] ?? .ok
        return m == .ok ? defaultValue : m.color
    }
}

// MARK: Memory

struct MemoryPage: View {
    @EnvironmentObject var monitor: Monitor
    @State private var expanded: Set<WorkCategory> = [.claude]

    var body: some View {
        PageContainer {
            if let h = monitor.system, let budget = monitor.budget {
                // The budget sits in a card like every other section.
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("RAM budget", subtitle: monitor.processesAge.map { "Estimate. Updated \(Format.duration($0)) ago" } ?? "Estimate")
                    BudgetBar(budget: budget)
                    Text("Estimated readable process memory plus wired memory: \(Format.bytes(budget.demand)). This Mac has \(Format.bytes(budget.totalRAM, digits: 0)). Some system processes are not included.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .card()

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    StatBox(label: "Used", value: Format.bytes(h.memory.used), subtitle: "Of \(Format.bytes(h.memory.total, digits: 0))")
                    StatBox(label: "Wired", value: Format.bytes(h.memory.wired), subtitle: "Held by system")
                    StatBox(label: "Compressed memory", value: Format.bytes(h.memory.compressed), subtitle: "Compressed to avoid swap")
                    StatBox(label: "Swap", value: Format.bytes(h.swap.used),
                            color: (monitor.levels[.swap] ?? .ok) == .ok ? .primary : (monitor.levels[.swap] ?? .ok).color,
                            subtitle: "On disk, slow")
                }

                groupTable
            } else {
                ProgressView()
            }
        }
    }

    private var groupTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Group").frame(maxWidth: .infinity, alignment: .leading)
                Text("RAM").frame(width: 80, alignment: .trailing)
                Text("CPU").frame(width: 60, alignment: .trailing)
                Text("Status").frame(width: 130, alignment: .trailing)
            }
            .font(.callout).foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))
            ForEach(monitor.processes.groups) { n in
                Divider()
                groupRow(n)
                if expanded.contains(n.group) {
                    ForEach(n.items) { m in
                        Divider().padding(.leading, 40)
                        itemRow(m)
                    }
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func groupRow(_ n: GroupUsage) -> some View {
        Button {
            if expanded.contains(n.group) { expanded.remove(n.group) } else { expanded.insert(n.group) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: expanded.contains(n.group) ? "chevron.down" : "chevron.right")
                    .font(.callout).foregroundStyle(.secondary).frame(width: 10)
                GroupIcon(group: n.group, size: 20)
                Text(n.group.name).fontWeight(.medium)
                Text("\(n.processCount) processes").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Text(Format.bytes(n.footprint)).frame(width: 80, alignment: .trailing)
                Text(Format.number(n.cpu, digits: 0) + Format.percentSign).frame(width: 60, alignment: .trailing).foregroundStyle(.secondary)
                Text("").frame(width: 130)
            }
            .monospacedDigit()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .accessibilityHint(expanded.contains(n.group) ? String(localized: "Collapse", bundle: .main) : String(localized: "Expand", bundle: .main))
    }

    private func itemRow(_ m: ItemUsage) -> some View {
        let isClaudeCode = m.group == .claude && m.name == ItemName.claudeCode
        return HStack(spacing: 8) {
            Text(isClaudeCode ? String(localized: "\(m.name) · \(monitor.processes.sessions.count) sessions", bundle: .main) : m.name)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(Format.bytes(m.footprint)).frame(width: 80, alignment: .trailing)
            Text(Format.number(m.cpu, digits: 0) + Format.percentSign).frame(width: 60, alignment: .trailing).foregroundStyle(.secondary)
            status(m, isClaudeCode: isClaudeCode).frame(width: 130, alignment: .trailing)
        }
        .monospacedDigit()
        .font(.callout)
        .padding(.leading, 48).padding(.trailing, 10).padding(.vertical, 6)
    }

    @ViewBuilder
    private func status(_ m: ItemUsage, isClaudeCode: Bool) -> some View {
        if isClaudeCode {
            let idleCount = monitor.processes.sessions.filter { monitor.isSessionIdle($0) }.count
            if idleCount > 0 {
                Text("\(idleCount) idle").foregroundStyle(.orange)
            } else {
                let stillMonitoring = Date().timeIntervalSince(monitor.monitoringStart) < monitor.thresholds.idleMinutes * 60
                Text(stillMonitoring ? String(localized: "Wait \(Format.number(monitor.thresholds.idleMinutes, digits: 0)) min", bundle: .main) : String(localized: "No idle sessions", bundle: .main)).foregroundStyle(.secondary)
            }
        } else if [ItemName.claudeVM, ItemName.dockerVM, ItemName.otherVM].contains(m.name) {
            Text("Running \(Format.duration(Date().timeIntervalSince(m.earliestStart)))").foregroundStyle(.secondary)
        } else {
            if let statusText = monitor.displayStatus(cpu: m.cpu, lastActive: m.lastActive) {
                Text(statusText.0).foregroundStyle(statusText.1)
            } else {
                Text("-").foregroundStyle(.tertiary)
            }
        }
    }
}
