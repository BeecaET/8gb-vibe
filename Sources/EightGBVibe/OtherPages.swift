import AppKit
import ServiceManagement
import SwiftUI
import VibeCore

// MARK: Processes

struct ProcessesPage: View {
    @EnvironmentObject var monitor: Monitor
    @State private var searchText = ""
    @State private var sortOrder = [KeyPathComparator(\ProcessRow.ramSort, order: .reverse)]
    @State private var selection: Set<ProcessRow.ID> = []

    var body: some View {
        let items = monitor.processes.processes
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.kind.group.name.localizedCaseInsensitiveContains(searchText) || "\($0.pid)" == searchText }
            .sorted(using: sortOrder)
            .prefix(400)
        VStack(spacing: 0) {
        Table(Array(items), selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Tên", value: \.name) { t in
                HStack(spacing: 6) {
                    GroupIcon(group: t.kind.group, size: 16)
                    Text(t.name).lineLimit(1)
                }
            }
            TableColumn("Nhóm", value: \.groupName) { t in Text(t.groupName).foregroundStyle(.secondary).lineLimit(1) }
            TableColumn("RAM", value: \.ramSort) { t in
                Text(t.footprint.map { Format.bytes($0) } ?? "-").monospacedDigit()
            }.width(75)
            TableColumn("CPU", value: \.cpu) { t in Text(Format.number(t.cpu, digits: 1) + Format.percentSign).monospacedDigit() }.width(60)
            TableColumn("PID", value: \.pidSort) { t in Text(verbatim: "\(t.pid)").monospacedDigit().foregroundStyle(.secondary) }.width(60)
        }
        .contextMenu(forSelectionType: ProcessRow.ID.self) { ids in
            let selection = monitor.processes.processes.filter { ids.contains($0.id) && ProcessIdentity(pid: $0.pid, startDate: $0.startDate).canStop() }
            Button(selection.count == 1 ? String(localized: "Thoát \(selection[0].name)…", bundle: .main)
                                   : String(localized: "Thoát \(selection.count) tiến trình…", bundle: .main)) {
                monitor.pendingConfirmation = selection.map { monitor.candidates(from: $0) }
            }
            .disabled(selection.isEmpty)
            // A blocked process was picked: say why.
            if selection.isEmpty, ids.count == 1, let t = monitor.processes.processes.first(where: { ids.contains($0.id) }),
               let reason = ProcessGuard.reason(t) {
                Text(reason)
            }
        }
            Divider()
            footer
        }
        .searchable(text: $searchText, prompt: "Tên, nhóm hoặc PID")
    }

    /// Bottom bar: what is selected, why it cannot be quit, and the quit button. Quitting still goes through the
    /// same checks (ProcessIdentity, ProcessGuard) and the confirmation sheet as the context menu.
    private var footer: some View {
        let picked = monitor.processes.processes.filter { selection.contains($0.id) }
        let stoppable = picked.filter { ProcessIdentity(pid: $0.pid, startDate: $0.startDate).canStop() }
        let ram = stoppable.reduce(UInt64(0)) { $0 + ($1.footprint ?? 0) }
        return HStack(spacing: 12) {
            if picked.isEmpty {
                Text("Chọn dòng (giữ Cmd để chọn nhiều) hoặc chuột phải để thoát tiến trình của bạn.")
                    .foregroundStyle(.secondary)
            } else if stoppable.isEmpty {
                Label(picked.count == 1 ? (ProcessGuard.reason(picked[0]) ?? String(localized: "Không thể thoát", bundle: .main))
                                        : String(localized: "Không có tiến trình nào thoát được trong mục đã chọn.", bundle: .main),
                      systemImage: "lock.fill")
                    .foregroundStyle(.orange)
            } else {
                Text("Đã chọn \(stoppable.count) tiến trình · \(Format.bytes(ram))").foregroundStyle(.secondary).monospacedDigit()
                if stoppable.count < picked.count {
                    Text("\(picked.count - stoppable.count) mục bị bỏ qua").foregroundStyle(.orange)
                }
            }
            Spacer()
            Button(stoppable.isEmpty ? String(localized: "Thoát…", bundle: .main)
                   : stoppable.count == 1 ? String(localized: "Thoát \(stoppable[0].name)…", bundle: .main)
                   : String(localized: "Thoát \(stoppable.count) tiến trình…", bundle: .main)) {
                monitor.pendingConfirmation = stoppable.map { monitor.candidates(from: $0) }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(stoppable.isEmpty)
        }
        .font(.callout)
        .lineLimit(1)
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

extension ProcessRow {
    var ramSort: UInt64 { footprint ?? 0 }
    var pidSort: Int { Int(pid) }
    var groupName: String { kind.group == .other || kind.item == ItemName.system ? kind.group.name : "\(kind.group.name) · \(kind.item)" }
}

// MARK: Disk

struct DiskPage: View {
    @EnvironmentObject var monitor: Monitor

    var body: some View {
        PageContainer {
            if let h = monitor.system {
                // The bar shows the used part: accent color when fine, orange or red when nearly full (no green, so it does not read as "good").
                let diskLevel = monitor.levels[.disk] ?? .ok
                VStack(alignment: .leading, spacing: 6) {
                    SectionTitle("Macintosh HD", subtitle: "Trống \(Format.bytes(h.disk.free, digits: 0)) / \(Format.bytes(h.disk.total, digits: 0))")
                    ProgressView(value: h.disk.fullRatio).tint(diskLevel == .ok ? Color.accentColor : diskLevel.color)
                    Text("Đã dùng \(Format.percent(h.disk.fullRatio))").font(.caption).foregroundStyle(.secondary)
                }
                .card()
            }
            HStack {
                Text(monitor.scanningDisk ? String(localized: "Đang quét…", bundle: .main)
                     : monitor.lastDiskScan.map { String(localized: "Quét lúc \($0.formatted(date: .omitted, time: .shortened))", bundle: .main) } ?? String(localized: "Chưa quét", bundle: .main))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if monitor.scanningDisk { ProgressView().controlSize(.small) }
                Button(monitor.lastDiskScan == nil ? String(localized: "Quét", bundle: .main) : String(localized: "Quét lại", bundle: .main)) { monitor.scanDisk() }.disabled(monitor.scanningDisk)
            }
            group(.safe, "Cache an toàn", "Tạo lại được tự động. Bản sau sẽ có nút dọn.")
            group(.review, "Cần xem kỹ", "Có thể chứa dữ liệu còn dùng. Bạn tự quyết.")
            group(.inApp, "Dữ liệu của app khác", "Dọn trong chính app đó.")
            Text("App chỉ đo dung lượng. Không xoá gì.").font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { if monitor.lastDiskScan == nil { monitor.scanDisk() } }
    }

    private func group(_ kind: DiskItem.Kind, _ name: LocalizedStringKey, _ summary: LocalizedStringKey) -> some View {
        let items = monitor.disk.filter { $0.kind == kind }.sorted { ($0.bytes ?? 0) > ($1.bytes ?? 0) }
        let total = items.reduce(UInt64(0)) { $0 + ($1.bytes ?? 0) }
        return VStack(alignment: .leading, spacing: 0) {
            SectionTitle(name, subtitle: total > 0 ? "Tổng \(Format.bytes(total))" : nil).padding(.bottom, 2)
            Text(summary).font(.caption).foregroundStyle(.secondary).padding(.bottom, 8)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, m in
                    if i > 0 { Divider() }
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.name)
                            Text(m.note).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(m.bytes.map { Format.bytes($0) } ?? (monitor.scanningDisk ? String(localized: "…", bundle: .main) : String(localized: "Không có", bundle: .main)))
                            .monospacedDigit().foregroundStyle((m.bytes ?? 0) < 1 << 20 ? .tertiary : .primary)
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: m.path)])
                        } label: { Image(systemName: "magnifyingglass") }
                            .buttonStyle(.borderless)
                            .help("Hiện trong Finder")
                            .accessibilityLabel("Hiện \(m.name) trong Finder")
                            .disabled(m.bytes == nil)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                }
            }
            .card(padding: 0)
        }
    }
}

