import Foundation

/// Something that can be quit to free RAM: a GUI app, Simulator, Gradle daemon, emulator.
/// Data only. The app quits it after the user confirms.
public struct QuitCandidate: Identifiable, Sendable, Hashable {
    public enum QuitMethod: Sendable, Hashable {
        /// Sends the standard macOS quit; the app saves and closes itself. `others`: further running copies of the
        /// same app bundle (e.g. Chrome started twice with different profiles), quit the same way.
        case app(ProcessIdentity, bundleId: String?, others: [ProcessIdentity] = [])
        /// Shuts down every booted Simulator device (`xcrun simctl shutdown all`), then quits Simulator.app.
        case simulator(app: ProcessIdentity?)
        /// Sends a gentle stop signal (SIGTERM) to the processes.
        /// Each identity (pid, start time, user) is checked again right before the signal, so a reused pid is never hit.
        case processes([ProcessIdentity])
    }

    public var id: String
    public var name: String
    public var group: WorkCategory
    public var quitMethod: QuitMethod
    public var footprint: UInt64
    public var cpu: Double
    public var startDate: Date
    public var lastActive: Date
    public var isFrontmost: Bool
    public var note: String
    /// Why it may not be quit from the app. nil means it may be quit.
    public var blockedReason: String?

    public init(id: String, name: String, group: WorkCategory, quitMethod: QuitMethod, footprint: UInt64, cpu: Double,
                startDate: Date, lastActive: Date, isFrontmost: Bool, note: String, blockedReason: String?) {
        self.id = id; self.name = name; self.group = group; self.quitMethod = quitMethod; self.footprint = footprint
        self.cpu = cpu; self.startDate = startDate; self.lastActive = lastActive; self.isFrontmost = isFrontmost
        self.note = note; self.blockedReason = blockedReason
    }

    /// Stopped with a signal (not an app quit).
    public var isProcess: Bool {
        switch quitMethod {
        case .processes: return true
        default: return false
        }
    }

    /// Idle: not frontmost, no CPU use, and no activity seen for a while.
    public func isIdle(afterSeconds: TimeInterval, now: Date = Date()) -> Bool {
        !isFrontmost && cpu < 2 && now.timeIntervalSince(lastActive) >= afterSeconds
    }
}

public enum CandidateBuilder {
    /// Minimum RAM for a GUI app to be listed.
    public static var ramThreshold: UInt64 = 50 << 20

    static let protectedBundles: [String: String] = [
        "com.apple.finder": String(localized: "Finder là một phần của macOS.", bundle: .main),
        "com.apple.dock": String(localized: "Dock là một phần của macOS.", bundle: .main),
        "com.apple.systemuiserver": String(localized: "Một phần của macOS.", bundle: .main)
    ]

    static func isClaude(_ a: RunningApp) -> Bool {
        a.bundlePath.hasSuffix("/Claude.app") || (a.bundleId ?? "").hasPrefix("com.anthropic.claude")
    }

    static func isSimulator(_ a: RunningApp) -> Bool {
        a.bundleId == "com.apple.iphonesimulator" || a.bundlePath.hasSuffix("/Simulator.app")
    }

