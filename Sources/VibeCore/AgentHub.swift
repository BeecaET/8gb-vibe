import Darwin
import Foundation

// MARK: Policy

/// What AI agents may do through 8GB Vibe's MCP server. Written by the app (Settings), read by `8gbvibe-mcp`.
public struct AgentPolicy: Codable, Sendable, Hashable {
    public enum Level: String, Codable, Sendable, CaseIterable {
        /// Machine status only.
        case readOnly
        /// Status plus coordination between agents (register, slots, messages). Default.
        case coordinate
        /// Coordination plus low-risk actions the user allowed in advance. Not used yet (later phase).
        case lowRiskActions
    }

    public var level: Level
    /// Later phase: an agent may stop orphans its own session started, only while the Mac is short of RAM. Off by default.
    public var allowOwnOrphanStopWhenShort: Bool

    public init(level: Level = .coordinate, allowOwnOrphanStopWhenShort: Bool = false) {
        self.level = level; self.allowOwnOrphanStopWhenShort = allowOwnOrphanStopWhenShort
    }

    public var allowsCoordination: Bool { level != .readOnly }
}

// MARK: Machine status

/// Machine status shared with agents. Always says when it was measured and how old it is; never turns "not measured" into 0.
public struct MachineStatus: Codable, Sendable, Hashable {
    public var measuredAt: Date
    /// "app" (written by the running app) or "direct" (read by the MCP process itself).
    public var source: String
    public var ramTotalGB: Double
    public var ramUsedPercent: Double
    public var swapUsedGB: Double
    /// Swap in plus out per minute. nil when not measured (first sample, counter error).
    public var swapMBPerMin: Double?
    /// "normal", "warning" or "critical"; nil when unknown.
    public var pressure: String?
    public var healthScore: Int?
    /// Pressure warning or worse, or heavy swapping. nil when neither is known.
    public var strained: Bool?
    /// Hardware profile name, for example "8 GB".
    public var profile: String
    public var freezeWarningMBPerMin: Double
    /// Heaviest work categories ("Claude: 6.2 GB").
    public var topGroups: [String]
    public var agentSessions: [String]
    /// Length of the window the swap rate was measured over, seconds (1 when read directly, noisy).
    public var windowSeconds: Double?

    public func dataAge(now: Date = Date()) -> Int { max(0, Int(now.timeIntervalSince(measuredAt).rounded())) }

    /// Strained from what is known: pressure warning or worse, or swap at least `strainMB` per minute.
    public static func strained(pressure: String?, swapMBPerMin: Double?, strainMB: Double = MeasurementRecorder.strainSwapMB) -> Bool? {
        if let p = pressure, p != "normal" { return true }
        if let r = swapMBPerMin, r >= strainMB { return true }
        if pressure == nil && swapMBPerMin == nil { return nil }
        return false
    }
}

public enum MachineStatusReader {
    /// Builds a status from a system snapshot (and an optional process snapshot).
    public static func make(_ h: SystemSnapshot, rates: VMRates?, processes: ProcessSnapshot?, profile: OptimizationProfile,
                            thresholds: Thresholds, source: String, windowSeconds: Double? = nil) -> MachineStatus {
        let rate = rates.map { ($0.swapIOBytes * 60 / 1_048_576).rounded() }
        let pressure: String = h.pressure == .critical ? "critical" : (h.pressure == .warning ? "warning" : "normal")
        return MachineStatus(
            measuredAt: h.timestamp, source: source,
            ramTotalGB: Double(h.memory.total) / Format.GB, ramUsedPercent: (h.memory.usedRatio * 100).rounded(),
            swapUsedGB: (Double(h.swap.used) / Format.GB * 10).rounded() / 10, swapMBPerMin: rate,
            pressure: pressure, healthScore: HealthScore.compute(h, thresholds: thresholds, swapIO: rates?.swapIOBytes),
            strained: MachineStatus.strained(pressure: pressure, swapMBPerMin: rate), profile: profile.name,
            freezeWarningMBPerMin: profile.freezeSevereMBPerMin,
            topGroups: (processes?.groups ?? []).prefix(5).map { "\($0.group.name): \(Format.bytes($0.footprint))" },
            agentSessions: AIToolBuilder.from(processes ?? .empty).flatMap(\.sessions).map {
                "\($0.tool) (\($0.projectName ?? "?")): \(Format.bytes($0.footprint))"
            },
            windowSeconds: windowSeconds)
    }