// MARK: Background items

struct BackgroundPage: View {
    @EnvironmentObject var monitor: Monitor

    var body: some View {
        PageContainer {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text("Dịch vụ tự chạy khi khởi động máy. App chỉ xem, không tắt. Muốn tắt: Cài đặt hệ thống, Cài đặt chung, Mục đăng nhập.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Mở Mục đăng nhập") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .card(padding: 12)
            ForEach([BackgroundItem.Scope.currentUser, .allUsers, .system], id: \.self) { scopeValue in
                let items = monitor.backgroundItems.filter { $0.scope == scopeValue }
                if !items.isEmpty {
                    SectionTitle(LocalizedStringKey(scopeValue.rawValue), subtitle: "\(items.count) mục")
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, m in
                            if i > 0 { Divider().padding(.leading, 52) }
                            BackgroundItemRow(m: m)
                        }
                    }
                    .card(padding: 0)
                }
            }
        }
        .onAppear { monitor.readBackgroundItems() }
    }
}

/// One background item row: app icon (if it belongs to an .app), readable name, original label, shortened path.
struct BackgroundItemRow: View {
    var m: BackgroundItem

    /// Path of the .app bundle containing the program, if any.
    private var appBundle: String? {
        guard let r = m.program.range(of: ".app/") else { return nil }
        return String(m.program[..<r.lowerBound]) + ".app"
    }