    /// `selfIdentifier`: this app's bundle id, always left out of the list.
    public static func from(_ result: ProcessSnapshot, selfIdentifier: String? = nil) -> [QuitCandidate] {
        var items: [QuitCandidate] = []

        // Simulator: both Simulator.app and the virtual iOS device processes.
        if let m = result.item(.xcode, ItemName.simulator), m.footprint > 0 {
            let app = result.apps.first { isSimulator($0.app) }
            items.append(QuitCandidate(id: "simulator", name: "Simulator iOS", group: .xcode,
                                 quitMethod: .simulator(app: app?.identity), footprint: m.footprint, cpu: m.cpu,
                                 startDate: m.earliestStart, lastActive: max(m.lastActive, app?.lastActive ?? .distantPast),
                                 isFrontmost: app?.app.isFrontmost ?? false,
                                 note: String(localized: "Tắt mọi máy Simulator đang bật. Dữ liệu trong máy ảo vẫn giữ.", bundle: .main), blockedReason: nil))
        }

        // Gradle daemon, Android emulator: no UI, stopped with SIGTERM.
        for (name, item, note) in [("Gradle daemon", ItemName.gradle, String(localized: "Lần build sau tự khởi động lại.", bundle: .main)),
                                   ("Emulator Android", ItemName.emulator, String(localized: "Máy Android ảo sẽ tắt.", bundle: .main))] {
            guard let m = result.item(.android, item), m.footprint > 0 else { continue }
            let identities = result.processes.filter { $0.kind == Classification(.android, item) }
                .map { ProcessIdentity(pid: $0.pid, startDate: $0.startDate) }
            items.append(QuitCandidate(id: "android/\(item)", name: m.processCount > 1 ? "\(name) (\(m.processCount))" : name,
                                 group: .android, quitMethod: .processes(identities), footprint: m.footprint, cpu: m.cpu,
                                 startDate: m.earliestStart, lastActive: m.lastActive, isFrontmost: false,
                                 note: note, blockedReason: nil))
        }

        // GUI apps.
        let dockerVM = result.item(.docker, ItemName.dockerVM)
        for a in result.apps {
            if let b = selfIdentifier, a.app.bundleId == b { continue }
            if isSimulator(a.app) { continue }
            var fp = a.footprint
            var note = a.otherInstances.isEmpty
                ? String(localized: "\(a.processCount) tiến trình. App có thể hỏi lưu trước khi đóng.", bundle: .main)
                : String(localized: "\(a.otherInstances.count + 1) bản app đang chạy, \(a.processCount) tiến trình. App có thể hỏi lưu trước khi đóng.", bundle: .main)
            let isDocker = a.app.bundleId == "com.docker.docker" || a.app.bundlePath.hasSuffix("/Docker.app")
            if isDocker, let vm = dockerVM {
                fp += vm.footprint
                note = String(localized: "Gồm cả máy ảo Docker. Container đang chạy sẽ dừng.", bundle: .main)
            }
            // Without the main process identity the app cannot be quit safely, so it is not listed.
            guard fp >= ramThreshold, let identity = a.identity else { continue }
            var key = a.app.bundleId.flatMap { protectedBundles[$0] }
            if isClaude(a.app) {
                key = String(localized: "App Claude được bảo vệ để tránh ngắt công việc bên trong. Hãy quản lý phiên tại nơi bạn mở nó.", bundle: .main)
            }
            let group = ProcessClassifier.classifyOne(ProcessRecord(pid: a.app.pid, ppid: 1, uid: 501, name: a.app.name,
                                                        path: a.app.bundlePath + "/Contents/MacOS/x",
                                                        startDate: a.startDate, footprint: nil, cpuNanos: nil)).0.group
            items.append(QuitCandidate(id: "app:\(a.app.bundlePath)", name: a.app.name, group: group,
                                 quitMethod: .app(identity, bundleId: a.app.bundleId, others: a.otherInstances),
                                 footprint: fp, cpu: a.cpu, startDate: a.startDate, lastActive: a.lastActive,
                                 isFrontmost: a.app.isFrontmost, note: note, blockedReason: key))
        }
        // Orphaned processes: the agent or window has closed but the server still runs.
        items += orphanCandidates(result)
        return items.sorted { $0.footprint > $1.footprint }
    }

    /// Candidate to stop a dev server: the whole process tree, with an identity check before signaling.
    public static func from(_ d: DevServer, now: Date = Date()) -> QuitCandidate {
        var name = d.serverKind
        if let project = d.projectName { name += " (\(project))" }
        if let c = d.ports.first { name += String(localized: ", cổng \(String(c.number))", bundle: .main) + (d.ports.count > 1 ? "..." : "") }
        let note: String
        if let o = d.origin, d.orphaned {
            note = o.orphanNote(now: now)
        } else if d.orphaned {
            note = String(localized: "Mồ côi: người chạy đã thoát nhưng tiến trình vẫn chạy.", bundle: .main)
        } else {
            note = String(localized: "Chạy từ \(d.ownerDescription).", bundle: .main)
        }
        return QuitCandidate(id: d.id, name: name, group: .otherDev, quitMethod: .processes(d.processIdentities),
                          footprint: d.footprint, cpu: d.cpu, startDate: d.startDate, lastActive: d.lastActive,
                          isFrontmost: false, note: note + String(localized: " Gửi tín hiệu dừng nhẹ.", bundle: .main), blockedReason: nil)
    }

    /// Orphans as quit candidates. Orphans from the same agent session are grouped so they can be stopped at once.
    public static func orphanCandidates(_ result: ProcessSnapshot) -> [QuitCandidate] {
        let orphans = result.devServers.filter(\.orphaned)
        var items = orphans.filter { $0.origin == nil }.map { from($0, now: result.timestamp) }
        let bySession = Dictionary(grouping: orphans.filter { $0.origin != nil }, by: { $0.origin!.sessionID })
        for key in bySession.keys.sorted() {
            let group = bySession[key]!
            items.append(group.count == 1 ? from(group[0], now: result.timestamp) : fromOrphans(group, now: result.timestamp))
        }
        return items
    }

