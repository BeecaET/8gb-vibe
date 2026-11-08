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
    case overview, memory, agents, devServers, processes, disk, backgroundItems, machine, freeRAM, log, inbox, settings, about
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
        case .machine: return String(localized: "Máy", bundle: .main)
        case .freeRAM: return String(localized: "Dọn RAM", bundle: .main)
        case .log: return String(localized: "Nhật ký", bundle: .main)
        case .inbox: return String(localized: "Thông báo", bundle: .main)
        case .settings: return String(localized: "Cài đặt", bundle: .main)
        case .about: return String(localized: "Giới thiệu", bundle: .main)
        }
    }

    /// Command-number shortcut shown in the sidebar and the command palette (Settings uses the standard Cmd-comma).
    var shortcut: Character? {
        switch self {
        case .overview: return "1"
        case .agents: return "2"
        case .devServers: return "3"
        case .memory: return "4"
        case .freeRAM: return "5"
        case .processes: return "6"
        case .disk: return "7"
        case .backgroundItems: return "8"
        case .machine: return "i"
        case .log: return "9"
        case .inbox: return "0"
        case .settings: return ","
        case .about: return nil
        }
    }

    /// Pages that show live process data (lists, top RAM, sessions); the others do not need fast process scans.
    var needsProcesses: Bool {
        switch self {
        case .overview, .memory, .agents, .devServers, .processes, .freeRAM: return true
        case .disk, .backgroundItems, .machine, .log, .inbox, .settings, .about: return false
        }
    }

    /// Shortcut as shown in tooltips and menus ("⌘1"), nil when the page has none.
    var shortcutHint: String? { shortcut.map { "⌘\($0)" } }

    /// Sidebar order and grouping (also used by the View menu).
    static let sidebarGroups: [(title: LocalizedStringKey, pages: [Page])] = [
        ("Vibe", [.agents, .devServers]),
        ("Xem", [.overview, .memory, .processes, .disk, .backgroundItems, .machine]),
        ("Xử lý", [.freeRAM, .log, .inbox]),
        ("Ứng dụng", [.settings, .about]),
    ]

    var symbol: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .memory: return "memorychip"
        case .agents: return "sparkles"
        case .devServers: return "server.rack"
        case .processes: return "list.bullet.rectangle"
        case .disk: return "internaldrive"
        case .backgroundItems: return "power"
        case .machine: return "laptopcomputer"
        case .freeRAM: return "wand.and.stars"
        case .log: return "clock.arrow.circlepath"
        case .inbox: return "bell"
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
    @Published var page: Page = .overview {
        didSet {
            if page.needsProcesses != oldValue.needsProcesses { scheduleProcessTimer() }
        }
    }

    /// Seconds since the last process scan, nil before the first one (the snapshot then carries the reference date).
    var processesAge: TimeInterval? {
        let age = Date().timeIntervalSince(processes.timestamp)
        return age >= 0 && age < 86_400 ? age : nil
    }
    /// The Cmd-K command palette is showing in the main window.
    @Published var showPalette = false
    @Published private(set) var candidates: [QuitCandidate] = []
    /// Items waiting for the user to confirm quitting (shows the confirmation dialog).
    @Published var pendingConfirmation: [QuitCandidate]?
    /// Result of the last cleanup, shown as a short reward card. Set once every item in a batch has finished.
    @Published var lastFreed: FreedSummary?
    /// Apps to have selected when Free RAM opens (set by "Review and quit" so the page shows exactly the apps named).
    @Published var freeRAMPreselect: Set<String>?
    /// First-run welcome sheet is showing.
    @Published var showWelcome = false
    /// Apps the user chose to keep ("Keep this"): never suggested, never preselected. Saved in UserDefaults.
    @Published private(set) var keptIDs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "mucGiu") ?? [])
    /// Running totals for the batch being quit right now.
    private var batchPending = 0, batchFreed: UInt64 = 0, batchCount = 0, batchFailed = 0
    /// Heavy-job slots past their 2-hour total while the job still runs.
    @Published var overdueSlots: [OverdueSlot] = []
    private var notifiedOverdue: Set<String> = []
    /// RAM and swap in use right before the current cleanup started.
    private var batchBefore: MemoryReading?
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
    let recorder: MeasurementRecorder
    /// Fine-grained samples kept in RAM, written to disk only while strained; freeze incidents.
    let blackBox: BlackBox
    private var forecast = FreezeForecast()
    /// Coordination files shared with the `8gbvibe-mcp` processes of AI agents.
    let agentHub = AgentHub(directory: AgentHub.defaultDirectory)
    /// What agents may do (Settings > AI agents). Saved to agents/policy.json for the MCP processes.
    @Published var agentPolicy = AgentPolicy() {
        didSet { agentHub.savePolicy(agentPolicy) }
    }
    /// Registered agents, slots and queue, refreshed with every system sample.
    @Published private(set) var agentState = HubState()
    /// This Mac, scanned once and saved in hardware.json.
    @Published private(set) var hardware: HardwareInfo
    /// Defaults that fit this Mac (thresholds, freeze warning, scan interval).
    @Published private(set) var profile: OptimizationProfile
    /// "Recognized this Mac: ... Using the 8 GB profile." after a (re)scan.
    @Published private(set) var hardwareNotice: String?
    /// Most recent freeze or stall, shown in the overview explanation for 2 hours.
    @Published private(set) var lastIncident: Incident?
    /// Marker removed on a normal quit: if it is still there at launch, the previous run did not quit normally.
    private let runMarker = BlackBox.defaultDirectory.appendingPathComponent("running")
    private var reportedUILag = false
    private var lastProcessSample: Date?
    /// Swapping hard (1 GB per minute or more) or critical memory pressure.
    private var heavyStrain: Bool {
        system?.pressure == .critical || (recorder.lastRates?.swapIOBytes ?? 0) * 60 >= 1024 * 1_048_576
    }
    /// Once-a-second check of how late the app gets (main thread and a background timer).
    private let probe = ResponsivenessProbe()
    private var alertThrottle = AlertThrottle()
    private var systemTimer: Timer?
    private var processTimer: Timer?
    private var samplingProcesses = false
    private let historyLimit = 720 // 1 hour at one point every 5 seconds

    init() {
        // Only one running copy of the app writes measurements and the black box (test copies share the folder).
        let store = MeasurementStore(directory: MeasurementStore.defaultDirectory)
        let writer = store.acquireLock()
        var previous: Incident?
        recorder = MeasurementRecorder(store: store)
        blackBox = BlackBox(directory: writer ? BlackBox.defaultDirectory : nil)
        recorder.probe = probe
        probe.start()
        if writer {
            let clean = !FileManager.default.fileExists(atPath: runMarker.path)
            try? FileManager.default.createDirectory(at: BlackBox.defaultDirectory, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            FileManager.default.createFile(atPath: runMarker.path, contents: Data(), attributes: [.posixPermissions: 0o600])
            previous = blackBox.checkPreviousRun(previousRunWasClean: clean, now: Date())
            let marker = runMarker
            NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
                try? FileManager.default.removeItem(at: marker)
            }
        }

        if let data = UserDefaults.standard.data(forKey: "nguong"),
           let n = try? JSONDecoder().decode(Thresholds.self, from: data) {
            thresholds = n
        } else {
            thresholds = Thresholds()
        }
        menuBarStyle = MenuBarStyle(rawValue: UserDefaults.standard.string(forKey: "kieuThanhMenu") ?? "") ?? .ringAndSwap
        sendNotifications = UserDefaults.standard.object(forKey: "guiThongBao") as? Bool ?? true
        // Hardware profile: scanned on first launch (and when the Mac, its RAM or macOS changed), then reused.
        let hw = HardwareStore(file: HardwareStore.defaultFile)
        let firstScan = hw.load() == nil
        let (info, rescanned) = hw.loadOrScan()
        hardware = info
        profile = OptimizationProfile.forHardware(info)
        applyProfile()
        if rescanned {
            hardwareNotice = String(localized: "Đã nhận diện máy: \(info.summary). Dùng hồ sơ \(profile.name).", bundle: .main)
            if firstScan { Notifier.info(title: String(localized: "Cấu hình máy", bundle: .main), body: hardwareNotice ?? "") }
        }

        agentPolicy = agentHub.loadPolicy()
        lastIncident = blackBox.incidents.last { $0.kind != .sleep }
        if let i = previous, sendNotifications {
            Notifier.incident(title: Self.title(i), text: Self.describe(i))
        }
        // Sleep and wake: a gap that contains a sleep is the Mac sleeping, not an incident.
        let center = NSWorkspace.shared.notificationCenter
        let box = blackBox
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in box.noteSleep(at: Date()) }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in box.noteWake(at: Date()) }

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
        if let i = lastIncident, Date().timeIntervalSince(i.start) < 2 * 3600 { items.append(Self.describe(i)) }
        if let budget = budget, budget.overflow > 0 {
            items.append(String(localized: "Các app cần \(Format.bytes(budget.demand)), máy có \(Format.bytes(budget.totalRAM, digits: 0)).", bundle: .main))
        }
        if h.pressure != .normal {
            items.append(String(localized: "Áp lực bộ nhớ: \(h.pressure.name).", bundle: .main))
        }
        if (levels[.swap] ?? .ok) != .ok { items.append(String(localized: "Swap đang dùng \(Format.bytes(h.swap.used)). Dung lượng swap cao chưa đủ để kết luận máy chậm.", bundle: .main)) }
        if (levels[.load] ?? .ok) != .ok { items.append(String(localized: "CPU đang tải \(Format.number(h.load.m5, digits: 0)) trên \(h.coreCount) nhân.", bundle: .main)) }
        if (levels[.disk] ?? .ok) != .ok { items.append(String(localized: "Ổ chỉ còn \(Format.bytes(h.disk.free, digits: 0)).", bundle: .main)) }
        if let rise = wiredRise {
            items.append(String(localized: "RAM wired của hệ thống tăng \(Format.bytes(rise)) trong 30 phút, chưa xác định nguyên nhân. Nếu máy chậm và mức này tiếp tục tăng, hãy lưu việc và cân nhắc khởi động lại.", bundle: .main))
        }
        return items.isEmpty ? String(localized: "Các chỉ số đang theo dõi chưa vượt ngưỡng cảnh báo đã đặt.", bundle: .main) : items.joined(separator: " ")
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
        if isIdle >= thresholds.idleMinutes * 60 { return (String(localized: "Ít CPU \(Format.duration(isIdle))", bundle: .main), .orange) }
        if lastActive.timeIntervalSince(monitoringStart) < 15 { return (String(localized: "Đang theo dõi", bundle: .main), .secondary) }
        return (String(localized: "Có CPU \(Format.duration(isIdle)) trước", bundle: .main), .green)
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

    // MARK: AI agents (MCP)

    /// While agents are registered, writes the machine status for the MCP processes (about 1 KB every 5 seconds),
    /// so they answer at once instead of sampling for a second. Nothing is written when no agent is active.
    private func shareWithAgents(_ h: SystemSnapshot) {
        var state = agentHub.read()
        // A slot past its time: refresh under the lock (drops dead holders, marks busy ones) before showing it.
        if state.slots.contains(where: { $0.lease(now: h.timestamp) != .active }) { state = agentHub.update(now: h.timestamp) { $0 } }
        if state != agentState { agentState = state }
        checkOverdue(state, now: h.timestamp)
        // A damaged coordination file was set aside by an MCP process: tell the user once.
        if let name = try? String(contentsOf: agentHub.corruptionNotice, encoding: .utf8) {
            try? FileManager.default.removeItem(at: agentHub.corruptionNotice)
            Notifier.info(title: String(localized: "Tệp phối hợp agent bị hỏng", bundle: .main),
                          body: String(localized: "Đã cất tệp hỏng thành \(name) và tạo tệp mới. Agent cần xin lại chỗ.", bundle: .main), bell: true)
        }
        guard agentHub.hasActiveAgents(now: h.timestamp) else { return }
        agentHub.saveStatus(MachineStatusReader.make(h, rates: recorder.lastRates, processes: processes, profile: profile,
                                                     thresholds: thresholds, source: "app"))
    }

    /// Overdue slots (past 2 hours, job still running): shown in Settings and once in the bell. Nothing is stopped.
    private func checkOverdue(_ state: HubState, now: Date) {
        let list = state.slots.filter { $0.lease(now: now) == .overdue && $0.expiredBusy == true }.map {
            OverdueSlot(id: $0.id, holder: AgentHub.describe(state, $0.agentID), kind: $0.kind, since: $0.acquiredAt, busyWith: $0.busyWith ?? [])
        }
        if list != overdueSlots { overdueSlots = list }
        for s in list where !notifiedOverdue.contains(s.id) {
            notifiedOverdue.insert(s.id)
            Notifier.info(title: String(localized: "Chỗ việc nặng bị giữ quá 2 giờ", bundle: .main),
                          body: String(localized: "\(s.holder) vẫn chạy \(s.busyWith.joined(separator: ", ")). App không dừng việc này. Mở Cài đặt > Agent AI để nhả chỗ nếu cần.", bundle: .main),
                          bell: true)
        }
    }

    /// The user released an overdue slot (after confirming). Only the reservation; no process is touched.
    func releaseOverdue(_ s: OverdueSlot) {
        let ok = agentHub.releaseByUser(slotID: s.id)
        ActionLog.write(LogEntry(timestamp: Date(), action: "Nhả chỗ việc nặng", target: "\(s.holder), \(s.kind)", freed: 0,
                                 outcome: ok ? "Nhả chỗ xong, không dừng tiến trình" : "Chỗ đã không còn"))
        agentState = agentHub.read()
        overdueSlots.removeAll { $0.id == s.id }
    }

    // MARK: Freezes

    /// Black box sample, freeze incidents and early warning. Runs with every system sample.
    private func watchForFreeze(_ h: SystemSnapshot) {
        let rate = (recorder.lastRates?.swapIOBytes ?? 0) * 60 / 1_048_576
        let sample = BlackBoxSample(time: h.timestamp, pressure: h.pressure == .critical ? 2 : (h.pressure == .warning ? 1 : 0),
                                    swapMBPerMin: rate, swapUsedGB: Double(h.swap.used) / Format.GB,
                                    suspect: recorder.currentSuspect(now: h.timestamp),
                                    uptime: ProcessInfo.processInfo.systemUptime)
        if let i = blackBox.add(sample) { report(i) }
        let lag = probe.lastMainLag
        if lag >= BlackBox.uiStallSeconds, !reportedUILag, let i = blackBox.uiLag(lag, at: h.timestamp) {
            reportedUILag = true
            report(i)
        } else if lag < 1 {
            reportedUILag = false
        }
        if let r = forecast.check(blackBox.ring, now: h.timestamp), sendNotifications {
            Notifier.freezeWarning(swapMBPerMin: r, windowSeconds: 60, pressure: sample.pressure, suspect: sample.suspect)
        }
    }

    private func report(_ i: Incident) {
        guard i.kind != .sleep else { return }   // the Mac sleeping is not an incident
        lastIncident = i
        if sendNotifications { Notifier.incident(title: Self.title(i), text: Self.describe(i)) }
    }

    /// Title by evidence (PHAN_HOI_CLAUDE_CAP_NHAT_2.md, table 4.2): only strong evidence says the Mac may have frozen.
    static func title(_ i: Incident) -> String {
        // Missing samples or a slow app alone never say the whole Mac froze (owner, 08/11/2026).
        if i.likelyFrozen { return String(localized: "Theo dõi bị gián đoạn lâu khi swap rất nặng", bundle: .main) }
        switch i.kind {
        case .gap: return String(localized: "Theo dõi bị gián đoạn khi máy căng", bundle: .main)
        case .uiStall: return String(localized: "8GB Vibe phản hồi chậm khi máy căng", bundle: .main)
        case .endedWhileStrained: return String(localized: "Lần trước app kết thúc bất thường khi máy căng", bundle: .main)
        case .sleep: return String(localized: "Máy ngủ", bundle: .main)
        }
    }

    /// "Monitoring stopped at 14:05 for 3 min while the Mac was strained. May be related: Claude Code (shop) +900 MB."
    static func describe(_ i: Incident) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let at = f.string(from: i.start)
        var s: String
        switch i.kind {
        case .gap:
            s = String(localized: "Lúc \(at), app không lấy được số đo trong \(Format.duration(i.duration ?? 0)) khi máy đang căng.", bundle: .main)
        case .uiStall:
            s = String(localized: "Lúc \(at), 8GB Vibe trả lời chậm \(Format.duration(i.duration ?? 0)) khi máy đang chịu tải; chưa xác định nguyên nhân.", bundle: .main)
        case .endedWhileStrained:
            s = i.rebooted == true
                ? String(localized: "Lần chạy trước của app kết thúc lúc \(at) khi máy đang căng; sau đó máy đã khởi động lại.", bundle: .main)
                : String(localized: "Lần chạy trước của app kết thúc lúc \(at) khi máy đang căng, không thoát bình thường.", bundle: .main)
        case .sleep:
            s = String(localized: "Máy ngủ lúc \(at), \(Format.duration(i.duration ?? 0)).", bundle: .main)
        }
        if i.peakSwapMBPerMin >= 100 {
            s += String(localized: " Swap lúc đó khoảng \(Format.number(i.peakSwapMBPerMin / 1024, digits: 1)) GB mỗi phút.", bundle: .main)
        }
        if !i.suspect.isEmpty { s += String(localized: " Có thể liên quan: \(i.suspect).", bundle: .main) }
        return s
    }

    private func scheduleProcessTimer() {
        processTimer?.invalidate()
        // A full process scan costs about 0.2 s of CPU (more while swapping). With a window open it runs every
        // 10 s, and only when the shown page lists processes (the menu bar panel always does); otherwise at the
        // background pace. Measured before: 15.7 % CPU with the main window open, 0.3 % without.
        let fast = visibleViews.contains("popover") || (visibleViews.contains("main-window") && page.needsProcesses)
        let seconds: TimeInterval = fast ? 10 : profile.backgroundScanSeconds
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
        watchForFreeze(h)
        shareWithAgents(h)
        history.append(HistoryPoint(timestamp: h.timestamp, swapGB: Double(h.swap.used) / Format.GB,
                                 ramRatio: h.memory.usedRatio, load: h.load.m1, wired: h.memory.wired))
        if history.count > historyLimit { history.removeFirst(history.count - historyLimit) }
        evaluate()
        if previousPressure != nil, (previousPressure == .critical) != (h.pressure == .critical) { scheduleSystemTimer() }
    }

    func sampleProcesses() {
        guard !samplingProcesses else { return }
        // Under heavy strain, read processes at most every 30 seconds even with a window open:
        // the scan touches every process and allocates, which only adds to the paging.
        if heavyStrain, let last = lastProcessSample, Date().timeIntervalSince(last) < 30 { return }
        lastProcessSample = Date()
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
        // Published values are assigned only when they changed: every assignment re-renders the views watching the Monitor.
        let newLevels = thresholds.evaluate(h, sessionCount: processes.sessions.count)
        if newLevels != levels { levels = newLevels }
        let selfIdentifier = Bundle.main.bundleIdentifier
        let newCandidates = CandidateBuilder.from(processes, selfIdentifier: selfIdentifier)
        if newCandidates != candidates { candidates = newCandidates }
        let newSuggestions = SuggestionBuilder.from(processes, idleTime: thresholds.idleMinutes * 60, selfIdentifier: selfIdentifier)
            .filter { if case .quitAll(let u) = $0.kind { return !keptIDs.contains(u.id) }; return true }
        if newSuggestions != suggestions { suggestions = newSuggestions }
        // Alerts whose condition is over are marked "resolved" in the in-app inbox.
        Inbox.shared.resolve(levels: levels)
        let toSend = alertThrottle.check(levels, now: Date())
        if sendNotifications {
            // Pressure, swap and load are already part of "Mac is slow", so they are not reported separately to avoid piling up alerts.
            for (metric, item) in toSend where [.slowMac, .disk, .claudeSessions].contains(metric) {
                Notifier.gui(metric: metric, item: item, system: h, sessionCount: processes.sessions.count, suggestions: suggestions)
            }
        }
    }

    /// Uses the profile's defaults for every threshold the user has not changed, plus the freeze warning,
    /// headroom reserve and background scan interval. The defaults applied last time are remembered to tell
    /// untouched values from the user's own.
    private func applyProfile() {
        let key = "profileDefaults"
        let previous = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Thresholds.self, from: $0) } ?? Thresholds()
        let adopted = thresholds.adopting(newDefaults: profile.thresholds, previousDefaults: previous)
        if adopted != thresholds { thresholds = adopted }
        if let data = try? JSONEncoder().encode(profile.thresholds) { UserDefaults.standard.set(data, forKey: key) }
        forecast.severe = profile.freezeSevereMBPerMin
        forecast.rising = profile.freezeRisingMBPerMin
        SessionHeadroom.currentReserve = profile.headroomReserve
    }

    /// "Rescan" in Settings or About.
    func rescanHardware() {
        let info = HardwareScanner.scan()
        HardwareStore(file: HardwareStore.defaultFile).save(info)
        hardware = info
        profile = OptimizationProfile.forHardware(info)
        applyProfile()
        hardwareNotice = String(localized: "Đã nhận diện máy: \(info.summary). Dùng hồ sơ \(profile.name).", bundle: .main)
        scheduleProcessTimer()
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

    /// Keep an app: hide it from suggestions and preselection until the user un-keeps it.
    func keep(_ id: String, _ on: Bool) {
        if on { keptIDs.insert(id) } else { keptIDs.remove(id) }
        UserDefaults.standard.set(Array(keptIDs), forKey: "mucGiu")
        evaluate()
    }

    func quitAll(_ items: [QuitCandidate]) {
        if batchPending == 0 { batchFreed = 0; batchCount = 0; batchFailed = 0; batchBefore = MemoryReading.now() }
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
        let before = MemoryReading.now()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            ProcessActions.forceQuit(u)
            Thread.sleep(forTimeInterval: 2)
            let running = ProcessActions.isRunning(u)
            Task { @MainActor in
                guard let self else { return }
                self.actionStates[u.id] = running ? .notQuit : .quit
                ActionLog.write(LogEntry(timestamp: Date(), action: u.isProcess ? "Buộc dừng" : "Buộc thoát", target: u.name,
                                      freed: u.footprint, outcome: running ? "Chưa thoát" : "Đã thoát"))
                if !running { self.showFreed(FreedSummary(bytes: u.footprint, count: 1), before: before) }
                self.sampleProcesses()
            }
        }
    }

    /// Counts one finished item of the current batch; when the batch is done and something closed, shows the reward card.
    private func finishBatchItem(freed: UInt64?) {
        if let freed { batchFreed += freed; batchCount += 1 } else { batchFailed += 1 }
        batchPending = max(0, batchPending - 1)
        // The card only appears when something actually closed; it also says how many did not.
        if batchPending == 0, batchCount > 0 {
            showFreed(FreedSummary(bytes: batchFreed, count: batchCount, failed: batchFailed), before: batchBefore)
        }
    }

    /// Shows the reward card with the estimate now, then measures RAM and swap again after 10 seconds
    /// and logs both numbers ("giaiPhong" estimated, "doDuoc" measured).
    private func showFreed(_ summary: FreedSummary, before: MemoryReading?) {
        var s = summary
        s.measuring = before != nil
        lastFreed = s
        guard let before else { return }
        let id = s.id
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + MeasuredDrop.delay) { [weak self] in
            let after = MemoryReading.now()
            Task { @MainActor in
                guard let self else { return }
                let drop = after.map { MeasuredDrop(before: before, after: $0) }
                if self.lastFreed?.id == id { self.lastFreed?.measured = drop; self.lastFreed?.measuring = false }
                ActionLog.write(LogEntry(timestamp: Date(), action: "Đo sau khi dọn",
                                         target: String(localized: "\(s.count) mục", bundle: .main),
                                         freed: s.bytes, outcome: drop == nil ? "Không đo được" : "Đo sau 10 giây", measured: drop))
            }
        }
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
