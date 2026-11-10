import AppKit
import SwiftUI
import VibeCore

/// One alert the app raised, kept so it can be read again inside the app.
struct InboxEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var date: Date
    /// Level.rawValue: 0 ok, 1 warning, 2 critical.
    var level: Int
    var title: String
    var body: String
    /// Page to open from the entry (Page.rawValue).
    var page: String
    var read = false
    /// Metric this alert is about (Metric.rawValue), so it can be marked over when the level is back to normal.
    var metric: String? = nil
    /// When the condition was over; nil while it is still going on.
    var resolvedAt: Date? = nil

    var levelValue: Level { Level(rawValue: level) ?? .warning }
    var target: Page { Page(rawValue: page) ?? .overview }
}

/// Recent alerts: what was sent to Notification Center, plus freeze warnings and incidents.
/// Kept in memory and in a small file readable only by the user (0600), at most 100 entries from the last 7 days.
/// Viewing only: entries open a page, they never quit anything.
@MainActor
final class Inbox: ObservableObject {
    static let shared = Inbox()

    @Published private(set) var entries: [InboxEntry] = []
    /// The panel under the bell is open.
    var unread: [InboxEntry] { entries.filter { !$0.read } }

    private static let limit = 100
    private static let maxAge: TimeInterval = 7 * 24 * 3600
    static var file: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Product.name, isDirectory: true)
        return directory.appendingPathComponent(StoredName.inboxFile)
    }
    /// Preview entries (UI testing) are never written to disk.
    private var isPreview = false

    private init() {
        if let data = try? Data(contentsOf: Self.file),
           let list = try? JSONDecoder().decode([InboxEntry].self, from: data) {
            entries = Self.trimmed(list)
        }
    }

    func add(level: Level, title: String, body: String, page: Page, metric: Metric? = nil, alreadyOver: Bool = false) {
        // The same alert repeated within 10 minutes replaces the previous one instead of piling up.
        if let i = entries.firstIndex(where: { $0.title == title && Date().timeIntervalSince($0.date) < 600 }) {
            entries.remove(at: i)
        }
        let now = Date()
        entries.insert(InboxEntry(date: now, level: level.rawValue, title: title, body: body, page: page.rawValue,
                                  metric: metric?.rawValue, resolvedAt: alreadyOver ? now : nil), at: 0)
        entries = Self.trimmed(entries)
        save()
    }

    /// Marks alerts as over once their metric is back to OK, so the bell does not show a past problem as current.
    func resolve(levels: [Metric: Level]) {
        var changed = false
        let now = Date()
        for i in entries.indices where entries[i].resolvedAt == nil {
            guard let raw = entries[i].metric, let m = Metric(rawValue: raw) else { continue }
            if (levels[m] ?? .ok) == .ok { entries[i].resolvedAt = now; changed = true }
        }
        if changed { save() }
    }

    func markAllRead() {
        guard entries.contains(where: { !$0.read }) else { return }
        for i in entries.indices { entries[i].read = true }
        save()
    }

    func markRead(_ id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }), !entries[i].read else { return }
        entries[i].read = true
        save()
    }

    /// Sample alerts for screenshots (--preview-inbox); kept in memory only.
    func loadPreview() {
        isPreview = true
        let now = Date()
        entries = [
            InboxEntry(date: now.addingTimeInterval(-120), level: 2, title: String(localized: "Swap is very heavy", bundle: .main),
                       body: String(localized: "Swap is growing 1.2 GB per minute. Save your work and close some sessions or apps.", bundle: .main), page: Page.freeRAM.rawValue),
            InboxEntry(date: now.addingTimeInterval(-1500), level: 1, title: String(localized: "Claude Code sessions: warning", bundle: .main),
                       body: String(localized: "28 Claude Code sessions open. Review and end finished sessions where you started them.", bundle: .main), page: Page.agents.rawValue),
            InboxEntry(date: now.addingTimeInterval(-7200), level: 1, title: String(localized: "Monitoring was interrupted while the Mac was strained", bundle: .main),
                       body: String(localized: "At 13:05, the app got no readings for 40 seconds while the Mac was strained. Possibly related: Claude, Chrome.", bundle: .main), page: Page.overview.rawValue, read: true),
            InboxEntry(date: now.addingTimeInterval(-90000), level: 1, title: String(localized: "Disk: warning", bundle: .main),
                       body: String(localized: "Only 38 GB free on disk.", bundle: .main), page: Page.disk.rawValue, read: true,
                       metric: "disk", resolvedAt: now.addingTimeInterval(-80000)),
        ]
    }

    private static func trimmed(_ list: [InboxEntry]) -> [InboxEntry] {
        let since = Date().addingTimeInterval(-maxAge)
        return Array(list.filter { $0.date >= since }.prefix(limit))
    }

    private func save() {
        guard !isPreview else { return }
        let url = Self.file
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

extension Metric {
    /// The page that explains an alert for this metric.
    var page: Page {
        switch self {
        case .disk: return .disk
        case .load: return .processes
        case .claudeSessions: return .agents
        case .pressure, .swap, .slowMac: return .freeRAM
        }
    }
}

// MARK: Views

/// 24-hour time; adds the date when it is not today.
private func inboxTime(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: Format.isEnglish ? "en_GB" : "vi_VN")
    f.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "HH:mm · dd/MM"
    return f.string(from: d)
}