    /// Reads the system directly: two VM counter samples one second apart give the swap rate (`window_s: 1`, noisy).
    public static func direct(profile: OptimizationProfile, thresholds: Thresholds, sampleSeconds: TimeInterval = 1) -> MachineStatus? {
        let a = VMCounters.read()
        Thread.sleep(forTimeInterval: sampleSeconds)
        guard let h = SystemReader.snapshot(disk: Disk(total: 0, free: 0)) else { return nil }
        let b = VMCounters.read()
        let rates = a.flatMap { a in b.flatMap { VMRates.between(a, $0, seconds: sampleSeconds) } }
        return make(h, rates: rates, processes: nil, profile: profile, thresholds: thresholds, source: "direct", windowSeconds: sampleSeconds)
    }
}

// MARK: Coordination state

public struct AgentRecord: Codable, Sendable, Hashable {
    public var id: String
    /// Self-declared: "Claude Code", "Codex CLI"... Not authenticated.
    public var tool: String
    public var project: String
    public var task: String?
    /// PID of the MCP process that registered (one per agent session).
    public var pid: Int32
    public var registeredAt: Date
    /// Updated by the MCP process itself every 60 seconds while it lives, and on every call.
    public var lastSeen: Date
    /// Identity (pid + start time) of the MCP process: the agent ends when that exact process is gone.
    public var mcp: ProcessIdentity?
    /// Identity of the MCP process's parent, the agent session itself. Heavy jobs under it keep an expired slot busy.
    public var session: ProcessIdentity?
}

public struct SlotRecord: Codable, Sendable, Hashable {
    public var id: String
    public var agentID: String
    public var kind: String
    public var acquiredAt: Date
    public var expiresAt: Date
    /// Time ran out but a heavy job of the holder's session is still running: not given to anyone, never stopped.
    /// Lease `expired` (or `overdue` after 2 hours) with task `running`.
    public var expiredBusy: Bool?
    /// Heavy jobs seen under the holder's session when the slot was marked busy.
    public var busyWith: [String]?
}

/// How long the holder may keep the slot: `active` within its time; `expired` past it but a heavy job of the holder
/// still runs (not given to anyone); `overdue` the same after the 2-hour total: never stopped, never treated as free,
/// shown in the app for the user to release by hand.
public enum LeaseState: String, Sendable { case active, expired, overdue }

/// The holder's heavy job: `running` (seen under its session), `ended` (session known, no heavy job seen now;
/// may also mean not started yet), `unknown` (session not known or not readable).
public enum TaskState: String, Sendable { case running, ended, unknown }

public extension SlotRecord {
    func lease(now: Date) -> LeaseState {
        if now < expiresAt { return .active }
        return now >= acquiredAt.addingTimeInterval(AgentHub.maxSlotTotal) ? .overdue : .expired
    }
}

public struct QueueEntry: Codable, Sendable, Hashable {
    public var agentID: String
    public var kind: String
    public var since: Date
    /// Last time this agent asked for the slot again, and the retry interval it was given.
    public var lastAsked: Date?
    public var retryAfter: Int?
}

public struct AgentMessage: Codable, Sendable, Hashable {
    public var seq: Int
    public var from: String
    public var to: String?
    public var text: String
    public var at: Date
}

public struct HubState: Codable, Sendable, Hashable {
    public var agents: [AgentRecord] = []
    public var slots: [SlotRecord] = []
    public var queue: [QueueEntry] = []
    public var messages: [AgentMessage] = []
    /// Slot ids released recently, so a second release says `already_released`.
    public var released: [String]? = []
    public var seq = 0
    public init() {}
}

