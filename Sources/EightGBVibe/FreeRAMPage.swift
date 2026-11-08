import AppKit
import SwiftUI
import VibeCore

/// Free RAM page: pick apps, Simulator, daemons to quit. Always goes through a confirmation dialog.
struct FreeRAMPage: View {
    @EnvironmentObject var monitor: Monitor
    @State private var selection: Set<String> = []
    @State private var preselected = false

    var body: some View {
        let idleAfter = monitor.thresholds.idleMinutes * 60
        let items = monitor.candidates
        let suggestions = items.filter { $0.blockedReason == nil && $0.isIdle(afterSeconds: idleAfter) && $0.footprint >= 200 << 20 }
        let suggestionIDs = Set(suggestions.map(\.id))
        // Hide very small items (under 50 MB) to keep the list short, unless they are selected.
        let other = items.filter { !suggestionIDs.contains($0.id) && ($0.footprint >= 50 << 20 || selection.contains($0.id)) }
        let freeableTotal = items.filter { $0.blockedReason == nil }.reduce(UInt64(0)) { $0 + $1.footprint }
        PageContainer {
            HStack(spacing: 24) {
                ZStack {
                    Circle().fill(Palette.accent).opacity(0.15)
                    Image(systemName: "wand.and.stars").font(.system(size: 34, weight: .medium))
                        .foregroundStyle(Palette.accent)
                }
                .frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 4) {
                    // Nothing selected: show the most that could be freed (secondary color) instead of "0 MB".
                    Text(selection.isEmpty ? String(localized: "Có thể giải phóng tới", bundle: .main) : String(localized: "Giải phóng được", bundle: .main)).font(.callout).foregroundStyle(.secondary)
                    Text(Format.bytes(selection.isEmpty ? freeableTotal : selectedTotal(items)))
                        .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(selection.isEmpty ? Color.secondary : Color.primary)
                        .motionCount()
                        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: selection)
                    Text(selection.isEmpty ? String(localized: "Chọn app muốn thoát ở danh sách dưới.", bundle: .main) : String(localized: "Đã chọn \(selection.count) mục", bundle: .main))
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Button {
                        monitor.pendingConfirmation = items.filter { selection.contains($0.id) && $0.blockedReason == nil }
                    } label: {
                        Label("Giải phóng", systemImage: "bolt.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle(large: true))
                    .disabled(selection.isEmpty)
                    if let h = monitor.system {
                        Text("Swap \(Format.bytes(h.swap.used)) · RAM \(Format.percent(h.memory.usedRatio))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.primary.opacity(0.07), lineWidth: 1))

            if (monitor.levels[.slowMac] ?? .ok) != .ok { SlowMacPanel() }

            if !monitor.processes.sessions.isEmpty {
                let ram = monitor.processes.sessions.reduce(UInt64(0)) { $0 + $1.footprint }
                HStack(spacing: 10) {
                    GroupIcon(group: .claude)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(monitor.processes.sessions.count) phiên Claude Code · \(Format.bytes(ram))")
                        Text("App không tắt phiên. Lưu trữ phiên đã xong trong app Claude.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Mở Claude") { monitor.openClaude() }
                }
                .padding(10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }

            SectionTitle("Gợi ý tắt", subtitle: "Rảnh trên \(Format.number(monitor.thresholds.idleMinutes, digits: 0)) phút, từ 200 MB")
            if suggestions.isEmpty {
                Text(Date().timeIntervalSince(monitor.monitoringStart) < idleAfter
                     ? String(localized: "Đang theo dõi. Gợi ý xuất hiện sau \(Format.number(monitor.thresholds.idleMinutes, digits: 0)) phút kể từ khi mở app.", bundle: .main)
                     : String(localized: "Không có app nào rảnh lâu. Bạn vẫn có thể chọn ở danh sách dưới.", bundle: .main))
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                table(suggestions)
            }

            SectionTitle("Đang chạy khác")
            table(other)

            HStack {
                Text("App gửi lệnh thoát chuẩn: app tự lưu rồi đóng. Mọi lần tắt đều ghi vào Nhật ký.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Bỏ chọn") { selection.removeAll() }.disabled(selection.isEmpty)
                Button("Thoát mục đã chọn…") {
                    monitor.pendingConfirmation = items.filter { selection.contains($0.id) && $0.blockedReason == nil }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selection.isEmpty)
            }
        }
        .onAppear {
            if !preselected { selection = suggestionIDs; preselected = true }
        }
        .onChange(of: monitor.candidates.map(\.id)) { ids in selection.formIntersection(Set(ids)) }
    }

    private func selectedTotal(_ items: [QuitCandidate]) -> UInt64 {
        items.filter { selection.contains($0.id) }.reduce(0) { $0 + $1.footprint }
    }

    private func table(_ items: [QuitCandidate]) -> some View {
        let largest = monitor.candidates.first?.footprint ?? 1
        return VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, u in
                if i > 0 { Divider().padding(.leading, 74) }
                CandidateRow(u: u, largest: largest, selection: Binding(
                    get: { selection.contains(u.id) },
                    set: { if $0 { selection.insert(u.id) } else { selection.remove(u.id) } }))
            }
        }
        .card(padding: 4)
    }
}

struct CandidateRow: View {
    @EnvironmentObject var monitor: Monitor
    var u: QuitCandidate
    var largest: UInt64
    @Binding var selection: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            // Items that may not be quit: show a lock instead of a dimmed checkbox.
            if let reason = u.blockedReason {
                Image(systemName: "lock.fill").font(.caption).foregroundStyle(.tertiary)
                    .frame(width: 18).help(reason).accessibilityLabel("Không thể thoát")
            } else {
                Toggle("", isOn: $selection).labelsHidden().toggleStyle(.checkbox).frame(width: 18)
            }
            CandidateIcon(u: u, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(u.name).fontWeight(.medium)
                Text(u.blockedReason ?? u.note).font(.caption)
                    .foregroundStyle(u.blockedReason == nil ? Color.secondary : Color.orange)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            status
            VStack(alignment: .trailing, spacing: 4) {
                Text(Format.bytes(u.footprint)).monospacedDigit().fontWeight(.medium)
                GeometryReader { geo in
                    ZStack(alignment: .trailing) {
                        Capsule().fill(Color.primary.opacity(0.07))
                        Capsule().fill(u.group.color.gradient)
                            .frame(width: max(3, geo.size.width * Double(u.footprint) / Double(max(1, largest))))
                    }
                }
                .frame(width: 70, height: 4)
            }
            .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 8).fill(selection ? Color.accentColor.opacity(0.08) : (hovering ? Color.primary.opacity(0.04) : .clear)))
        .contentShape(Rectangle())
        .onTapGesture { if u.blockedReason == nil { selection.toggle() } }
        .onHover { hovering = $0 }
        .opacity(u.blockedReason == nil ? 1 : 0.65)
        .animation(.easeOut(duration: 0.15), value: selection)
    }

    @ViewBuilder private var status: some View {
        switch monitor.actionStates[u.id] {
        case .quitting:
            HStack(spacing: 4) { ProgressView().controlSize(.small); Text("Đang thoát").font(.caption) }.foregroundStyle(.secondary)
        case .quit:
            StatusPill(owner: "Đã thoát", color: .green)
        case .notQuit:
            Button("Buộc thoát…") { monitor.pendingForceQuit = u }.controlSize(.small)
        case nil:
            if u.isFrontmost {
                StatusPill(owner: "Đang dùng", color: .blue)
            } else {
                if let statusText = monitor.displayStatus(cpu: u.cpu, lastActive: u.lastActive) {
                    StatusPill(owner: LocalizedStringKey(statusText.0), color: statusText.1)
                }
            }
        }
    }
}

/// Red warning strip when the Mac is slow.
struct SlowMacPanel: View {
    @EnvironmentObject var monitor: Monitor
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 1) {
                Text("Máy đang chậm").fontWeight(.medium)
                if let h = monitor.system {
                    Text("Swap \(Format.bytes(h.swap.used)), tải \(Format.number(h.load.m5, digits: 0)) trên \(h.coreCount) nhân. Tắt bớt app rảnh để máy nhẹ lại.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Confirmation dialog before quitting. Esc cancels. No Return key binding.
struct QuitConfirmation: View {
    @EnvironmentObject var monitor: Monitor
    @State var items: [QuitCandidate]
    @State private var selection: Set<String>

    init(items: [QuitCandidate]) {
        _items = State(initialValue: items)
        // Blocked items (system, Claude app...) are not preselected and cannot be selected.
        _selection = State(initialValue: Set(items.filter { $0.blockedReason == nil }.map(\.id)))
    }

    var body: some View {
        let total = items.filter { selection.contains($0.id) }.reduce(UInt64(0)) { $0 + $1.footprint }
        // Only processes (dev servers, orphans): say "Stop" instead of "Quit".
        let stopping = items.allSatisfy(\.isProcess)
        VStack(alignment: .leading, spacing: 12) {
            Text(stopping ? "Dừng \(selection.count) mục?" : "Thoát \(selection.count) mục?").font(.headline)
            Text(stopping ? "Giải phóng khoảng \(Format.bytes(total)) RAM. Tiến trình nhận tín hiệu dừng nhẹ và tự đóng."
                      : "Giải phóng khoảng \(Format.bytes(total)) RAM. App sẽ tự lưu trước khi đóng.")
                .font(.callout).foregroundStyle(.secondary)
            VStack(spacing: 8) {
                ForEach(items) { u in
                    Toggle(isOn: Binding(get: { selection.contains(u.id) },
                                         set: { if $0 { selection.insert(u.id) } else { selection.remove(u.id) } })) {
                        HStack(spacing: 10) {
                            CandidateIcon(u: u, size: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(u.name)
                                Text(u.isFrontmost ? String(localized: "Đang dùng. Hãy lưu việc đang làm.", bundle: .main) : u.note)
                                    .font(.caption).foregroundStyle(u.isFrontmost ? Color.orange : Color.secondary)
                            }
                            Spacer()
                            Text(Format.bytes(u.footprint)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .disabled(u.blockedReason != nil)
                    .help(u.blockedReason ?? "")
                }
            }
            HStack {
                Spacer()
                Button("Huỷ") { monitor.pendingConfirmation = nil }.keyboardShortcut(.cancelAction)
                Button(stopping ? "Dừng mục đã chọn" : "Thoát mục đã chọn") {
                    let confirmed = items.filter { selection.contains($0.id) && $0.blockedReason == nil }
                    monitor.pendingConfirmation = nil
                    monitor.quitAll(confirmed)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selection.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

// MARK: Log

struct LogPage: View {
    @State private var items: [LogEntry] = []

    var body: some View {
        Group {
            if items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath").font(.largeTitle).foregroundStyle(.tertiary)
                    Text("Chưa có hành động nào")
                    Text("Mỗi lần thoát app từ trang Dọn RAM sẽ được ghi ở đây.").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                Table(items) {
                    TableColumn("Thời điểm") { d in
                        Text(d.timestamp.formatted(.dateTime.day().month().hour().minute())).monospacedDigit()
                    }.width(110)
                    TableColumn("Hành động") { d in Text(LocalizedStringKey(d.action)) }.width(90)
                    TableColumn("Đối tượng") { d in Text(d.target) }
                    TableColumn("RAM") { d in Text(Format.bytes(d.freed)).monospacedDigit() }.width(70)
                    TableColumn("Kết quả") { d in
                        // Success outcomes are stored in Vietnamese ("Đã thoát", "Đã dừng"...); anything else is a warning.
                        Text(LocalizedStringKey(d.outcome)).foregroundStyle(d.outcome.hasPrefix("Đã") ? Color.green : Color.orange)
                    }.width(110)
                }
                Divider()
                HStack {
                    Text("Tệp nhật ký: \((ActionLog.file.path as NSString).abbreviatingWithTildeInPath)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer()
                    Button("Hiện trong Finder") { NSWorkspace.shared.activateFileViewerSelecting([ActionLog.file]) }
                        .controlSize(.small)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                }
            }
        }
        .toolbar {
            Button { NSWorkspace.shared.activateFileViewerSelecting([ActionLog.file]) } label: {
                Label("Hiện tệp nhật ký", systemImage: "doc.text.magnifyingglass")
            }
        }
        .onAppear { items = ActionLog.read() }
    }
}

/// Tells SwiftUI whether the window holding this view is visible or hidden (closed, minimized, fully covered).
struct VisibilityTracker: NSViewRepresentable {
    var changed: (Bool) -> Void

    func makeNSView(context: Context) -> NSView { V(changed: changed) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class V: NSView {
        let changed: (Bool) -> Void
        private var observers: [NSObjectProtocol] = []
        private var current: Bool?

        init(changed: @escaping (Bool) -> Void) {
            self.changed = changed
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let w = window else { report(false); return }
            let nc = NotificationCenter.default
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification,
                        NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
                observers.append(nc.addObserver(forName: name, object: w, queue: .main) { [weak self, weak w] n in
                    guard let w else { return }
                    self?.report(n.name != NSWindow.willCloseNotification && w.isVisible && w.occlusionState.contains(.visible))
                })
            }
            report(w.isVisible && w.occlusionState.contains(.visible))
        }

        private func report(_ v: Bool) {
            guard v != current else { return }
            current = v
            changed(v)
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}
