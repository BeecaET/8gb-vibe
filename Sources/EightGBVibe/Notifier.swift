import Foundation
import VibeCore
import UserNotifications

/// Sends macOS notifications. Only works when the app runs as a packaged .app (needs a bundle id).
enum Notifier {
    private static var askedPermission = false

    static let openFreeRAM = Notification.Name("vn.beeca.8gbvibe.moDonRAM")

    static func gui(metric: Metric, item: Level, system h: SystemSnapshot, sessionCount: Int, suggestions: [Suggestion]) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        if !askedPermission {
            askedPermission = true
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        let content = UNMutableNotificationContent()
        content.title = metric == .slowMac ? String(localized: "Máy đang chậm", bundle: .main)
            : (item == .critical ? String(localized: "\(metric.name): nguy hiểm", bundle: .main) : String(localized: "\(metric.name): cảnh báo", bundle: .main))
        content.body = messageText(metric, h, sessionCount, suggestions)
        content.sound = item == .critical ? .default : nil
        let req = UNNotificationRequest(identifier: "alert-\(metric.rawValue)", content: content, trigger: nil)
        center.add(req)
    }

    static func messageText(_ metric: Metric, _ h: SystemSnapshot, _ sessionCount: Int, _ suggestions: [Suggestion]) -> String {
        switch metric {
        case .slowMac:
            let advice = suggestions.prefix(3).map { g -> String in
                if case let .quitAll(u) = g.kind { return "\(u.name) (\(Format.bytes(u.footprint)))" }
                return String(localized: "lưu trữ phiên Claude (\(Format.bytes(g.freed)))", bundle: .main)
            }
            let head = String(localized: "Swap \(Format.bytes(h.swap.used)), tải \(Format.number(h.load.m5, digits: 0)).", bundle: .main)
            return advice.isEmpty ? head + String(localized: " Bấm để xem nên tắt gì.", bundle: .main) : head + String(localized: " Nên tắt: ", bundle: .main) + advice.joined(separator: ", ") + String(localized: ". Bấm để xem.", bundle: .main)
        case .pressure: return String(localized: "Áp lực bộ nhớ đang ở mức \(h.pressure.name.lowercased()). Mở app để xem nên tắt gì.", bundle: .main)
        case .swap: return String(localized: "Swap đã lên \(Format.bytes(h.swap.used)). Máy sẽ chậm dần.", bundle: .main)
        case .disk: return String(localized: "Ổ chỉ còn \(Format.bytes(h.disk.free)) trống.", bundle: .main)
        case .load: return String(localized: "Tải CPU 5 phút là \(Format.number(h.load.m5, digits: 0)), máy có \(h.coreCount) nhân.", bundle: .main)
        case .claudeSessions: return String(localized: "Đang mở \(sessionCount) phiên Claude Code. Nên lưu trữ phiên đã xong.", bundle: .main)
        }
    }
}
