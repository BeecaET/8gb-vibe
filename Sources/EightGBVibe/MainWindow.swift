import AppKit
import SwiftUI
import VibeCore

/// Main window, laid out like System Settings.
struct MainWindow: View {
    @EnvironmentObject var monitor: Monitor

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { monitor.page }, set: { if let t = $0 { monitor.page = t } })) {
                Section("Vibe") {
                    ForEach([Page.agents, .devServers]) { t in
                        Label(t.name, systemImage: t.symbol).tag(t)
                    }
                }
                Section("Xem") {
                    ForEach([Page.overview, .memory, .processes, .disk, .backgroundItems]) { t in
                        Label(t.name, systemImage: t.symbol).tag(t)
                    }
                }
                Section("Xử lý") {
                    ForEach([Page.freeRAM, .log]) { t in
                        Label(t.name, systemImage: t.symbol).tag(t)
                    }
                }
                Section("Ứng dụng") {
                    ForEach([Page.settings, .about]) { t in
                        Label(t.name, systemImage: t.symbol).tag(t)
                    }
                }
            }
            .safeAreaInset(edge: .top) { sidebarHeader }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
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
                case .freeRAM: FreeRAMPage()
                case .log: LogPage()
                case .settings: SettingsPage()
                case .about: AboutPage()
                }
            }
            .navigationTitle(monitor.page.name)
            // Reward after a cleanup: slides up from the bottom of the content area, then hides itself.
            .overlay(alignment: .bottom) {
                if let freed = monitor.lastFreed {
                    RewardCard(summary: freed) {
                        if monitor.lastFreed?.id == freed.id { monitor.lastFreed = nil }
                    }
                    .frame(maxWidth: 460)
                    .padding(20)
                    .id(freed.id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: monitor.lastFreed?.id)
        }
        .background(VisibilityTracker { monitor.reportVisibility("main-window", $0) })
        .sheet(item: Binding(get: { monitor.pendingConfirmation.map { QuitRequest(items: $0) } },
                             set: { if $0 == nil { monitor.pendingConfirmation = nil } })) { g in
            QuitConfirmation(items: g.items).environmentObject(monitor)
        }
        .confirmationDialog("Buộc thoát \(monitor.pendingForceQuit?.name ?? "")?",
                            isPresented: Binding(get: { monitor.pendingForceQuit != nil }, set: { if !$0 { monitor.pendingForceQuit = nil } }),
                            presenting: monitor.pendingForceQuit) { u in
            Button("Buộc thoát", role: .destructive) { monitor.forceQuit(u) }
            Button("Huỷ", role: .cancel) {}
        } message: { _ in
            Text("App chưa tự đóng sau 10 giây. Buộc thoát có thể làm mất dữ liệu chưa lưu.")
        }
    }
}

