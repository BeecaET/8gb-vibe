import AppKit
import SwiftUI
import VibeCore

/// All AI tools on one page: CLI agents (per session), AI apps, AI IDEs. Includes an estimate of how many more sessions fit.
struct AgentsPage: View {
    @EnvironmentObject var monitor: Monitor
    @State private var expanded: Set<String> = []
    /// Tools whose full session list is shown (by default only the heaviest few are listed).
    @State private var showAllSessions: Set<String> = []
    @State private var didAutoExpand = false
    private static let sessionPreview = 8

    var body: some View {
        let items = AIToolBuilder.from(monitor.processes)
        let sessions = items.flatMap(\.sessions)
        PageContainer {
            Color.clear.frame(height: 0).onAppear { autoExpand(items) }
            if let budget = monitor.budget {
                headroomCard(SessionHeadroom(budget: budget, sessions: sessions))
            }
            HStack(spacing: 10) {
                StatBox(label: "Phiên agent", value: "\(sessions.count)",
                        subtitle: "Các công cụ dòng lệnh đã nhận diện")
                StatBox(label: "Phiên rảnh", value: "\(sessions.filter(isIdle).count)",
                        color: sessions.contains(where: isIdle) ? .orange : .primary,
                        subtitle: "Ít CPU trên \(Format.number(monitor.thresholds.idleMinutes, digits: 0)) phút")
                StatBox(label: "RAM công cụ AI", value: Format.bytes(items.reduce(0) { $0 + $1.footprint }),
                        subtitle: "Gồm cả tiến trình con")
            }
            let duplicates = MCPBuilder.duplicates(monitor.processes.mcpServers)
            if !duplicates.isEmpty { duplicateMCPCard(duplicates) }
            ForEach(AITool.Kind.allCases, id: \.self) { kind in
                let group = items.filter { $0.kind == kind }
                if !group.isEmpty {
                    SectionTitle(LocalizedStringKey(kind.name))
                    table(group)
                }
            }
            if items.isEmpty {
                Text("Chưa thấy công cụ AI nào đang mở.").foregroundStyle(.secondary)
            }
            HStack {
                Text("“Rảnh” nghĩa là ít dùng CPU từ lúc theo dõi; phiên có thể đang chờ phản hồi. Kết thúc phiên tại Terminal hoặc app nơi bạn mở nó.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                if items.contains(where: { $0.name == "Claude Code" }) {
                    Button("Mở Claude") { monitor.openClaude() }
                }
            }
        }
    }

    /// Opens the agent with the most sessions once, so the page shows which sessions use RAM without an extra click.
    private func autoExpand(_ items: [AITool]) {
        guard !didAutoExpand else { return }
        didAutoExpand = true
        if let top = items.filter({ !$0.sessions.isEmpty }).max(by: { $0.sessions.count < $1.sessions.count }) {
            expanded.insert(top.name)
        }
    }

    private func isIdle(_ p: AgentSession) -> Bool {
        Date().timeIntervalSince(p.lastActive) >= monitor.thresholds.idleMinutes * 60
    }