    /// One candidate for every orphan left by the same agent session: stopped together after one confirmation.
    public static func fromOrphans(_ group: [DevServer], now: Date = Date()) -> QuitCandidate {
        let o = group[0].origin!
        let kinds = Array(Set(group.map(\.serverKind))).sorted().joined(separator: ", ")
        return QuitCandidate(id: "orphans:\(o.sessionID)",
                             name: String(localized: "\(group.count) tiến trình mồ côi của \(o.sessionDescription)", bundle: .main),
                             group: .otherDev, quitMethod: .processes(group.flatMap(\.processIdentities)),
                             footprint: group.reduce(0) { $0 + $1.footprint }, cpu: group.reduce(0) { $0 + $1.cpu },
                             startDate: group.map(\.startDate).min() ?? now, lastActive: group.map(\.lastActive).max() ?? now,
                             isFrontmost: false,
                             note: kinds + ". " + o.orphanNote(now: now) + String(localized: " Gửi tín hiệu dừng nhẹ.", bundle: .main),
                             blockedReason: nil)
    }
}

public struct Suggestion: Identifiable, Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case archiveClaudeSessions
        case quitAll(QuitCandidate)
        /// An agent session whose memory keeps growing: suggest exiting and resuming it. The app does nothing itself.
        case restartSession(String)
    }
    public var id: String
    public var kind: Kind
    public var title: String
    public var detail: String
    public var freed: UInt64
}

public enum SuggestionBuilder {
    /// RAM a freshly resumed session is expected to need; the rest is counted as freed by restarting.
    public static let restartBaseline: UInt64 = 250 << 20

    /// Suggestions from idle Claude Code sessions and idle candidates above 200 MB. Suggests only, never acts.
    public static func from(_ result: ProcessSnapshot, idleTime: TimeInterval, selfIdentifier: String? = nil,
                          now: Date = Date()) -> [Suggestion] {
        var items: [Suggestion] = []
        let isSessionIdle = result.sessions.filter { now.timeIntervalSince($0.lastActive) >= idleTime }
        if !isSessionIdle.isEmpty {
            items.append(Suggestion(id: "phien-claude", kind: .archiveClaudeSessions,
                           title: String(localized: "Kiểm tra \(isSessionIdle.count) phiên Claude Code ít hoạt động", bundle: .main),
                           detail: String(localized: "Ít dùng CPU trên \(Format.duration(idleTime)); có thể đang chờ phản hồi. Nếu đã xong, kết thúc tại nơi bạn mở phiên.", bundle: .main),
                           freed: isSessionIdle.reduce(0) { $0 + $1.footprint }))
        }
        for u in CandidateBuilder.from(result, selfIdentifier: selfIdentifier)
        where u.blockedReason == nil && u.footprint >= 200 << 20 && u.isIdle(afterSeconds: idleTime, now: now) {
            items.append(Suggestion(id: u.id, kind: .quitAll(u), title: String(localized: "Tắt \(u.name)", bundle: .main),
                           detail: String(localized: "Ít dùng CPU trong \(Format.duration(now.timeIntervalSince(u.lastActive))). Hãy kiểm tra trước khi đóng.", bundle: .main),
                           freed: u.footprint))
        }
        // Sessions growing in memory: exiting and resuming gives the memory back (/clear does not).
        for w in result.memoryWarnings {
            let session = w.projectName.map { "\(w.agent) (\($0))" } ?? w.agent
            let title: String
            switch w.kind {
            case .large:
                title = String(localized: "\(session) chiếm \(Format.bytes(w.footprint))", bundle: .main)
            case let .growing(step):
                title = String(localized: "\(session) tăng \(Format.bytes(step)) mỗi 10 phút", bundle: .main)
            }
            let detail = w.agent == "Claude Code"
                ? String(localized: "Gõ /exit rồi mở lại bằng claude -c để trả RAM. /clear không trả RAM. App không tự làm.", bundle: .main)
                : String(localized: "Thoát phiên rồi mở lại để trả RAM. App không tự làm.", bundle: .main)
            items.append(Suggestion(id: "phinh:\(w.sessionID)", kind: .restartSession(w.sessionID), title: title, detail: detail,
                                    freed: w.footprint > restartBaseline ? w.footprint - restartBaseline : 0))
        }
        return items.sorted { $0.freed > $1.freed }
    }
}
