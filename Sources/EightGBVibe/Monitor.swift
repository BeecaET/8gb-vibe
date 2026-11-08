import AppKit
import Foundation
import SwiftUI
import VibeCore

struct HistoryPoint: Identifiable {
    var id: Date { timestamp }
    var timestamp: Date
    var swapGB: Double
    var ramRatio: Double
    var load: Double
    var wired: UInt64 = 0
}

enum Page: String, CaseIterable, Identifiable {
    case overview, memory, agents, devServers, processes, disk, backgroundItems, freeRAM, log, settings, about
    var id: String { rawValue }

    var name: String {
        switch self {
        case .overview: return String(localized: "Tổng quan", bundle: .main)
        case .memory: return String(localized: "Bộ nhớ", bundle: .main)
        case .agents: return String(localized: "Agent AI", bundle: .main)
        case .devServers: return String(localized: "Dev server", bundle: .main)
        case .processes: return String(localized: "Tiến trình", bundle: .main)
        case .disk: return String(localized: "Ổ đĩa", bundle: .main)
        case .backgroundItems: return String(localized: "Chạy nền", bundle: .main)
        case .freeRAM: return String(localized: "Dọn RAM", bundle: .main)
        case .log: return String(localized: "Nhật ký", bundle: .main)
        case .settings: return String(localized: "Cài đặt", bundle: .main)
        case .about: return String(localized: "Giới thiệu", bundle: .main)
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .memory: return "memorychip"
        case .agents: return "sparkles"
        case .devServers: return "server.rack"
        case .processes: return "list.bullet.rectangle"
        case .disk: return "internaldrive"
        case .backgroundItems: return "power"
        case .freeRAM: return "wand.and.stars"
        case .log: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

enum MenuBarStyle: String, CaseIterable, Identifiable {
    // Raw values are stored in UserDefaults by earlier versions: keep them.
    case ringAndSwap = "vongVaSwap", ringOnly = "chiVong", ringAndRAM = "vongVaRAM"
    var id: String { rawValue }
    var name: String {
        switch self {
        case .ringAndSwap: return String(localized: "Vòng tròn và swap", bundle: .main)
        case .ringOnly: return String(localized: "Chỉ vòng tròn", bundle: .main)
        case .ringAndRAM: return String(localized: "Vòng tròn và % RAM", bundle: .main)
        }
    }
}

enum ActionState: Equatable {
    case quitting, quit, notQuit
}

/// Samples periodically and holds the state for the UI.
/// System metrics: every 5 seconds (15 when overloaded). Processes: every 5 seconds while UI is visible, 60 seconds in the background.
@MainActor
final class Monitor: ObservableObject {
    @Published private(set) var system: SystemSnapshot?
    @Published private(set) var processes: ProcessSnapshot = .empty
    @Published private(set) var history: [HistoryPoint] = []
    @Published private(set) var levels: [Metric: Level] = [:]
    @Published private(set) var suggestions: [Suggestion] = []
    @Published private(set) var disk: [DiskItem] = DiskScanner.catalog
    @Published private(set) var scanningDisk = false
    @Published private(set) var lastDiskScan: Date?
    @Published private(set) var backgroundItems: [BackgroundItem] = []
    @Published var page: Page = .overview
    @Published private(set) var candidates: [QuitCandidate] = []
    /// Items waiting for the user to confirm quitting (shows the confirmation dialog).
    @Published var pendingConfirmation: [QuitCandidate]?
    /// Result of the last cleanup, shown as a short reward card. Set once every item in a batch has finished.
    @Published var lastFreed: FreedSummary?
    /// Running totals for the batch being quit right now.
    private var batchPending = 0, batchFreed: UInt64 = 0, batchCount = 0
    /// Item that did not quit, waiting for force quit confirmation.
    @Published var pendingForceQuit: QuitCandidate?
    @Published private(set) var actionStates: [String: ActionState] = [:]

    @Published var thresholds: Thresholds {
        didSet { saveThresholds(); evaluate() }
    }
    @Published var menuBarStyle: MenuBarStyle {
        didSet { UserDefaults.standard.set(menuBarStyle.rawValue, forKey: "kieuThanhMenu") }
    }
    @Published var sendNotifications: Bool {
        didSet { UserDefaults.standard.set(sendNotifications, forKey: "guiThongBao") }
    }

    /// Visible UI (popover, main window). When any is visible, processes are sampled more often.
    private var visibleViews: Set<String> = []

    func reportVisibility(_ name: String, _ show: Bool) {
        let before = !visibleViews.isEmpty
        if show { visibleViews.insert(name) } else { visibleViews.remove(name) }
        let after = !visibleViews.isEmpty
        guard before != after else { return }
        if after { sampleProcesses() }
        scheduleProcessTimer()
    }

    private let queue = DispatchQueue(label: "vn.beeca.8gbvibe.laymau", qos: .utility)
    private let analyzer = ProcessAnalyzer()
    /// Per-minute measurements (swap I/O, compression, heavy jobs), kept on this Mac only.
    let recorder = MeasurementRecorder(store: MeasurementStore(directory: MeasurementStore.defaultDirectory))
    private var alertThrottle = AlertThrottle()
    private var systemTimer: Timer?
    private var processTimer: Timer?
    private var samplingProcesses = false
    private let historyLimit = 720 // 1 hour at one point every 5 seconds

    init() {
        if let data = UserDefaults.standard.data(forKey: "nguong"),
           let n = try? JSONDecoder().decode(Thresholds.self, from: data) {
            thresholds = n
        } else {
            thresholds = Thresholds()
        }
        menuBarStyle = MenuBarStyle(rawValue: UserDefaults.standard.string(forKey: "kieuThanhMenu") ?? "") ?? .ringAndSwap
        sendNotifications = UserDefaults.standard.object(forKey: "guiThongBao") as? Bool ?? true

        // Read the disk once right away so the app does not falsely report "disk full" at launch.
        cachedDisk = SystemReader.disk()
        lastDiskRead = Date()
        sampleSystem()
        sampleProcesses()
        scheduleSystemTimer()
        scheduleProcessTimer()
        readBackgroundItems()
    }

    // MARK: Derived values

    var overallLevel: Level { levels.values.max() ?? .ok }

    var score: Int { system.map { HealthScore.compute($0, thresholds: thresholds, swapIO: recorder.lastRates?.swapIOBytes) } ?? 100 }

    /// Total RAM freeable by quitting everything suggested (Claude Code sessions not included).
    var freeableFromCandidates: UInt64 {
        suggestions.reduce(0) { total, g in if case .quitAll = g.kind { return total + g.freed }; return total }
    }

    /// One sentence explaining why the Mac is slow or fine.
    var explanation: String {
        guard let h = system else { return "" }
        var items: [String] = []
        if let budget = budget, budget.overflow > 0 {
            items.append(String(localized: "Các app cần \(Format.bytes(budget.demand)), máy có \(Format.bytes(budget.totalRAM, digits: 0)).", bundle: .main))
        }
        if (levels[.swap] ?? .ok) != .ok { items.append(String(localized: "Swap \(Format.bytes(h.swap.used)) làm máy chậm.", bundle: .main)) }
        if (levels[.load] ?? .ok) != .ok { items.append(String(localized: "CPU đang tải \(Format.number(h.load.m5, digits: 0)) trên \(h.coreCount) nhân.", bundle: .main)) }
        if (levels[.disk] ?? .ok) != .ok { items.append(String(localized: "Ổ chỉ còn \(Format.bytes(h.disk.free, digits: 0)).", bundle: .main)) }
        if let rise = wiredRise {
            items.append(String(localized: "RAM wired của hệ thống tăng \(Format.bytes(rise)) trong 30 phút, có thể do rò bộ nhớ trong nhân. Nếu còn tăng, hãy khởi động lại máy.", bundle: .main))
        }
        return items.isEmpty ? String(localized: "RAM, CPU và ổ đĩa đều trong ngưỡng an toàn.", bundle: .main) : items.joined(separator: " ")
    }

    /// Wired memory rising steadily over 30 minutes (kernel-side leak, invisible in process footprints).
    var wiredRise: UInt64? {
        MemoryGrowth.wiredRise(history.map { ($0.timestamp, $0.wired) }, now: history.last?.timestamp ?? Date())
    }

    var budget: RAMBudget? {
        system.map { RAMBudget(memory: $0.memory, snapshot: processes) }
    }

    var totalFreeable: UInt64 { suggestions.reduce(0) { $0 + $1.freed } }

    /// When the app started monitoring. Idle time can only be measured from this point.
    let monitoringStart = Date()

    func isSessionIdle(_ p: ClaudeCodeSession, now: Date = Date()) -> Bool {
        now.timeIntervalSince(p.lastActive) >= thresholds.idleMinutes * 60
    }

    /// Activity status of a session or item, based on the last time it used CPU.
    func status(cpu: Double, lastActive: Date, now: Date = Date()) -> (String, Color) {
        let isIdle = now.timeIntervalSince(lastActive)
        if cpu >= 2 { return (String(localized: "Đang chạy", bundle: .main), .green) }
        if isIdle >= thresholds.idleMinutes * 60 { return (String(localized: "Rảnh \(Format.duration(isIdle))", bundle: .main), .orange) }
        if lastActive.timeIntervalSince(monitoringStart) < 15 { return (String(localized: "Đang theo dõi", bundle: .main), .secondary) }
        return (String(localized: "Dùng \(Format.duration(isIdle)) trước", bundle: .main), .green)
    }

    // MARK: Sampling

    private func scheduleSystemTimer() {
        systemTimer?.invalidate()
        let seconds: TimeInterval = system?.pressure == .critical ? 15 : 5
        let t = Timer(timeInterval: seconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleSystem() }
        }
        t.tolerance = seconds * 0.2
        RunLoop.main.add(t, forMode: .common)
        systemTimer = t
    }

    private func scheduleProcessTimer() {
        processTimer?.invalidate()
        let seconds: TimeInterval = visibleViews.isEmpty ? 60 : 5
        let t = Timer(timeInterval: seconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleProcesses() }
        }
        t.tolerance = seconds * 0.2
        RunLoop.main.add(t, forMode: .common)
        processTimer = t
    }

    /// Disk capacity is read every 60 seconds on a background thread (slow to read, keep it off the main thread).
    private var cachedDisk: Disk?
    private var lastDiskRead: Date = .distantPast

    private func readDiskIfNeeded() {
        guard Date().timeIntervalSince(lastDiskRead) >= 60 else { return }
        lastDiskRead = Date()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let o = SystemReader.disk()
            Task { @MainActor in self?.cachedDisk = o }
        }
    }