/// Kinds of heavy work that share the heavy-job slot.
public enum HeavyKind: String, CaseIterable, Sendable {
    case xcodeBuild = "xcode_build", swiftBuild = "swift_build", gradle, simulator, docker, npmBuild = "npm_build", tests, other

    public var isHeavy: Bool { self != .other }
}

/// Checks against the real process table. Injected so tests can simulate processes.
public struct HubChecks: Sendable {
    /// Whether this exact process is still running.
    public var isAlive: @Sendable (ProcessIdentity) -> Bool
    /// Heavy jobs running under this process (its descendants). Empty when none, or when the tree cannot be read.
    public var heavyJobsUnder: @Sendable (ProcessIdentity) -> [String]

    public init(isAlive: @escaping @Sendable (ProcessIdentity) -> Bool, heavyJobsUnder: @escaping @Sendable (ProcessIdentity) -> [String]) {
        self.isAlive = isAlive; self.heavyJobsUnder = heavyJobsUnder
    }

    public static let live = HubChecks(
        isAlive: { $0.isSameProcess() },
        heavyJobsUnder: { root in
            guard root.isSameProcess() else { return [] }
            var cache: [String: (String, [String])] = [:]
            let list = ProcessReader.readAll(cache: &cache)
            var children: [Int32: [Int32]] = [:]
            for t in list { children[t.ppid, default: []].append(t.pid) }
            var under: Set<Int32> = []
            var queue = children[root.pid] ?? []
            while let p = queue.popLast(), under.count < 2000 {
                if under.insert(p).inserted { queue.append(contentsOf: children[p] ?? []) }
            }
            // CPU is not known from one read: compilers count as busy (a build is running), Gradle by its arguments.
            let busy = Dictionary(list.map { ($0.pid, 100.0) }, uniquingKeysWith: { a, _ in a })
            return HeavyJobDetector.jobs(list.filter { under.contains($0.pid) }, cpu: busy).map(\.kind)
        })
}

/// Coordination between agents through one JSON file guarded by `flock`. Works without the app running.
/// Folder: ~/Library/Application Support/8GB Vibe/agents (0700), files 0600.
/// Coordination is voluntary: it does not guarantee resources and does not block agents that do not call the tools.
public final class AgentHub: @unchecked Sendable {
    public let directory: URL
    public var checks: HubChecks
    /// Fallback: an agent with no heartbeat for this long is gone even if its process could not be checked.
    public static let agentTimeout: TimeInterval = 10 * 60
    public static let maxAgents = 20
    public static let maxMessages = 200
    public static let maxMessageLength = 500
    /// One acquire or renew gives at most 30 minutes; a slot is held at most 2 hours in total.
    public static let maxSlotTTL: TimeInterval = 30 * 60
    public static let maxSlotTotal: TimeInterval = 2 * 3600
    public static let defaultSlotTTL: TimeInterval = 15 * 60
    /// Retry interval given to queued agents; the head of the queue yields after twice this without asking again.
    public static let queueRetry = 60

    public init(directory: URL, checks: HubChecks = .live) {
        self.directory = directory
        self.checks = checks
    }

    public static var defaultDirectory: URL {
        if let d = ProcessInfo.processInfo.environment["VIBE_AGENTS_DIR"], !d.isEmpty { return URL(fileURLWithPath: d, isDirectory: true) }
        return MeasurementStore.defaultDirectory.deletingLastPathComponent().appendingPathComponent("agents", isDirectory: true)
    }

    var stateFile: URL { directory.appendingPathComponent("state.json") }
    public var statusFile: URL { directory.appendingPathComponent("status.json") }
    public var policyFile: URL { directory.appendingPathComponent("policy.json") }
    var logFile: URL { directory.appendingPathComponent("log.jsonl") }
    /// Written when a damaged state file was set aside; the app shows it in the bell and removes this file.
    public var corruptionNotice: URL { directory.appendingPathComponent("corrupt-notice.txt") }

    // MARK: Locked read-modify-write

