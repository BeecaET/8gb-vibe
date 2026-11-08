import SwiftUI
import VibeCore

/// The one thing worth doing right now, in one sentence, with at most one button.
/// Every main screen and the popover lead with this instead of a wall of numbers.
struct Advice: Equatable {
    enum Action: Equatable {
        /// Open Free RAM with the idle suggestions already picked.
        case freeRAM
        /// Review sessions where they were started; opening Claude cannot manage every CLI session.
        case reviewSessions
        case reviewDisk
        case none
    }

    var level: Level
    var headline: String
    var detail: String
    var actionTitle: String?
    var action: Action

    var symbol: String {
        switch level {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .critical: return "exclamationmark.triangle.fill"
        }
    }
}

extension Monitor {
    /// Sessions open for more than a day: usually finished work that still holds RAM.
    var longRunningSessions: [ClaudeCodeSession] {
        processes.sessions.filter { Date().timeIntervalSince($0.startDate) > 24 * 3600 }
    }

    /// Picks the single most useful advice, in priority order:
    /// 1. idle apps worth quitting, 2. too many long-running agent sessions, 3. the Mac is slow (say why),
    /// 4. the Mac is fine (say how much room is left). Suggests only; every action still goes through confirmation.
    var advice: Advice {
        guard system != nil, processesAge != nil else {
            return Advice(level: .ok, headline: String(localized: "Đang thu thập số liệu", bundle: .main),
                          detail: String(localized: "Chờ số đo hệ thống và tiến trình trước khi đánh giá.", bundle: .main), actionTitle: nil, action: .none)
        }
        let level = overallLevel
        if levels[.disk] != .ok, let diskLevel = levels[.disk],
           levels.filter({ $0.key != .disk }).values.allSatisfy({ $0 == .ok }) {
            return Advice(level: diskLevel, headline: String(localized: "Ổ chứa macOS sắp đầy", bundle: .main),
                          detail: explanation, actionTitle: String(localized: "Xem dung lượng ổ đĩa", bundle: .main), action: .reviewDisk)
        }
        let idleApps = suggestions.filter { if case .quitAll = $0.kind { return true }; return false }
        if !idleApps.isEmpty, freeableFromCandidates > 0 {
            return Advice(level: max(level, .warning),
                          headline: String(localized: "\(idleApps.count) mục ít hoạt động đang giữ khoảng \(Format.bytes(freeableFromCandidates))", bundle: .main),
                          detail: String(localized: "\(names(idleApps)) ít hoạt động hơn \(Format.number(thresholds.idleMinutes, digits: 0)) phút. Hãy kiểm tra việc đang làm trước khi đóng.", bundle: .main),
                          actionTitle: String(localized: "Xem và đóng", bundle: .main), action: .freeRAM)
        }
        let sessions = processes.sessions
        let old = longRunningSessions
        if sessions.count >= thresholds.sessionsYellow, !old.isEmpty {
            // Age does not prove a session is finished: say it was opened over a day ago and let the user decide.
            let held = old.reduce(UInt64(0)) { $0 + $1.footprint }
            return Advice(level: max(level, .warning),
                          headline: String(localized: "\(old.count) phiên Claude Code đã mở hơn 1 ngày", bundle: .main),
                          detail: String(localized: "Chúng giữ khoảng \(Format.bytes(held)). Mở lâu không có nghĩa là đã xong. Hãy kiểm tra và kết thúc phiên tại nơi bạn mở nó. Đang mở \(sessions.count) phiên; ngưỡng vàng là \(thresholds.sessionsYellow).", bundle: .main),
                          actionTitle: String(localized: "Xem các phiên", bundle: .main), action: .reviewSessions)
        }
        if level != .ok {
            // State facts, not a cause: name the sessions and what they hold; "may be related" only when they hold most of the RAM.
            let held = sessions.reduce(UInt64(0)) { $0 + $1.footprint }
            let used = system?.memory.used ?? 0
            var headline = HealthScore.summary(score)
            var detail = explanation
            if sessions.count >= thresholds.sessionsYellow {
                headline = String(localized: "Đang mở \(sessions.count) phiên Claude Code, giữ khoảng \(Format.bytes(held))", bundle: .main)
                if used > 0, Double(held) > Double(used) * 0.4 {
                    detail = String(localized: "Có thể liên quan đến việc máy chậm. ", bundle: .main) + explanation
                }
            }
            return Advice(level: level, headline: headline, detail: detail,
                          actionTitle: String(localized: "Xem nên đóng gì", bundle: .main), action: .freeRAM)
        }
        let roomText: String
        if let b = budget {
            switch SessionHeadroom(budget: b, sessions: AIToolBuilder.from(processes).flatMap(\.sessions)).state {
            case .room(let n): roomText = String(localized: "Còn chỗ cho khoảng \(n) phiên agent nữa.", bundle: .main)
            case .tight, .short: roomText = String(localized: "RAM gần đầy, chưa nên mở thêm phiên.", bundle: .main)
            }
        } else {
            roomText = ""
        }
        return Advice(level: .ok, headline: String(localized: "Máy đang ổn", bundle: .main),
                      detail: roomText, actionTitle: nil, action: .none)
    }

    /// "ChatGPT, WeChat và 1 app khác": names of the first suggested apps.
    private func names(_ items: [Suggestion]) -> String {
        let list = items.compactMap { g -> String? in if case .quitAll(let u) = g.kind { return u.name }; return nil }
        let shown = list.prefix(2).joined(separator: ", ")
        return list.count > 2 ? String(localized: "\(shown) và \(list.count - 2) app khác", bundle: .main) : shown
    }

    /// Navigates to the relevant page; quitting still needs the confirmation sheet.
    func perform(_ action: Advice.Action) {
        switch action {
        case .freeRAM:
            // Open Free RAM with exactly the idle apps named in the advice selected (nothing quits until confirmed).
            let ids = suggestions.compactMap { g -> String? in if case .quitAll(let u) = g.kind { return u.id }; return nil }
            freeRAMPreselect = Set(ids)
            page = .freeRAM
        case .reviewSessions: page = .agents
        case .reviewDisk: page = .disk
        case .none: break
        }
    }
}

/// Card that shows the advice: colored symbol, headline, one line of detail, one primary button.
struct AdviceCard: View {
    @EnvironmentObject var monitor: Monitor
    var compact = false
    /// Called after the action ran (the popover uses it to open the main window).
    var didAct: ((Advice.Action) -> Void)?

    var body: some View {
        let a = monitor.advice
        let color = a.level.color
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: a.symbol).foregroundStyle(color).font(compact ? .callout : .title3)
                Text(a.headline)
                    .font(compact ? .callout.weight(.semibold) : .system(size: 22, weight: .bold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !a.detail.isEmpty {
                Text(a.detail).font(compact ? .callout : .body).foregroundStyle(.secondary)
                    .lineLimit(compact ? 2 : nil).fixedSize(horizontal: false, vertical: true)
            }
            if let title = a.actionTitle {
                Button {
                    monitor.perform(a.action)
                    didAct?(a.action)
                } label: {
                    Label(title, systemImage: a.action == .reviewSessions ? "archivebox" : "bolt.fill")
                }
                .buttonStyle(.borderedProminent).controlSize(compact ? .regular : .large)
                .padding(.top, 2)
            }
        }
        .padding(compact ? 12 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: compact ? 12 : 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: compact ? 12 : 16, style: .continuous).stroke(color.opacity(0.28), lineWidth: 1))
        .animation(.easeOut(duration: 0.25), value: a)
        .accessibilityElement(children: .contain)
    }
}
