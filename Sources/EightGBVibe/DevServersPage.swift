import AppKit
import SwiftUI
import VibeCore

/// Dev servers, open ports and orphaned processes (the agent or Terminal has closed but the server still runs).
struct DevServersPage: View {
    @EnvironmentObject var monitor: Monitor

    var body: some View {
        let items = monitor.processes.devServers
        let orphaned = items.filter(\.orphaned)
        let portCount = items.reduce(0) { $0 + $1.ports.count }
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                StatBox(label: "Đang chạy", value: "\(items.count)", subtitle: "\(portCount) cổng đang mở")
                StatBox(label: "Mồ côi", value: "\(orphaned.count)", color: orphaned.isEmpty ? .primary : .orange,
                        subtitle: orphaned.isEmpty ? "Không có" : "\(Format.bytes(orphaned.reduce(0) { $0 + $1.footprint }))")
                StatBox(label: "RAM", value: Format.bytes(items.reduce(0) { $0 + $1.footprint }), subtitle: "Gồm cả tiến trình con")
            }
            if items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "server.rack").font(.largeTitle).foregroundStyle(.tertiary)
                    Text("Chưa phát hiện dev server nào")
                    Text("Server chạy bằng npm, Vite, Next.js, Python... sẽ hiện ở đây kèm cổng.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                table(items)
            }
            HStack(alignment: .top) {
                Text("Bấm cổng để mở localhost trong trình duyệt. “Mồ côi”: không còn thấy tiến trình cha đã khởi chạy server; server có thể vẫn cần dùng. “mạng”: có thể nhận kết nối từ máy khác, tuỳ tường lửa.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                if !orphaned.isEmpty {
                    Button("Dừng \(orphaned.count) mồ côi…") { monitor.pendingConfirmation = CandidateBuilder.orphanCandidates(monitor.processes) }
                }
            }
        }
        .padding(20)
    }

    private func table(_ items: [DevServer]) -> some View {
        Table(items) {
            TableColumn("Dự án") { d in
                VStack(alignment: .leading) {
                    Text(d.projectName ?? String(localized: "Không rõ dự án", bundle: .main))
                    Text(d.command).font(.callout.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            // Explicit widths so every column fits the smallest window (720 pt) instead of scrolling sideways.
            .width(min: 90, ideal: 100)
            TableColumn("Loại") { d in Text(d.serverKind).lineLimit(1) }.width(min: 44, ideal: 48)
            TableColumn("Cổng") { d in portsColumn(d) }.width(min: 64, ideal: 72)
            TableColumn("Chạy từ") { d in
                Text(d.ownerDescription).foregroundStyle(d.orphaned ? Color.orange : Color.primary).lineLimit(1)
                    .help(d.origin?.orphanNote(now: Date()) ?? d.ownerDescription)
            }.width(min: 72, ideal: 80)
            TableColumn("RAM") { d in Text(Format.bytes(d.footprint)).monospacedDigit() }.width(64)
            TableColumn("Trạng thái") { d in
                if let statusText = monitor.displayStatus(cpu: d.cpu, lastActive: d.lastActive) {
                    Text(statusText.0).foregroundStyle(statusText.1)
                } else {
                    Text("-").foregroundStyle(.tertiary)
                }
            }.width(min: 40, ideal: 40)
            // Stop straight from the row; it still goes through the confirmation sheet like the context menu.
            TableColumn("") { d in
                Button("Dừng…") { monitor.pendingConfirmation = [CandidateBuilder.from(d)] }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .help("Dừng \(d.serverKind). Sẽ hỏi lại trước khi dừng.")
            }.width(min: 70, ideal: 70)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .contextMenu(forSelectionType: DevServer.ID.self) { ids in
            let selection = items.filter { ids.contains($0.id) }
            if selection.count == 1, let d = selection.first {
                ForEach(d.ports, id: \.number) { c in
                    Button("Mở localhost:\(String(c.number)) trong trình duyệt") { openInBrowser(c.number) }
                }
                if let m = d.directory, m != "/" {
                    Button("Hiện thư mục trong Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: m)])
                    }
                }
                Divider()
                // Every orphan left by the same agent session, stopped together.
                if let o = d.origin, d.orphaned {
                    let siblings = items.filter { $0.orphaned && $0.origin?.sessionID == o.sessionID }
                    if siblings.count > 1 {
                        Button("Dừng \(siblings.count) mồ côi của \(o.sessionDescription)…") {
                            monitor.pendingConfirmation = [CandidateBuilder.fromOrphans(siblings)]
                        }
                    }
                }
            }
            Button(selection.count == 1 ? "Dừng \(selection[0].serverKind)…" : "Dừng \(selection.count) mục…") {
                monitor.pendingConfirmation = selection.map { CandidateBuilder.from($0) }
            }
            .disabled(selection.isEmpty)
        }
    }

    private func portsColumn(_ d: DevServer) -> some View {
        HStack(spacing: 4) {
            if d.ports.isEmpty {
                Text("-").foregroundStyle(.tertiary)
            } else {
                // Each port is a small button that opens localhost in the browser (never a URL taken from the process).
                ForEach(d.ports.prefix(2), id: \.number) { c in
                    Button { openInBrowser(c.number) } label: {
                        HStack(spacing: 2) {
                            Text(verbatim: ":\(String(c.number))").monospacedDigit()
                            Image(systemName: "arrow.up.right").font(.callout.weight(.semibold))
                        }
                        .font(.callout)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Palette.tint.opacity(0.12), in: Capsule())
                        .foregroundStyle(Palette.tint)
                    }
                    .buttonStyle(.plain)
                    .help("Mở http://localhost:\(String(c.number)) trong trình duyệt")
                    .accessibilityLabel("Mở cổng \(String(c.number)) trong trình duyệt")
                }
                if d.ports.count > 2 { Text(verbatim: "+\(d.ports.count - 2)").font(.callout).foregroundStyle(.secondary) }
                if d.exposedToNetwork {
                    Text("mạng").font(.callout.weight(.medium)).foregroundStyle(.orange)
                        .help("Lắng nghe trên địa chỉ ngoài localhost. Khả năng truy cập từ máy khác còn tuỳ mạng và tường lửa.")
                }
            }
        }
    }

    /// Only opens localhost with the port number that was read, never a string taken from the process.
    private func openInBrowser(_ number: UInt16) {
        if let url = URL(string: "http://localhost:\(String(number))") { NSWorkspace.shared.open(url) }
    }
}
