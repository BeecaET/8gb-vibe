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
        let kept = monitor.keptIDs
        // Kept apps are never suggested or preselected; they get their own section to review and un-keep.
        let suggestions = items.filter { $0.blockedReason == nil && !kept.contains($0.id) && $0.isIdle(afterSeconds: idleAfter) && $0.footprint >= 200 << 20 }
        let suggestionIDs = Set(suggestions.map(\.id))
        // Hide very small items (under 50 MB) to keep the list short, unless they are selected.
        let other = items.filter { !suggestionIDs.contains($0.id) && !kept.contains($0.id) && ($0.footprint >= 50 << 20 || selection.contains($0.id)) }
        let keptItems = items.filter { kept.contains($0.id) }
        let freeableTotal = items.filter { $0.blockedReason == nil && !kept.contains($0.id) }.reduce(UInt64(0)) { $0 + $1.footprint }
        PageContainer {
            VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 24) {
                ZStack {
                    Circle().fill(Palette.accent).opacity(0.15)
                    Image(systemName: "wand.and.stars").font(.system(size: 34, weight: .medium))
                        .foregroundStyle(Palette.accent)
                }
                .frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 4) {
                    // Nothing selected: show the most that could be freed (secondary color) instead of "0 MB".
                    Text(selection.isEmpty ? String(localized: "RAM các mục có thể đóng", bundle: .main) : String(localized: "RAM các mục đã chọn (ước tính)", bundle: .main)).font(.callout).foregroundStyle(.secondary)
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
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    // Cmd-Delete opens the confirmation sheet (never Return, never quits directly).
                    .keyboardShortcut(.delete, modifiers: .command)
                    .help("Giải phóng (⌘⌫). Sẽ hỏi lại trước khi thoát.")
                    .disabled(selection.isEmpty)
                    if let h = monitor.system {
                        Text("Swap \(Format.bytes(h.swap.used)) · RAM \(Format.percent(h.memory.usedRatio))")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            if let h = monitor.system {
                BeforeAfterBar(total: h.memory.total, used: h.memory.used, freed: selectedTotal(items))
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
                        Text("8GB Vibe không tự tắt phiên. Kết thúc phiên tại Terminal hoặc app nơi bạn mở nó.").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Xem các phiên") { monitor.page = .agents }
                }
                .padding(10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }

            SectionTitle("Gợi ý tắt", subtitle: "Ít hoạt động trên \(Format.number(monitor.thresholds.idleMinutes, digits: 0)) phút, từ 200 MB")
            if suggestions.isEmpty {
                Text(Date().timeIntervalSince(monitor.monitoringStart) < idleAfter
                     ? String(localized: "Đang theo dõi. Chỉ gợi ý mục ít hoạt động đủ \(Format.number(monitor.thresholds.idleMinutes, digits: 0)) phút và giữ từ 200 MB.", bundle: .main)
                     : String(localized: "Chưa có mục phù hợp tiêu chí gợi ý. Bạn vẫn có thể xem danh sách dưới.", bundle: .main))
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                table(suggestions)
            }

            SectionTitle("Đang chạy khác")
            table(other)

            if !keptItems.isEmpty {
                SectionTitle("Đang giữ", subtitle: "Không gợi ý đóng, không chọn sẵn")
                VStack(spacing: 0) {
                    ForEach(Array(keptItems.enumerated()), id: \.element.id) { i, u in
                        if i > 0 { Divider().padding(.leading, 50) }
                        HStack(spacing: 12) {
                            Image(systemName: "pin.fill").foregroundStyle(Palette.tint).frame(width: 18)
                            CandidateIcon(u: u, size: 26)
                            Text(u.name)
                            Spacer()
                            Text(Format.bytes(u.footprint)).monospacedDigit().foregroundStyle(.secondary)
                            Button("Bỏ giữ") { monitor.keep(u.id, false) }.controlSize(.small)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                    }
                }
                .card(padding: 4)
            }

            HStack {
                Text("App có giao diện nhận lệnh thoát macOS; tiến trình nền nhận tín hiệu dừng. Hãy lưu việc trước khi xác nhận. Kết quả được ghi vào Nhật ký.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Bỏ chọn") { selection.removeAll() }.disabled(selection.isEmpty)
                Button("Thoát mục đã chọn…") {
                    monitor.pendingConfirmation = items.filter { selection.contains($0.id) && $0.blockedReason == nil }
                }
                // Same action as the primary button at the top: one primary per screen, so this one is standard.
                .disabled(selection.isEmpty)
            }
        }
        .onAppear {
            if let pre = monitor.freeRAMPreselect {
                applyPreselect(pre, items: items)
            } else if !preselected {
                selection = suggestionIDs; preselected = true
            }
        }
        // Opened again from the advice or the popover while this page is showing.
        .onChange(of: monitor.freeRAMPreselect) { pre in if let pre { applyPreselect(pre, items: items) } }
        .onChange(of: monitor.candidates.map(\.id)) { ids in selection.formIntersection(Set(ids)) }
    }

    /// Selects exactly the apps named elsewhere (advice, popover), minus blocked and kept ones.
    private func applyPreselect(_ ids: Set<String>, items: [QuitCandidate]) {
        selection = Set(items.filter { ids.contains($0.id) && $0.blockedReason == nil && !monitor.keptIDs.contains($0.id) }.map(\.id))
        preselected = true
        monitor.freeRAMPreselect = nil
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
                Image(systemName: "lock.fill").font(.callout).foregroundStyle(.tertiary)
                    .frame(width: 18).help(reason).accessibilityLabel("Không thể thoát")
            } else {
                Toggle("", isOn: $selection).labelsHidden().toggleStyle(.checkbox).frame(width: 18)
            }
            CandidateIcon(u: u, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(u.name).fontWeight(.medium)
                Text(u.blockedReason ?? u.note).font(.callout)
                    .foregroundStyle(u.blockedReason == nil ? Color.secondary : Color.orange)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            if u.blockedReason == nil && hovering {
                Button { monitor.keep(u.id, true) } label: { Label("Giữ", systemImage: "pin") }
                    .controlSize(.small)
                    .help("Giữ mục này: không gợi ý đóng, không chọn sẵn. Bỏ giữ ở cuối trang.")
            }
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
        .background(RoundedRectangle(cornerRadius: 8).fill(selection ? Palette.tint.opacity(0.08) : (hovering ? Color.primary.opacity(0.04) : .clear)))
        .contentShape(Rectangle())
        .onTapGesture { if u.blockedReason == nil { selection.toggle() } }
        .onHover { hovering = $0 }
        .contextMenu {
            if u.blockedReason == nil {
                Button("Giữ mục này (không gợi ý đóng)") { monitor.keep(u.id, true) }
            }
        }
        .opacity(u.blockedReason == nil ? 1 : 0.65)
        .animation(.easeOut(duration: 0.15), value: selection)
    }

    @ViewBuilder private var status: some View {
        switch monitor.actionStates[u.id] {
        case .quitting:
            HStack(spacing: 4) { ProgressView().controlSize(.small); Text("Đang thoát").font(.callout) }.foregroundStyle(.secondary)
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
                        .font(.callout).foregroundStyle(.secondary)
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
            Text(stopping ? "Bộ nhớ các mục này đang giữ: khoảng \(Format.bytes(total)) (ước tính). App gửi tín hiệu yêu cầu dừng (SIGTERM); tiến trình có thể chưa dừng."
                      : "Bộ nhớ các app này đang giữ: khoảng \(Format.bytes(total)) (ước tính). App có thể hỏi lưu trước khi đóng.")
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
                                    .font(.callout).foregroundStyle(u.isFrontmost ? Color.orange : Color.secondary)
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
                .buttonStyle(.borderedProminent)
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

    /// DD/MM HH:mm, 24-hour, the same in every language.
    static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "dd/MM HH:mm"
        return f.string(from: d)
    }

    var body: some View {
        Group {
            if items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath").font(.largeTitle).foregroundStyle(.tertiary)
                    Text("Chưa có hành động nào")
                    Text("Kết quả đóng app, dừng tiến trình và thay đổi kết nối MCP được ghi ở đây.").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                Table(items) {
                    TableColumn("Thời điểm") { d in
                        Text(Self.time(d.timestamp)).monospacedDigit()
                    }.width(96)
                    TableColumn("Hành động") { d in Text(LocalizedStringKey(d.action)) }.width(90)
                    TableColumn("Đối tượng") { d in Text(d.target).lineLimit(1) }.width(min: 100, ideal: 100)
                    TableColumn("RAM (ước tính)") { d in Text(Format.bytes(d.freed)).monospacedDigit() }.width(100)
                    TableColumn("Kết quả") { d in
                        // Success outcomes are stored in Vietnamese ("Đã thoát", "Đã dừng"...); anything else is a warning.
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedStringKey(d.outcome))
                                .foregroundStyle(d.outcome.hasPrefix("Đã") || d.outcome == "Xong" || d.outcome == "Nhả chỗ xong, không dừng tiến trình" ? Color.green : Color.secondary)
                            if let m = d.measured {
                                Text("RAM ↓ \(RewardCard.signed(m.ram)) · swap ↓ \(RewardCard.signed(m.swap))")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }.width(min: 80, ideal: 90)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: false))
                Divider()
                HStack {
                    Text("Tệp nhật ký: \((ActionLog.file.path as NSString).abbreviatingWithTildeInPath)")
                        .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
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
    /// false for the menu bar panel: a shown panel counts as visible even if macOS never reports its occlusion state.
    var requireUnoccluded = true
    var changed: (Bool) -> Void

    func makeNSView(context: Context) -> NSView { V(requireUnoccluded: requireUnoccluded, changed: changed) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class V: NSView {
        let changed: (Bool) -> Void
        let requireUnoccluded: Bool
        private var observers: [NSObjectProtocol] = []
        private var current: Bool?
        /// Safety net: notifications alone left the menu bar panel blank on some Macs (Apple silicon and Intel).
        /// A cheap 1-second check of the window flag fixes any missed notice.
        private var poll: Timer?

        init(requireUnoccluded: Bool, changed: @escaping (Bool) -> Void) {
            self.requireUnoccluded = requireUnoccluded
            self.changed = changed
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let w = window else { poll?.invalidate(); poll = nil; report(false); return }
            let nc = NotificationCenter.default
            // Occlusion alone was not enough: under heavy swap, or right after the Dock icon policy changes, the menu bar
            // panel could open without an occlusion notice and stay blank. Key and order changes are watched too, and the
            // state is checked again shortly after each notice, when macOS has settled the window.
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification,
                         NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                         NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                         NSWindow.didExposeNotification, NSWindow.didChangeScreenNotification] {
                observers.append(nc.addObserver(forName: name, object: w, queue: .main) { [weak self, weak w] n in
                    guard let self, let w else { return }
                    if n.name == NSWindow.willCloseNotification { self.report(false); return }
                    self.check(w)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self, weak w] in
                        guard let self, let w else { return }
                        self.check(w)
                    }
                })
            }
            check(w)
            poll?.invalidate()
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                guard let self, let w = self.window else { return }
                self.check(w)
            }
            t.tolerance = 0.5
            RunLoop.main.add(t, forMode: .common)
            poll = t
        }

        /// Visible: shown and not fully covered. A key window is always treated as visible (it is in front of the user).
        private func check(_ w: NSWindow) {
            if !requireUnoccluded { report(w.isVisible); return }
            report(w.isVisible && (w.isKeyWindow || w.occlusionState.contains(.visible)))
        }

        private func report(_ v: Bool) {
            guard v != current else { return }
            current = v
            changed(v)
        }

        deinit {
            poll?.invalidate()
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }
}

/// RAM now and after quitting the selection: kept (gray), freed (lime), already free (faint).
/// Shows the result before the user commits to anything.
struct BeforeAfterBar: View {
    var total: UInt64
    var used: UInt64
    var freed: UInt64

    var body: some View {
        let t = Double(max(total, used, 1))
        let f = min(Double(freed), Double(used))
        let kept = Double(used) - f
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                HStack(spacing: 2) {
                    Capsule().fill(Color.primary.opacity(0.35)).frame(width: max(0, w * kept / t - 2))
                    if f > 0 {
                        // A range, not a sure mark: memory shared with other apps may not come back.
                        Capsule().fill(LinearGradient(colors: [Palette.headroom, Palette.headroom.opacity(0.25)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(4, w * f / t - 2))
                    }
                    Capsule().fill(Color.primary.opacity(0.08))
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: freed)
            }
            .frame(height: 12)
            Text(freed == 0
                 ? String(localized: "RAM đang dùng \(Format.bytes(used)) trên \(Format.bytes(total, digits: 0)). Chọn app để xem kết quả trước khi đóng.", bundle: .main)
                 : String(localized: "Sau khi đóng: có thể trống thêm tới khoảng \(Format.bytes(freed)) (ước tính). Phần dùng chung với app khác có thể không trả lại.", bundle: .main))
                .font(.callout).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
