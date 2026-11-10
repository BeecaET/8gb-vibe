import Foundation
import VibeCore
import UserNotifications

/// Sends macOS notifications. Only works when the app runs as a packaged .app (needs a bundle id).
enum Notifier {
    private static var askedPermission = false

    static let openFreeRAM = Notification.Name("vn.beeca.8gbvibe.openFreeRAM")

    static func gui(metric: Metric, item: Level, system h: SystemSnapshot, sessionCount: Int, suggestions: [Suggestion]) {
        let title = metric == .slowMac ? String(localized: "Mac is slow", bundle: .main)
            : (item == .critical ? String(localized: "\(metric.name): critical", bundle: .main) : String(localized: "\(metric.name): warning", bundle: .main))
        let body = messageText(metric, h, sessionCount, suggestions)
        // Keep a copy in the in-app inbox (Notifications page in the main window, strip in the popover).
        record(level: item, title: title, body: body, page: metric.page, metric: metric)
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        if !askedPermission {
            askedPermission = true
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = item == .critical ? .default : nil
        let req = UNNotificationRequest(identifier: "alert-\(metric.rawValue)", content: content, trigger: nil)
        center.add(req)
    }

    /// Freeze warning from the swap trend.
    /// Very heavy swap: the measured rate, over which window, and memory pressure. No prediction, no sure cause.
    static func freezeWarning(swapMBPerMin: Double, windowSeconds: Int, pressure: Int, suspect: String) {
        let level = pressure >= 2 ? String(localized: "critical", bundle: .main)
                  : pressure == 1 ? String(localized: "warning", bundle: .main) : String(localized: "normal", bundle: .main)
        var body = String(localized: "Swap in and out averaged \(Format.number(swapMBPerMin / 1024, digits: 1)) GB per minute over the last \(windowSeconds) seconds. Memory pressure: \(level). The Mac may be slow; save your work and close some sessions or apps.", bundle: .main)
        if !suspect.isEmpty { body += String(localized: " Grew most in RAM recently (not necessarily the cause): \(suspect).", bundle: .main) }
        let title = String(localized: "Swap is very heavy", bundle: .main)
        record(level: .critical, title: title, body: body, page: .freeRAM, metric: .slowMac)
        send(id: "freeze-warning", title: title, body: body, loud: true)
    }

    /// After the Mac comes back: when it stalled, for how long, what may be related.
    static func incident(title: String, text: String) {
        // A stall is reported after the Mac came back: it is already over.
        record(level: .warning, title: title, body: text, page: .overview, alreadyOver: true)
        send(id: "freeze-incident", title: title, body: text, loud: false)
    }

    private static func record(level: Level, title: String, body: String, page: Page, metric: Metric? = nil, alreadyOver: Bool = false) {
        Task { @MainActor in Inbox.shared.add(level: level, title: title, body: body, page: page, metric: metric, alreadyOver: alreadyOver) }
    }

    /// A plain information notice (for example the first hardware scan).
    static func info(title: String, body: String, bell: Bool = false) {
        if bell { record(level: .warning, title: title, body: body, page: .settings) }
        send(id: "info-\(title.hashValue)", title: title, body: body, loud: false)
    }

    private static func send(id: String, title: String, body: String, loud: Bool) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        if !askedPermission {
            askedPermission = true
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = loud ? .default : nil
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    static func messageText(_ metric: Metric, _ h: SystemSnapshot, _ sessionCount: Int, _ suggestions: [Suggestion]) -> String {
        switch metric {
        case .slowMac:
            let advice = suggestions.prefix(3).map { g -> String in
                g.title
            }
            let head = String(localized: "Swap \(Format.bytes(h.swap.used)), load \(Format.number(h.load.m5, digits: 0)).", bundle: .main)
            return advice.isEmpty ? head + String(localized: " Click to see what to quit.", bundle: .main) : head + String(localized: " Suggestions: ", bundle: .main) + advice.joined(separator: ", ") + String(localized: ". Click to view.", bundle: .main)
        case .pressure: return String(localized: "Memory pressure is \(h.pressure.name.lowercased()). Open the app to see what to quit.", bundle: .main)
        case .swap: return String(localized: "Swap in use: \(Format.bytes(h.swap.used)). Heavy swap I/O can slow the Mac.", bundle: .main)
        case .disk: return String(localized: "Only \(Format.bytes(h.disk.free)) left free on the disk.", bundle: .main)
        case .load: return String(localized: "5-minute CPU load is \(Format.number(h.load.m5, digits: 0)) on \(h.coreCount) cores.", bundle: .main)
        case .claudeSessions: return String(localized: "\(sessionCount) Claude Code sessions open. Review and end finished sessions where you started them.", bundle: .main)
        }
    }
}