    /// Runs `body` with the state locked; writes the state back if `body` changed it.
    @discardableResult
    public func update<T>(now: Date = Date(), _ body: (inout HubState) -> T) -> T {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(directory.appendingPathComponent(".lock").path, O_CREAT | O_RDWR, 0o600)
        if fd >= 0 { flock(fd, LOCK_EX) }
        defer { if fd >= 0 { flock(fd, LOCK_UN); close(fd) } }
        var state = loadState(now: now)
        let before = state
        expire(&state, now: now)
        let result = body(&state)
        if state != before { write(state) }
        return result
    }

    /// Reads without changing anything (for display). A damaged file reads as empty here; `update` sets it aside.
    public func read() -> HubState {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: stateFile), let s = try? dec.decode(HubState.self, from: data) else { return HubState() }
        return s
    }

    /// Loads the state under the lock. A file that exists but cannot be decoded is renamed to state.json.bad-<time>,
    /// logged and reported (never silently overwritten).
    private func loadState(now: Date) -> HubState {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: stateFile) else { return HubState() }
        if let s = try? dec.decode(HubState.self, from: data) { return s }
        let stamp = MinuteRow.iso.string(from: now).replacingOccurrences(of: ":", with: "-")
        let bad = directory.appendingPathComponent("state.json.bad-\(stamp)")
        _ = rename(stateFile.path, bad.path)
        log(agent: "-", tool: "state", detail: "damaged state.json set aside as \(bad.lastPathComponent)", now: now)
        FileManager.default.createFile(atPath: corruptionNotice.path, contents: Data(bad.lastPathComponent.utf8), attributes: [.posixPermissions: 0o600])
        return HubState()
    }

    private func write(_ s: HubState) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(s) else { return }
        let tmp = directory.appendingPathComponent("state.json.tmp")
        FileManager.default.createFile(atPath: tmp.path, contents: data, attributes: [.posixPermissions: 0o600])
        _ = rename(tmp.path, stateFile.path)
    }

    /// Drops agents whose MCP process is gone (or silent past the fallback timeout), with their slots and queue places.
    /// A slot whose time ran out stays as `expired_busy` while a heavy job still runs under its holder's session.
    func expire(_ s: inout HubState, now: Date) {
        let gone = Set(s.agents.filter { a in
            if let m = a.mcp, !checks.isAlive(m) { return true }
            return now.timeIntervalSince(a.lastSeen) > Self.agentTimeout
        }.map(\.id))
        for id in s.slots.filter({ gone.contains($0.agentID) }).map(\.id) { remember(&s, released: id) }
        s.agents.removeAll { gone.contains($0.id) }
        s.slots.removeAll { gone.contains($0.agentID) }
        s.queue.removeAll { gone.contains($0.agentID) }
        for i in s.slots.indices.reversed() where s.slots[i].expiresAt <= now {
            let holder = s.agents.first { $0.id == s.slots[i].agentID }
            let busy = holder?.session.map(checks.heavyJobsUnder) ?? []
            if busy.isEmpty {
                remember(&s, released: s.slots[i].id)
                s.slots.remove(at: i)
            } else if s.slots[i].expiredBusy != true || s.slots[i].busyWith != busy {
                s.slots[i].expiredBusy = true
                s.slots[i].busyWith = busy
            }
        }
    }

    private func remember(_ s: inout HubState, released id: String) {
        var r = s.released ?? []
        r.append(id)
        if r.count > 100 { r.removeFirst(r.count - 100) }
        s.released = r
    }

    // MARK: Policy and status files

    public func loadPolicy() -> AgentPolicy {
        guard let data = try? Data(contentsOf: policyFile), let p = try? JSONDecoder().decode(AgentPolicy.self, from: data) else { return AgentPolicy() }
        return p
    }

    public func savePolicy(_ p: AgentPolicy) { writeFile(policyFile, try? JSONEncoder().encode(p)) }

    public func saveStatus(_ s: MachineStatus) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        writeFile(statusFile, try? enc.encode(s))
    }

    /// The app's status if it is at most `maxAge` seconds old.
    public func freshStatus(maxAge: TimeInterval = 15, now: Date = Date()) -> MachineStatus? {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: statusFile), let s = try? dec.decode(MachineStatus.self, from: data),
              now.timeIntervalSince(s.measuredAt) <= maxAge else { return nil }
        return s
    }

    private func writeFile(_ url: URL, _ data: Data?) {
        guard let data else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let tmp = url.appendingPathExtension("tmp")
        FileManager.default.createFile(atPath: tmp.path, contents: data, attributes: [.posixPermissions: 0o600])
        _ = rename(tmp.path, url.path)
    }

    /// Whether any agent is registered and alive (the app writes status.json only then).
    public func hasActiveAgents(now: Date = Date()) -> Bool {
        read().agents.contains { now.timeIntervalSince($0.lastSeen) <= Self.agentTimeout }
    }

    // MARK: Log

    /// Appends one line per coordination call. Capped at 1 MB (the older half is dropped).
    public func log(agent: String, tool: String, detail: String, now: Date = Date()) {
        let obj: [String: String] = ["at": MinuteRow.iso.string(from: now), "agent": agent, "tool": tool, "detail": String(detail.prefix(300))]
        guard var data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return }
        data.append(0x0A)
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if let size = (try? fm.attributesOfItem(atPath: logFile.path)[.size] as? NSNumber)?.intValue, size > 1 << 20,
           let old = try? Data(contentsOf: logFile) {
            try? old.suffix(old.count / 2).write(to: logFile)
        }
        if !fm.fileExists(atPath: logFile.path) {
            fm.createFile(atPath: logFile.path, contents: data, attributes: [.posixPermissions: 0o600])
        } else if let h = try? FileHandle(forWritingTo: logFile) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        }
    }

    // MARK: Agents

    public enum RegisterResult: Equatable { case ok(AgentRecord), full }

    /// `mcp` and `session`: identities of the MCP process and of its parent (the agent session), when known.
    public func register(tool: String, project: String, task: String?, pid: Int32, mcp: ProcessIdentity? = nil,
                         session: ProcessIdentity? = nil, now: Date = Date()) -> RegisterResult {
        update(now: now) { s in
            // The same MCP process registering again keeps its id.
            if let i = s.agents.firstIndex(where: { $0.pid == pid && $0.tool == tool && $0.mcp == mcp }) {
                s.agents[i].lastSeen = now; s.agents[i].project = project; s.agents[i].task = task
                return .ok(s.agents[i])
            }
            guard s.agents.count < Self.maxAgents else { return .full }
            s.seq += 1
            let r = AgentRecord(id: "a\(s.seq)", tool: String(tool.prefix(40)), project: String(project.prefix(80)),
                                task: task.map { String($0.prefix(200)) }, pid: pid, registeredAt: now, lastSeen: now,
                                mcp: mcp, session: session)
            s.agents.append(r)
            return .ok(r)
        }
    }

    /// Updates the heartbeat. false when the agent is unknown (expired: register again).
    public func heartbeat(_ agentID: String, now: Date = Date()) -> Bool {
        update(now: now) { s in
            guard let i = s.agents.firstIndex(where: { $0.id == agentID }) else { return false }
            s.agents[i].lastSeen = now
            return true
        }
    }

    // MARK: Slots

    public enum SlotResult: Equatable {
        case granted(SlotRecord)
        case alreadyHeld(SlotRecord)
        /// Someone else holds the slot, or someone is ahead in the queue; `position` 1 is next.
        case queued(position: Int, holder: String, secondsLeft: Int)
        case unknownAgent
    }

    /// The queue in its effective order: the head yields its turn when it has not asked again for twice its retry interval.
    public static func eligibleQueue(_ s: HubState, now: Date) -> [QueueEntry] {
        guard let head = s.queue.first else { return [] }
        let stale = now.timeIntervalSince(head.lastAsked ?? head.since) > Double(2 * (head.retryAfter ?? queueRetry))
        return stale ? Array(s.queue.dropFirst()) + [head] : s.queue
    }

    public static func describe(_ s: HubState, _ agentID: String) -> String {
        s.agents.first { $0.id == agentID }.map { "\($0.tool) (\($0.project))" } ?? agentID
    }

    /// Asks for a heavy-job slot. `granted` means "your turn"; it does not mean the Mac has room (see advice).
    public func acquireSlot(_ agentID: String, kind: HeavyKind, ttl: TimeInterval, capacity: Int, now: Date = Date()) -> SlotResult {
        update(now: now) { s in
            guard let ai = s.agents.firstIndex(where: { $0.id == agentID }) else { return .unknownAgent }
            s.agents[ai].lastSeen = now
            if let mine = s.slots.first(where: { $0.agentID == agentID && $0.kind == kind.rawValue }) { return .alreadyHeld(mine) }
            let held = s.slots.filter { HeavyKind(rawValue: $0.kind)?.isHeavy ?? true }
            let firstInQueue = Self.eligibleQueue(s, now: now).first?.agentID
            if !kind.isHeavy || (held.count < capacity && (firstInQueue == nil || firstInQueue == agentID)) {
                s.queue.removeAll { $0.agentID == agentID }
                s.seq += 1
                let slot = SlotRecord(id: "s\(s.seq)", agentID: agentID, kind: kind.rawValue, acquiredAt: now,
                                      expiresAt: now.addingTimeInterval(min(max(60, ttl), Self.maxSlotTTL)))
                s.slots.append(slot)
                return .granted(slot)
            }
            if let i = s.queue.firstIndex(where: { $0.agentID == agentID }) {
                s.queue[i].lastAsked = now; s.queue[i].retryAfter = Self.queueRetry
            } else {
                s.queue.append(QueueEntry(agentID: agentID, kind: kind.rawValue, since: now, lastAsked: now, retryAfter: Self.queueRetry))
            }
            let position = (Self.eligibleQueue(s, now: now).firstIndex { $0.agentID == agentID } ?? 0) + 1
            let first = held.min { $0.expiresAt < $1.expiresAt }
            return .queued(position: position, holder: first.map { Self.describe(s, $0.agentID) } ?? "the queue",
                           secondsLeft: max(0, Int(first?.expiresAt.timeIntervalSince(now) ?? 0)))
        }
    }

    public enum RenewResult: Equatable {
        case renewed(SlotRecord)
        case notOwner
        case notFound
        /// Would go past the 2-hour total; `maxExpiresAt` is the latest allowed end.
        case totalLimit(maxExpiresAt: Date)
    }

    /// Extends a slot by `ttl` from now (at most 30 minutes). Only the holder; at most 2 hours in total.
    public func renewSlot(_ agentID: String, slotID: String, ttl: TimeInterval, now: Date = Date()) -> RenewResult {
        update(now: now) { s in
            guard let i = s.slots.firstIndex(where: { $0.id == slotID }) else { return .notFound }
            guard s.slots[i].agentID == agentID else { return .notOwner }
            let end = now.addingTimeInterval(min(max(60, ttl), Self.maxSlotTTL))
            let limit = s.slots[i].acquiredAt.addingTimeInterval(Self.maxSlotTotal)
            guard end <= limit else { return .totalLimit(maxExpiresAt: limit) }
            s.slots[i].expiresAt = end
            s.slots[i].expiredBusy = nil
            s.slots[i].busyWith = nil
            if let a = s.agents.firstIndex(where: { $0.id == agentID }) { s.agents[a].lastSeen = now }
            return .renewed(s.slots[i])
        }
    }

    public enum ReleaseResult: Equatable { case released, alreadyReleased, notOwner, notFound }

    /// Releases a slot. Only the holder; a second release says `alreadyReleased`.
    public func releaseSlot(_ agentID: String, slotID: String, now: Date = Date()) -> ReleaseResult {
        update(now: now) { s in
            if let i = s.slots.firstIndex(where: { $0.id == slotID }) {
                guard s.slots[i].agentID == agentID else { return .notOwner }
                s.slots.remove(at: i)
                remember(&s, released: slotID)
                return .released
            }
            return (s.released ?? []).contains(slotID) ? .alreadyReleased : .notFound
        }
    }

    /// The user releases a slot by hand in the app (for an overdue slot). Only the reservation is dropped:
    /// no process is touched. Logged.
    public func releaseByUser(slotID: String, now: Date = Date()) -> Bool {
        let done: (Bool, String) = update(now: now) { s in
            guard let i = s.slots.firstIndex(where: { $0.id == slotID }) else { return (false, "") }
            let who = Self.describe(s, s.slots[i].agentID)
            s.slots.remove(at: i)
            remember(&s, released: slotID)
            return (true, who)
        }
        if done.0 { log(agent: "user", tool: "release_by_user", detail: "\(slotID) held by \(done.1); processes untouched", now: now) }
        return done.0
    }

    /// Task state of a slot's holder, read from the process table (or from the busy mark of an expired slot).
    public func task(of slot: SlotRecord, in s: HubState) -> TaskState {
        if slot.expiredBusy == true { return .running }
        guard let session = s.agents.first(where: { $0.id == slot.agentID })?.session else { return .unknown }
        return checks.heavyJobsUnder(session).isEmpty ? .ended : .running
    }

    /// This agent's slots and queue place, to recover after losing context.
    public func mine(_ agentID: String, now: Date = Date()) -> (slots: [SlotRecord], queuePosition: Int?, known: Bool) {
        update(now: now) { s in
            guard s.agents.contains(where: { $0.id == agentID }) else { return ([], nil, false) }
            let pos = Self.eligibleQueue(s, now: now).firstIndex { $0.agentID == agentID }.map { $0 + 1 }
            return (s.slots.filter { $0.agentID == agentID }, pos, true)
        }
    }

    // MARK: Messages

    public func post(from agentID: String, to: String?, text: String, now: Date = Date()) -> AgentMessage? {
        update(now: now) { s in
            guard s.agents.contains(where: { $0.id == agentID }) else { return nil }
            s.seq += 1
            let m = AgentMessage(seq: s.seq, from: agentID, to: to, text: String(text.prefix(Self.maxMessageLength)), at: now)
            s.messages.append(m)
            if s.messages.count > Self.maxMessages { s.messages.removeFirst(s.messages.count - Self.maxMessages) }
            return m
        }
    }

    /// Messages for this agent (broadcast or addressed to it) after `since`.
    public func messages(for agentID: String, since: Int, now: Date = Date()) -> [AgentMessage] {
        update(now: now) { s in s.messages.filter { $0.seq > since && ($0.to == nil || $0.to == agentID) && $0.from != agentID } }
    }
}