extension MainWindow {
    /// Sidebar header: icon, app name, health score.
    var sidebarHeader: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                (Text("8GB").font(.system(size: 16, weight: .heavy, design: .rounded))
                 + Text(" Vibe").font(.system(size: 15, weight: .regular, design: .rounded)).foregroundColor(.secondary))
                HStack(spacing: 5) {
                    Circle().fill(Palette.forScore(monitor.score)).frame(width: 7, height: 7)
                    // One line: long English summaries shrink slightly instead of wrapping the score onto a new line.
                    Text("\(HealthScore.summary(monitor.score)) · \(monitor.score)").font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
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
                VStack(alignment: .leading, spacing: 16) {
                    Color.clear.frame(height: 0).id("page-top")
                    content
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { proxy.scrollTo("page-top", anchor: .top) }
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
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

// MARK: Overview

struct OverviewPage: View {
    @EnvironmentObject var monitor: Monitor

    var body: some View {
        PageContainer {
            if let h = monitor.system {
                hero
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    MetricCard(label: "RAM", symbol: "memorychip", value: Format.percent(h.memory.usedRatio),
                             subtitle: "\(Format.bytes(h.memory.used)) / \(Format.bytes(h.memory.total, digits: 0))",
                             color: metricColor(.pressure, defaultValue: .blue), data: monitor.history.map { $0.ramRatio * 100 }, ceiling: 100)
                    MetricCard(label: "Swap", symbol: "arrow.left.arrow.right", value: Format.bytes(h.swap.used),
                             subtitle: "Ngưỡng vàng \(Format.number(monitor.thresholds.swapYellowGB, digits: 0)) GB",
                             color: metricColor(.swap, defaultValue: .teal), data: monitor.history.map(\.swapGB), thresholds: monitor.thresholds.swapYellowGB)
                    MetricCard(label: "Tải CPU", symbol: "cpu", value: Format.number(h.load.m5, digits: 1),
                             subtitle: "5 phút · \(h.coreCount) nhân",
                             color: metricColor(.load, defaultValue: .indigo), data: monitor.history.map(\.load), thresholds: Double(h.coreCount))
                    diskCard(h)
                }
                // Both cards have the same height so no uneven gap is left.
                HStack(alignment: .top, spacing: 12) {
                    topRAMUsers.frame(maxHeight: .infinity, alignment: .top)
                    suggestions.frame(maxHeight: .infinity, alignment: .top)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 300)
            }
        }
    }

    private var hero: some View {
        HStack(spacing: 28) {
            HealthRing(score: monitor.score, size: 150)
            VStack(alignment: .leading, spacing: 10) {
                Text(HealthScore.summary(monitor.score))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(monitor.explanation)
                    .font(.title3).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if monitor.freeableFromCandidates > 0 {
                        Button { monitor.page = .freeRAM } label: {
                            Label("Dọn RAM · giải phóng \(Format.bytes(monitor.freeableFromCandidates))", systemImage: "wand.and.stars")
                        }
                        .buttonStyle(PrimaryButtonStyle(large: true))
                    } else {
                        Button { monitor.page = .freeRAM } label: { Label("Dọn RAM", systemImage: "wand.and.stars") }
                            .buttonStyle(PrimaryButtonStyle(large: true))
                    }
                    Button("Xem bộ nhớ") { monitor.page = .memory }.controlSize(.large)
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Palette.forScore(monitor.score).opacity(0.10), Color(nsColor: .controlBackgroundColor)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.primary.opacity(0.07), lineWidth: 1))
    }

    private func diskCard(_ h: SystemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "internaldrive").foregroundStyle(metricColor(.disk, defaultValue: .purple))
                Text("Ổ trống").foregroundStyle(.secondary)
            }
            .font(.callout)
            Text(Format.bytes(h.disk.free, digits: 0))
                .font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
            Text("Đầy \(Format.percent(h.disk.fullRatio)) · \(Format.bytes(h.disk.total, digits: 0))")
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(metricColor(.disk, defaultValue: .purple).gradient)
                        .frame(width: geo.size.width * h.disk.fullRatio)
                }
            }
            .frame(height: 8)
            .padding(.bottom, 13)
        }
        .card(padding: 14)
    }

    private var topRAMUsers: some View {
        let items = Array(monitor.candidates.prefix(6))
        let largest = Double(items.first?.footprint ?? 1)
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Ai đang chiếm RAM", subtitle: "App và dịch vụ lớn nhất")
            ForEach(items) { u in
                HStack(spacing: 10) {
                    CandidateIcon(u: u, size: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(u.name).lineLimit(1)
                            Spacer()
                            Text(Format.bytes(u.footprint)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        GeometryReader { geo in
                            Capsule().fill(u.group.color.gradient)
                                .frame(width: max(4, geo.size.width * Double(u.footprint) / largest))
                        }
                        .frame(height: 5)
                    }
                }
            }
            if items.isEmpty { Text("Đang đọc…").foregroundStyle(.secondary) }
        }
        .card()
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Gợi ý")
            if monitor.suggestions.isEmpty {
                // Empty state centered in the card.
                let waiting = Date().timeIntervalSince(monitor.monitoringStart) < monitor.thresholds.idleMinutes * 60
                VStack(spacing: 8) {
                    Image(systemName: waiting ? "hourglass" : "checkmark.seal.fill")
                        .font(.system(size: 30)).foregroundStyle(waiting ? Color.secondary : Color.green)
                    Text(waiting ? String(localized: "Đang tìm app rảnh", bundle: .main) : String(localized: "Không có gì cần tắt", bundle: .main)).font(.headline)
                    Text(waiting ? String(localized: "Gợi ý có sau \(Format.number(monitor.thresholds.idleMinutes, digits: 0)) phút theo dõi.", bundle: .main)
                                 : String(localized: "Không app nào rảnh lâu.", bundle: .main))
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Mở Dọn RAM") { monitor.page = .freeRAM }.padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 12)
            }
            ForEach(monitor.suggestions.prefix(5)) { g in
                HStack(spacing: 10) {
                    if case let .quitAll(u) = g.kind {
                        CandidateIcon(u: u, size: 28)
                    } else {
                        GroupIcon(group: .claude, size: 28)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(g.title).lineLimit(1)
                        Text(g.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text("-\(Format.bytes(g.freed))").monospacedDigit().foregroundStyle(.green)
                }
            }
            if !monitor.suggestions.isEmpty {
                HStack {
                    Spacer()
                    if monitor.suggestions.contains(where: { $0.kind == .archiveClaudeSessions }) {
                        Button("Mở Claude") { monitor.openClaude() }
                    }
                    Button("Xem và tắt") { monitor.page = .freeRAM }.buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .card()
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
                SectionTitle("Ngân sách RAM", subtitle: "Ước tính. Cập nhật \(Format.duration(Date().timeIntervalSince(monitor.processes.timestamp))) trước")
                BudgetBar(budget: budget)
                Text("Các app cần khoảng \(Format.bytes(budget.demand)) nếu không nén. Máy có \(Format.bytes(budget.totalRAM, digits: 0)).")
                    .font(.callout).foregroundStyle(.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    StatBox(label: "Đã dùng", value: Format.bytes(h.memory.used), subtitle: "Trên \(Format.bytes(h.memory.total, digits: 0))")
                    StatBox(label: "Wired", value: Format.bytes(h.memory.wired), subtitle: "Hệ thống giữ")
                    StatBox(label: "Đã nén", value: Format.bytes(h.memory.compressed), subtitle: "macOS nén để đỡ swap")
                    StatBox(label: "Swap", value: Format.bytes(h.swap.used),
                            color: (monitor.levels[.swap] ?? .ok) == .ok ? .primary : (monitor.levels[.swap] ?? .ok).color,
                            subtitle: "Trên ổ đĩa, chậm")
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
                Text("Nhóm").frame(maxWidth: .infinity, alignment: .leading)
                Text("RAM").frame(width: 80, alignment: .trailing)
                Text("CPU").frame(width: 60, alignment: .trailing)
                Text("Trạng thái").frame(width: 130, alignment: .trailing)
            }
            .font(.caption).foregroundStyle(.secondary)
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
                    .font(.caption2).foregroundStyle(.secondary).frame(width: 10)
                GroupIcon(group: n.group, size: 20)
                Text(n.group.name).fontWeight(.medium)
                Text("\(n.processCount) tiến trình").font(.caption).foregroundStyle(.tertiary)
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
        .accessibilityHint(expanded.contains(n.group) ? String(localized: "Thu gọn", bundle: .main) : String(localized: "Mở rộng", bundle: .main))
    }

    private func itemRow(_ m: ItemUsage) -> some View {
        let isClaudeCode = m.group == .claude && m.name == ItemName.claudeCode
        return HStack(spacing: 8) {
            Text(isClaudeCode ? String(localized: "\(m.name) · \(monitor.processes.sessions.count) phiên", bundle: .main) : m.name)
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
                Text("\(idleCount) rảnh").foregroundStyle(.orange)
            } else {
                let stillMonitoring = Date().timeIntervalSince(monitor.monitoringStart) < monitor.thresholds.idleMinutes * 60
                Text(stillMonitoring ? String(localized: "Chờ đủ \(Format.number(monitor.thresholds.idleMinutes, digits: 0)) ph", bundle: .main) : String(localized: "Không có phiên rảnh", bundle: .main)).foregroundStyle(.secondary)
            }
        } else if [ItemName.claudeVM, ItemName.dockerVM, ItemName.otherVM].contains(m.name) {
            Text("Chạy \(Format.duration(Date().timeIntervalSince(m.earliestStart)))").foregroundStyle(.secondary)
        } else {
            if let statusText = monitor.displayStatus(cpu: m.cpu, lastActive: m.lastActive) {
                Text(statusText.0).foregroundStyle(statusText.1)
            } else {
                Text("-").foregroundStyle(.tertiary)
            }
        }
    }
}