    private func sampleSystem() {
        readDiskIfNeeded()
        guard let h = SystemReader.snapshot(disk: cachedDisk ?? Disk(total: 0, free: 0)) else { return }
        let previousPressure = system?.pressure
        system = h
        recorder.addSystem(h, counters: VMCounters.read())
        history.append(HistoryPoint(timestamp: h.timestamp, swapGB: Double(h.swap.used) / Format.GB,
                                 ramRatio: h.memory.usedRatio, load: h.load.m1, wired: h.memory.wired))
        if history.count > historyLimit { history.removeFirst(history.count - historyLimit) }
        evaluate()
        if previousPressure != nil, (previousPressure == .critical) != (h.pressure == .critical) { scheduleSystemTimer() }
    }

    func sampleProcesses() {
        guard !samplingProcesses else { return }
        samplingProcesses = true
        let engine = analyzer
        let apps = Self.runningApps()
        queue.async { [weak self] in
            let result = engine.run(apps: apps)
            Task { @MainActor in
                guard let self else { return }
                self.processes = result
                self.recorder.addProcesses(result)
                self.samplingProcesses = false
                self.evaluate()
            }
        }
    }

    private func evaluate() {
        guard let h = system else { return }
        levels = thresholds.evaluate(h, sessionCount: processes.sessions.count)
        let selfIdentifier = Bundle.main.bundleIdentifier
        candidates = CandidateBuilder.from(processes, selfIdentifier: selfIdentifier)
        suggestions = SuggestionBuilder.from(processes, idleTime: thresholds.idleMinutes * 60, selfIdentifier: selfIdentifier)
        let toSend = alertThrottle.check(levels, now: Date())
        if sendNotifications {
            // Pressure, swap and load are already part of "Mac is slow", so they are not reported separately to avoid piling up alerts.
            for (metric, item) in toSend where [.slowMac, .disk, .claudeSessions].contains(metric) {
                Notifier.gui(metric: metric, item: item, system: h, sessionCount: processes.sessions.count, suggestions: suggestions)
            }
        }
    }