    private var name: String {
        if let g = appBundle { return ((g as NSString).lastPathComponent as NSString).deletingPathExtension }
        return Self.displayName(m.label)
    }

    /// "com.google.keystone.agent" becomes "Google Keystone Agent". Drops the domain prefix and repeated parts.
    static func displayName(_ label: String) -> String {
        var parts = label.split(separator: ".").map(String.init)
        guard parts.count > 1 else { return label }
        if ["com", "org", "net", "io", "vn", "de", "co"].contains(parts[0].lowercased()) { parts.removeFirst() }
        let compact = parts.enumerated().filter { i, p in
            !parts[(i + 1)...].contains { $0.lowercased().contains(p.lowercased()) }
        }.map { _, p in p.prefix(1).uppercased() + p.dropFirst() }
        return compact.isEmpty ? label : compact.joined(separator: " ")
    }

    var body: some View {
        HStack(spacing: 12) {
            if let g = appBundle {
                IconApp(path: g, size: 28)
            } else {
                Image(systemName: "gearshape.2").font(.system(size: 14)).foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name).lineLimit(1)
                let subtitle = name == m.label ? m.program : m.label
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                        .help(m.program)
                }
            }
            Spacer(minLength: 8)
            if m.runAtLoad { StatusPill(owner: "Khi khởi động", color: .secondary) }
            if m.keepAlive { StatusPill(owner: "Luôn chạy", color: .orange) }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Settings

struct SettingsPage: View {
    @EnvironmentObject var monitor: Monitor
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?
    @State private var language = AppLanguage.current
    private let launchLanguage = AppLanguage.current