// MARK: Advice

public struct CanStartAdvice: Codable, Sendable, Hashable {
    /// "go", "wait", "no" or "unknown".
    public var decision: String
    public var reason: String
    public var retryAfterSeconds: Int?
    /// "low" when part of the data is missing (for example swap not measured yet).
    public var confidence: String?
}

public enum HeavyJobAdvisor {
    /// Advice only: whether a heavy job should start now. Never blocks anything by itself.
    /// - otherHolders: slots held by others; queueAhead: agents waiting before this one; busyHolder: holder of an `expired_busy` slot.
    public static func advise(kind: HeavyKind, status: MachineStatus?, profile: OptimizationProfile,
                              otherHolders: [(holder: String, secondsLeft: Int)], queueAhead: Int = 0,
                              busyHolder: String? = nil, now: Date = Date()) -> CanStartAdvice {
        guard let st = status, st.pressure != nil || st.swapMBPerMin != nil else {
            return CanStartAdvice(decision: "unknown", reason: "No machine data (8GB Vibe status unavailable).", retryAfterSeconds: nil, confidence: nil)
        }
        let swapText = st.swapMBPerMin.map { "swap \(Int($0)) MB/min" } ?? "swap: not measured yet"
        let pressureText = "pressure \(st.pressure ?? "unknown")"
        let confidence: String? = (st.swapMBPerMin == nil || st.pressure == nil) ? "low" : nil
        if st.pressure == "critical" || (st.swapMBPerMin.map { $0 >= profile.freezeSevereMBPerMin } ?? false) {
            return CanStartAdvice(decision: "no", reason: "The Mac is badly short of RAM (\(pressureText), \(swapText)). Close sessions or apps first.",
                                  retryAfterSeconds: 120, confidence: confidence)
        }
        if kind.isHeavy, let busy = busyHolder {
            return CanStartAdvice(decision: "wait", reason: "A heavy job of \(busy) is still running (its slot time is up; after 2 hours it is shown to the user, who may release the slot).",
                                  retryAfterSeconds: 60, confidence: confidence)
        }
        if kind.isHeavy, let h = otherHolders.min(by: { $0.secondsLeft < $1.secondsLeft }) {
            return CanStartAdvice(decision: "wait", reason: "\(h.holder) holds the heavy-job slot (\(h.secondsLeft / 60) min left).",
                                  retryAfterSeconds: min(300, max(30, h.secondsLeft)), confidence: confidence)
        }
        if kind.isHeavy, queueAhead > 0 {
            return CanStartAdvice(decision: "wait", reason: "\(queueAhead) agent(s) are waiting before you; you would be number \(queueAhead + 1).",
                                  retryAfterSeconds: AgentHub.queueRetry, confidence: confidence)
        }
        if kind.isHeavy && (st.pressure == "warning" || (st.swapMBPerMin.map { $0 >= profile.freezeRisingMBPerMin } ?? false)) {
            return CanStartAdvice(decision: "wait", reason: "The Mac is strained (\(pressureText), \(swapText)).",
                                  retryAfterSeconds: 60, confidence: confidence)
        }
        return CanStartAdvice(decision: "go", reason: "\(pressureText.capitalizedFirst), \(swapText), no other heavy job reserved.",
                              retryAfterSeconds: nil, confidence: confidence)
    }