    /// Header card: a rough estimate of how many more agent sessions fit. Never promises "no swap".
    private func headroomCard(_ c: SessionHeadroom) -> some View {
        let color: Color
        switch c.state {
        case let .room(n): color = n >= 2 ? .green : .orange
        case .tight: color = .orange
        case .short: color = .red
        }
        return HStack(spacing: 14) {
            Group {
                if case let .room(n) = c.state {
                    Text(n > 9 ? "~9+" : "~\(n)")
                        .font(.system(size: 36, weight: .bold, design: .rounded)).monospacedDigit()
                } else {
                    Image(systemName: c.state == .short ? "exclamationmark.triangle.fill" : "gauge.with.dots.needle.100percent")
                        .font(.system(size: 32, weight: .semibold))
                }
            }
            .foregroundStyle(color)
            .frame(minWidth: 60)
            VStack(alignment: .leading, spacing: 3) {
                switch c.state {
                case let .room(n):
                    Text("Ước tính còn chỗ cho khoảng \(n) phiên agent nữa").font(.headline)
                    Text("Mỗi phiên cần khoảng \(Format.bytes(c.perSession)), RAM còn trống theo ước tính khoảng \(Format.bytes(c.availableRAM)).")
                        .font(.callout).foregroundStyle(.secondary)
                case .tight:
                    Text("Gần hết RAM, chưa nên mở thêm phiên").font(.headline)
                    Text("Mỗi phiên mới cần khoảng \(Format.bytes(c.perSession)), nhiều hơn phần RAM còn trống theo ước tính.")
                        .font(.callout).foregroundStyle(.secondary)
                case .short:
                    Text("Máy đang thiếu RAM, chưa nên mở thêm phiên").font(.headline)
                    Text("Các app đang cần hơn RAM máy khoảng \(Format.bytes(c.overflow)). Đóng bớt phiên hoặc app không dùng trước.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Text("Chỉ là ước tính theo RAM các app đang cần, không bảo đảm máy không swap.").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if case .room = c.state {} else {
                Button("Dọn RAM") { monitor.page = .freeRAM }.buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func table(_ items: [AITool]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, c in
                if i > 0 { Divider() }
                toolRow(c)
                if expanded.contains(c.name) {
                    // Heaviest sessions first; long lists show a few rows and a "show all" button.
                    let sorted = c.sessions.sorted { $0.footprint > $1.footprint }
                    let showAll = showAllSessions.contains(c.name) || sorted.count <= Self.sessionPreview + 2
                    ForEach(showAll ? sorted : Array(sorted.prefix(Self.sessionPreview))) { p in
                        Divider().padding(.leading, 44)
                        sessionRow(p)
                    }
                    if sorted.count > Self.sessionPreview + 2 {
                        Divider().padding(.leading, 44)
                        Button(showAll ? String(localized: "Thu gọn", bundle: .main)
                                       : String(localized: "Hiện cả \(sorted.count) phiên", bundle: .main)) {
                            if showAll { showAllSessions.remove(c.name) } else { showAllSessions.insert(c.name) }
                        }
                        .buttonStyle(.link)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 44).padding(.vertical, 7)
                    }
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func toolRow(_ c: AITool) -> some View {
        let hasSessions = !c.sessions.isEmpty
        return Button {
            guard hasSessions else { return }
            if expanded.contains(c.name) { expanded.remove(c.name) } else { expanded.insert(c.name) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: expanded.contains(c.name) ? "chevron.down" : "chevron.right")
                    .font(.callout).foregroundStyle(.secondary).frame(width: 10)
                    .opacity(hasSessions ? 1 : 0)
                if let bundlePath = c.bundlePath {
                    IconApp(path: bundlePath, size: 22)
                } else {
                    Image(systemName: c.name == "Claude Code" ? "sparkles" : "terminal")
                        .frame(width: 22, height: 22)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.name).fontWeight(.medium)
                    if hasSessions {
                        Text("\(c.sessions.count) phiên").font(.callout).foregroundStyle(.secondary)
                    } else if let g = c.note {
                        Text(g).font(.callout).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(Format.bytes(c.footprint)).frame(width: 80, alignment: .trailing)
                Text(Format.number(c.cpu, digits: 0) + Format.percentSign).frame(width: 55, alignment: .trailing).foregroundStyle(.secondary)
                toolStatus(c).frame(width: 130, alignment: .trailing)
            }
            .monospacedDigit()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10).padding(.vertical, 7)
    }

    @ViewBuilder
    private func toolStatus(_ c: AITool) -> some View {
        if c.isFrontmost {
            Text("Đang dùng").foregroundStyle(.green)
        } else if !c.sessions.isEmpty {
            let idleCount = c.sessions.filter(isIdle).count
            if idleCount > 0 { Text("\(idleCount) rảnh").foregroundStyle(.orange) } else { status(c.cpu, c.lastActive) }
        } else {
            status(c.cpu, c.lastActive)
        }
    }

    @ViewBuilder
    private func status(_ cpu: Double, _ last: Date) -> some View {
        if let statusText = monitor.displayStatus(cpu: cpu, lastActive: last) {
            Text(statusText.0).foregroundStyle(statusText.1)
        } else {
            Text("-").foregroundStyle(.tertiary)
        }
    }

    /// Each agent session starts its own copy of every MCP server. Shows the ones running more than once.
    private func duplicateMCPCard(_ items: [MCPDuplicate]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("MCP server chạy nhiều bản", systemImage: "square.stack.3d.up").font(.headline)
            ForEach(items) { d in
                HStack {
                    Text("\(d.name): \(d.count) bản")
                    Spacer()
                    Text(Format.bytes(d.footprint)).monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            Text("Nhiều phiên hoặc app có thể chạy các bản MCP riêng. Nhiều bản không nhất thiết là lỗi. Kiểm tra phiên đã xong hoặc MCP ít dùng để giảm RAM.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func sessionRow(_ p: AgentSession) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(p.projectName ?? String(localized: "Không rõ thư mục", bundle: .main))
                        .lineLimit(1).truncationMode(.middle)
                    // Open for more than a day: usually finished work still holding RAM.
                    if Date().timeIntervalSince(p.startDate) > 24 * 3600 {
                        StatusPill(owner: "lâu ngày", color: .orange)
                    }
                }
                Text("Mở \(Format.duration(Date().timeIntervalSince(p.startDate))) · PID \(String(p.pid))")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                if monitor.processes.memoryWarnings.contains(where: { $0.sessionID == p.id }) {
                    Text(p.tool == "Claude Code" ? "RAM đang phình: gõ /exit rồi mở lại bằng claude -c" : "RAM đang phình: thoát phiên rồi mở lại")
                        .font(.callout).foregroundStyle(.orange)
                }
                let mcp = monitor.processes.mcpServers.filter { $0.origin?.sessionID == p.id }
                if !mcp.isEmpty {
                    Text("\(mcp.count) MCP (\(mcp.map(\.name).joined(separator: ", "))) · \(Format.bytes(mcp.reduce(0) { $0 + $1.footprint }))")
                        .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text(Format.bytes(p.footprint)).frame(width: 80, alignment: .trailing)
            Text(Format.number(p.cpu, digits: 0) + Format.percentSign).frame(width: 55, alignment: .trailing).foregroundStyle(.secondary)
            status(p.cpu, p.lastActive).frame(width: 130, alignment: .trailing)
        }
        .monospacedDigit()
        .font(.callout)
        .padding(.leading, 52).padding(.trailing, 10).padding(.vertical, 5)
        .help(p.directory ?? "")
    }
}