    private func saveThresholds() {
        if let data = try? JSONEncoder().encode(thresholds) { UserDefaults.standard.set(data, forKey: "nguong") }
    }

    // MARK: Disk, background items

    func scanDisk() {
        guard !scanningDisk else { return }
        scanningDisk = true
        let items = DiskScanner.catalog
        DispatchQueue.global(qos: .background).async { [weak self] in
            for item in items {
                let size = DiskScanner.measureSize(item.path)
                Task { @MainActor in
                    guard let self, let i = self.disk.firstIndex(where: { $0.id == item.id }) else { return }
                    self.disk[i].bytes = size
                }
            }
            Task { @MainActor in
                self?.scanningDisk = false
                self?.lastDiskScan = Date()
            }
        }
    }

    func readBackgroundItems() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let items = BackgroundItemReader.readAll()
            Task { @MainActor in self?.backgroundItems = items }
        }
    }

    // MARK: Quitting apps (only called after the user confirms)

    static func runningApps() -> [RunningApp] {
        let before = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { a in
            guard a.activationPolicy == .regular, let url = a.bundleURL else { return nil }
            return RunningApp(pid: a.processIdentifier, bundleId: a.bundleIdentifier,
                                 name: a.localizedName ?? url.deletingPathExtension().lastPathComponent,
                                 bundlePath: url.path, isFrontmost: a.processIdentifier == before)
        }
    }

    func quitAll(_ items: [QuitCandidate]) {
        if batchPending == 0 { batchFreed = 0; batchCount = 0 }
        batchPending += items.count
        for u in items {
            actionStates[u.id] = .quitting
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                ProcessActions.quitAll(u)
                // Wait for the app to save and close, then check.
                var running = true
                for _ in 0..<10 {
                    Thread.sleep(forTimeInterval: 1)
                    running = ProcessActions.isRunning(u)
                    if !running { break }
                }
                let outcome = running
                Task { @MainActor in
                    guard let self else { return }
                    self.actionStates[u.id] = outcome ? .notQuit : .quit
                    ActionLog.write(LogEntry(timestamp: Date(), action: u.isProcess ? "Dừng" : "Thoát", target: u.name,
                                          freed: u.footprint, outcome: outcome ? "Chưa thoát" : "Đã thoát"))
                    self.finishBatchItem(freed: outcome ? nil : u.footprint)
                    self.sampleProcesses()
                }
            }
        }
    }

    func forceQuit(_ u: QuitCandidate) {
        actionStates[u.id] = .quitting
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            ProcessActions.forceQuit(u)
            Thread.sleep(forTimeInterval: 2)
            let running = ProcessActions.isRunning(u)
            Task { @MainActor in
                guard let self else { return }
                self.actionStates[u.id] = running ? .notQuit : .quit
                ActionLog.write(LogEntry(timestamp: Date(), action: u.isProcess ? "Buộc dừng" : "Buộc thoát", target: u.name,
                                      freed: u.footprint, outcome: running ? "Chưa thoát" : "Đã thoát"))
                if !running { self.lastFreed = FreedSummary(bytes: u.footprint, count: 1) }
                self.sampleProcesses()
            }
        }
    }

    /// Counts one finished item of the current batch; when the batch is done and something closed, shows the reward card.
    private func finishBatchItem(freed: UInt64?) {
        if let freed { batchFreed += freed; batchCount += 1 }
        batchPending = max(0, batchPending - 1)
        if batchPending == 0, batchCount > 0 { lastFreed = FreedSummary(bytes: batchFreed, count: batchCount) }
    }

    /// Builds a candidate from a process in the Processes table (picked by the user).
    func candidates(from t: ProcessRow) -> QuitCandidate {
        if let a = processes.apps.first(where: { $0.app.pid == t.pid }), let u = candidates.first(where: { $0.id == "app:\(a.app.bundlePath)" }) {
            return u
        }
        return QuitCandidate(id: "pid:\(t.id)", name: "\(t.name) (PID \(t.pid))", group: t.kind.group,
                          quitMethod: .processes([ProcessIdentity(pid: t.pid, startDate: t.startDate)]), footprint: t.footprint ?? 0, cpu: t.cpu,
                          startDate: t.startDate, lastActive: t.startDate, isFrontmost: false,
                          note: String(localized: "Gửi tín hiệu dừng nhẹ (SIGTERM).", bundle: .main), blockedReason: ProcessGuard.reason(t))
    }

    func openClaude() {
        let url = URL(fileURLWithPath: "/Applications/Claude.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
