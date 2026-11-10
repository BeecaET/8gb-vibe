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
            TableColumn("Name", value: \.name) { t in
                HStack(spacing: 6) {
                    GroupIcon(group: t.kind.group, size: 16)
                    Text(t.name).lineLimit(1)
                }
            }
            TableColumn("Group", value: \.groupName) { t in Text(t.groupName).foregroundStyle(.secondary).lineLimit(1) }
            TableColumn("RAM", value: \.ramSort) { t in
                Text(t.footprint.map { Format.bytes($0) } ?? "-").monospacedDigit()
            }.width(75)
            TableColumn("CPU", value: \.cpu) { t in Text(Format.number(t.cpu, digits: 1) + Format.percentSign).monospacedDigit() }.width(60)
            TableColumn("PID", value: \.pidSort) { t in Text(verbatim: "\(t.pid)").monospacedDigit().foregroundStyle(.secondary) }.width(60)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .contextMenu(forSelectionType: ProcessRow.ID.self) { ids in
            let selection = monitor.processes.processes.filter { ids.contains($0.id) && ProcessIdentity(pid: $0.pid, startDate: $0.startDate).canStop() }
            Button(selection.count == 1 ? String(localized: "Quit \(selection[0].name)…", bundle: .main)
                                   : String(localized: "Quit \(selection.count) processes…", bundle: .main)) {
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
        .searchable(text: $searchText, prompt: "Name, group or PID")
    }

    /// Bottom bar: what is selected, why it cannot be quit, and the quit button. Quitting still goes through the
    /// same checks (ProcessIdentity, ProcessGuard) and the confirmation sheet as the context menu.
    private var footer: some View {
        let picked = monitor.processes.processes.filter { selection.contains($0.id) }
        let stoppable = picked.filter { ProcessIdentity(pid: $0.pid, startDate: $0.startDate).canStop() }
        let ram = stoppable.reduce(UInt64(0)) { $0 + ($1.footprint ?? 0) }
        return HStack(spacing: 12) {
            if picked.isEmpty {
                Text("Select rows (hold Cmd for several) or right-click to quit your processes.")
                    .foregroundStyle(.secondary)
            } else if stoppable.isEmpty {
                Label(picked.count == 1 ? (ProcessGuard.reason(picked[0]) ?? String(localized: "Cannot quit", bundle: .main))
                                        : String(localized: "None of the selected processes can be quit.", bundle: .main),
                      systemImage: "lock.fill")
                    .foregroundStyle(.orange)
            } else {
                Text("\(stoppable.count) processes selected · \(Format.bytes(ram))").foregroundStyle(.secondary).monospacedDigit()
                if stoppable.count < picked.count {
                    Text("\(picked.count - stoppable.count) skipped").foregroundStyle(.orange)
                }
            }
            Spacer()
            Button(stoppable.isEmpty ? String(localized: "Quit…", bundle: .main)
                   : stoppable.count == 1 ? String(localized: "Quit \(stoppable[0].name)…", bundle: .main)
                   : String(localized: "Quit \(stoppable.count) processes…", bundle: .main)) {
                monitor.pendingConfirmation = stoppable.map { monitor.candidates(from: $0) }
            }
            .buttonStyle(.borderedProminent)
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
                    SectionTitle("macOS volume", subtitle: "Free \(Format.bytes(h.disk.free, digits: 0)) / \(Format.bytes(h.disk.total, digits: 0))")
                    ProgressView(value: h.disk.fullRatio).tint(diskLevel == .ok ? Palette.tint : diskLevel.color)
                    Text("\(Format.percent(h.disk.fullRatio)) used").font(.callout).foregroundStyle(.secondary)
                }
                .card()
            }
            HStack {
                Text(monitor.scanningDisk ? String(localized: "Scanning…", bundle: .main)
                     : monitor.lastDiskScan.map { String(localized: "Scanned at \(LogPage.time($0))", bundle: .main) } ?? String(localized: "Not scanned", bundle: .main))
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                if monitor.scanningDisk { ProgressView().controlSize(.small) }
                Button(monitor.lastDiskScan == nil ? String(localized: "Scan", bundle: .main) : String(localized: "Rescan", bundle: .main)) { monitor.scanDisk() }.disabled(monitor.scanningDisk)
            }
            group(.safe, "Recreatable caches", "Usually recreated or downloaded again; the next run may take longer. Close the relevant tool before cleaning manually.")
            group(.review, "Review carefully", "May hold data still in use. Your call.")
            group(.inApp, "Data to review manually", "Clean in the relevant app; review Downloads in Finder.")
            Text("The app only measures size. Nothing is deleted.").font(.callout).foregroundStyle(.secondary)
        }
        .onAppear { if monitor.lastDiskScan == nil { monitor.scanDisk() } }
    }

    private func group(_ kind: DiskItem.Kind, _ name: LocalizedStringKey, _ summary: LocalizedStringKey) -> some View {
        let items = monitor.disk.filter { $0.kind == kind }.sorted { ($0.bytes ?? 0) > ($1.bytes ?? 0) }
        let total = items.reduce(UInt64(0)) { $0 + ($1.bytes ?? 0) }
        return VStack(alignment: .leading, spacing: 0) {
            SectionTitle(name, subtitle: total > 0 ? "Total \(Format.bytes(total))" : nil).padding(.bottom, 2)
            Text(summary).font(.callout).foregroundStyle(.secondary).padding(.bottom, 8)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, m in
                    if i > 0 { Divider() }
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.name)
                            Text(m.note).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(m.bytes.map { Format.bytes($0) } ?? (monitor.scanningDisk ? String(localized: "…", bundle: .main) : String(localized: "Missing or unreadable", bundle: .main)))
                            .monospacedDigit().foregroundStyle((m.bytes ?? 0) < 1 << 20 ? .secondary : .primary)
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: m.path)])
                        } label: { Image(systemName: "magnifyingglass") }
                            .buttonStyle(.borderless)
                            .help("Show in Finder")
                            .accessibilityLabel("Show \(m.name) in Finder")
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
                Text("LaunchAgent/LaunchDaemon configurations found on this Mac; not all are necessarily running. This app only reads them. You can also check System Settings > General > Login Items.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Open Login Items") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .card(padding: 12)
            ForEach([BackgroundItem.Scope.currentUser, .allUsers, .system], id: \.self) { scopeValue in
                let items = monitor.backgroundItems.filter { $0.scope == scopeValue }
                if !items.isEmpty {
                    SectionTitle(LocalizedStringKey(scopeValue.rawValue), subtitle: "\(items.count) items")
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
                        .font(.callout).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                        .help(m.program)
                }
            }
            Spacer(minLength: 8)
            if m.runAtLoad { StatusPill(owner: "When loaded", color: .secondary) }
            if m.keepAlive { StatusPill(owner: "Keep-alive rule", color: .orange) }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Settings

/// App language. Stored as AppleLanguages in the app's saved defaults (system settings are untouched). Needs a relaunch.
enum AppLanguage: String, CaseIterable, Identifiable {
    case automatic, vi, en
    var id: String { rawValue }

    /// Each language's name written in that language; only Automatic is translated.
    @ViewBuilder var label: some View {
        switch self {
        case .automatic: Text("Automatic (system)")
        case .vi: Text(verbatim: "Ti\u{1EBF}ng Vi\u{1EC7}t")  // the language's own name, never translated
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