    /// Heavy-job slots that may run at once: one on every Mac. A conservative coordination policy (owner's decision,
    /// 08/11/2026), not a claim that a Mac can only run one heavy job. No setting to raise it in this stage.
    public static func capacity(_ profile: OptimizationProfile) -> Int { 1 }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: Client install

/// Commands and snippets to register `8gbvibe-mcp` with agent clients. The app only runs the Claude Code one,
/// after the user confirms; the others are shown for copying.
public enum MCPInstall {
    public static let serverName = "8gbvibe"

    public static func claudeAdd(claude: String, server: String) -> [String] {
        [claude, "mcp", "add", "--transport", "stdio", "--scope", "user", serverName, "--", server]
    }

    public static func claudeRemove(claude: String) -> [String] {
        [claude, "mcp", "remove", "--scope", "user", serverName]
    }

    /// Shell-quoted command line for display.
    public static func display(_ args: [String]) -> String {
        args.map { $0.contains(" ") ? "'\($0)'" : $0 }.joined(separator: " ")
    }

    public static func codexSnippet(server: String) -> String {
        "[mcp_servers.\(serverName)]\ncommand = \"\(server)\"\nargs = []"
    }

    /// Where the `claude` command lives: a login-shell lookup first, then the usual install places.
    public static func findClaude(home: String = NSHomeDirectory(), fileExists: (String) -> Bool = FileManager.default.isExecutableFile(atPath:),
                                  shellLookup: () -> String? = { MCPInstall.loginShellWhich("claude") }) -> String? {
        if let p = shellLookup(), !p.isEmpty, fileExists(p) { return p }
        let candidates = ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        return candidates.first(where: fileExists)
    }

    public static func loginShellWhich(_ name: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "command -v \(name)"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// For ~/.cursor/mcp.json, ~/.gemini/settings.json and Antigravity's mcp_config.json.
    public static func jsonSnippet(server: String) -> String {
        "{\n  \"mcpServers\": {\n    \"\(serverName)\": { \"command\": \"\(server)\", \"args\": [] }\n  }\n}"
    }
}