    var body: some View {
        Form {
            Section {
                Picker("Ngôn ngữ", selection: $language) {
                    ForEach(AppLanguage.allCases) { n in n.label.tag(n) }
                }
                .onChange(of: language) { $0.save() }
                if language != launchLanguage {
                    HStack {
                        Text("Mở lại app để đổi ngôn ngữ.").foregroundStyle(.secondary)
                        Spacer()
                        Button("Mở lại") { AppLanguage.relaunch() }
                    }
                }
            }
            Section("Thanh menu") {
                Picker("Hiển thị", selection: $monitor.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { Text($0.name).tag($0) }
                }
                Toggle("Mở cùng máy", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in toggleLaunchAtLogin(enabled) }
                if let launchAtLoginError { Text(launchAtLoginError).font(.caption).foregroundStyle(.red) }
            }
            Section("Thông báo") {
                Toggle("Báo khi vượt ngưỡng", isOn: $monitor.sendNotifications)
                Text("Mỗi chỉ số báo tối đa 30 phút một lần, chỉ khi mức độ tăng.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Ngưỡng swap") {
                row(.yellow, "Mức vàng", "\(Format.number(monitor.thresholds.swapYellowGB, digits: 0)) GB", $monitor.thresholds.swapYellowGB, 1...20, step: 1)
                row(.red, "Mức đỏ", "\(Format.number(monitor.thresholds.swapRedGB, digits: 0)) GB", $monitor.thresholds.swapRedGB, 1...30, step: 1)
            }
            Section("Ngưỡng ổ trống") {
                row(.yellow, "Vàng khi còn dưới", "\(Format.number(monitor.thresholds.diskFreeYellowGB, digits: 0)) GB", $monitor.thresholds.diskFreeYellowGB, 5...200, step: 5)
                row(.red, "Đỏ khi còn dưới", "\(Format.number(monitor.thresholds.diskFreeRedGB, digits: 0)) GB", $monitor.thresholds.diskFreeRedGB, 5...100, step: 5)
            }
            Section {
                row(.yellow, "Mức vàng", Format.number(monitor.thresholds.load5Yellow, digits: 0), $monitor.thresholds.load5Yellow, 4...100, step: 2)
                row(.red, "Mức đỏ", Format.number(monitor.thresholds.load5Red, digits: 0), $monitor.thresholds.load5Red, 4...200, step: 2)
            } header: {
                Text("Ngưỡng tải CPU")
            } footer: {
                Text("Tải trung bình 5 phút. Máy có \(monitor.system?.coreCount ?? 8) nhân, tải bằng số nhân là đầy.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Phiên Claude Code") {
                row(.yellow, "Vàng khi trên", String(localized: "\(monitor.thresholds.sessionsYellow) phiên", bundle: .main), $monitor.thresholds.sessionsYellow, 1...50, step: 1)
                row(.red, "Đỏ khi trên", String(localized: "\(monitor.thresholds.sessionsRed) phiên", bundle: .main), $monitor.thresholds.sessionsRed, 1...80, step: 1)
                row(nil, "Coi là rảnh sau", String(localized: "\(Format.number(monitor.thresholds.idleMinutes, digits: 0)) phút", bundle: .main), $monitor.thresholds.idleMinutes, 5...240, step: 5)
            }
            Section {
                Button("Khôi phục mặc định") { monitor.thresholds = Thresholds() }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        // Limit the width like System Settings so rows do not stretch on a large window.
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
    }

    /// One threshold row: level dot, name, value with unit, stepper.
    private func row<V: Strideable>(_ color: Color?, _ name: LocalizedStringKey, _ value: String,
                                     _ b: Binding<V>, _ range: ClosedRange<V>, step: V.Stride) -> some View {
        Stepper(value: b, in: range, step: step) {
            HStack(spacing: 8) {
                if let color { Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true) }
                Text(name)
                Spacer()
                Text(value).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .accessibilityValue(value)
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = String(localized: "Không đổi được: \(error.localizedDescription)", bundle: .main)
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// App language. Stored as AppleLanguages in the app's saved defaults (system settings are untouched). Needs a relaunch.
enum AppLanguage: String, CaseIterable, Identifiable {
    case automatic, vi, en
    var id: String { rawValue }

    /// Each language's name written in that language; only Automatic is translated.
    @ViewBuilder var label: some View {
        switch self {
        case .automatic: Text("Tự động (theo máy)")
        case .vi: Text(verbatim: "Tiếng Việt")
        case .en: Text(verbatim: "English")
        }
    }

    private static let key = "AppleLanguages"

    static var current: AppLanguage {
        let saved = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?[key] as? [String]
        guard let n = saved?.first else { return .automatic }
        return n.hasPrefix("en") ? .en : .vi
    }

    func save() {
        if self == .automatic { UserDefaults.standard.removeObject(forKey: Self.key) }
        else { UserDefaults.standard.set([rawValue], forKey: Self.key) }
    }

    /// Relaunches the app: runs open after 1 second, then quits.
    static func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? p.run()
        NSApp.terminate(nil)
    }
}