/// Notifications page (sidebar, under Actions): recent alerts with level color, 24-hour time and a link to the
/// related page. Lives in the sidebar with an unread badge instead of a bell in the title bar.
struct InboxPage: View {
    @EnvironmentObject var monitor: Monitor
    @ObservedObject private var inbox = Inbox.shared

    var body: some View {
        PageContainer {
            HStack(alignment: .firstTextBaseline) {
                if inbox.unread.isEmpty {
                    Text(inbox.entries.isEmpty ? "No notifications yet" : "All read").foregroundStyle(.secondary)
                } else {
                    Text("\(inbox.unread.count) unread").fontWeight(.semibold)
                }
                Spacer()
                Button("Mark all read") { inbox.markAllRead() }
                    .disabled(inbox.unread.isEmpty)
            }
            if inbox.entries.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "bell.slash").font(.largeTitle).foregroundStyle(.tertiary)
                    Text("Threshold alerts, heavy swap activity and monitoring interruptions appear here when notifications are enabled in Settings.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(40)
                .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(inbox.entries.enumerated()), id: \.element.id) { i, e in
                        if i > 0 { Divider().padding(.leading, 46) }
                        row(e)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .card(padding: 0)
            }
            Text("Keeps up to 100 notifications from the last 7 days, on this Mac only. The latest unread, unresolved alert also appears at the top of the menu bar panel.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func row(_ e: InboxEntry) -> some View {
        let over = e.resolvedAt != nil
        let color = over ? Color.green : e.levelValue.color
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: over ? "checkmark.circle.fill" : (e.levelValue == .critical ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill"))
                .foregroundStyle(color).font(.title3).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(e.title).fontWeight(e.read ? .regular : .semibold)
                    Spacer()
                    Text(inboxTime(e.date)).font(.callout).monospacedDigit().foregroundStyle(.secondary)
                }
                Text(e.body).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    if let t = e.resolvedAt {
                        Label("Over at \(inboxTime(t))", systemImage: "checkmark").font(.callout).foregroundStyle(.green)
                    }
                    Button("View \(e.target.name) ›") {
                        inbox.markRead(e.id)
                        monitor.page = e.target
                    }
                    .buttonStyle(.link).font(.callout)
                    if !e.read {
                        Button("Mark read") { inbox.markRead(e.id) }.buttonStyle(.link).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(e.read ? Color.clear : color.opacity(0.07))
    }
}

/// Newest unread alert at the top of the menu bar popover; tapping it opens the related page.
struct InboxStrip: View {
    @ObservedObject private var inbox = Inbox.shared
    var open: (Page) -> Void

    var body: some View {
        // Only a problem that is still going on is shown here.
        if let e = inbox.unread.first(where: { $0.resolvedAt == nil }) {
            HStack(spacing: 8) {
                Image(systemName: e.levelValue == .critical ? "exclamationmark.triangle.fill" : "bell.badge.fill")
                    .foregroundStyle(e.levelValue.color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(e.title).font(.callout.weight(.semibold)).lineLimit(1)
                    Text("\(inboxTime(e.date)) · \(e.body)").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if inbox.unread.count > 1 {
                    Text("+\(inbox.unread.count - 1)").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                }
                Button { inbox.markRead(e.id) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                    .help("Mark read").accessibilityLabel("Mark as read")
            }
            .padding(10)
            .background(e.levelValue.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { inbox.markRead(e.id); open(e.target) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
        }
    }
}
