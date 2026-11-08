import Foundation

public struct ProcessRow: Identifiable, Sendable, Hashable {
    public var id: String
    public var pid: Int32
    public var name: String
    public var path: String
    public var kind: Classification
    public var footprint: UInt64?
    /// % CPU (can exceed 100 % when using several cores).
    public var cpu: Double
    public var startDate: Date
}

public struct ItemUsage: Identifiable, Sendable, Hashable {
    public var id: String { "\(group.rawValue)/\(name)" }
    public var group: WorkCategory
    public var name: String
    public var footprint: UInt64
    public var cpu: Double
    public var processCount: Int
    public var earliestStart: Date
    /// Last time CPU use was seen. Only counted from when the app started monitoring.
    public var lastActive: Date
}

public struct GroupUsage: Identifiable, Sendable, Hashable {
    public var id: WorkCategory { group }
    public var group: WorkCategory
    public var footprint: UInt64
    public var cpu: Double
    public var processCount: Int
    public var items: [ItemUsage]
}

public struct ClaudeCodeSession: Identifiable, Sendable, Hashable {
    public var id: String
    public var pid: Int32
    public var startDate: Date
    /// Includes child processes (MCP servers, tools...).
    public var footprint: UInt64
    public var cpu: Double
    public var directory: String?
    public var lastActive: Date

    public var projectName: String {
        guard let t = directory else { return String(localized: "Không rõ thư mục", bundle: .main) }
        return (t as NSString).lastPathComponent
    }
}

/// An open GUI app (read from NSWorkspace on the main thread).
public struct RunningApp: Sendable, Hashable {
    public var pid: Int32
    public var bundleId: String?
    public var name: String
    /// .app bundle path, for example /Applications/Xcode.app
    public var bundlePath: String
    /// The app is frontmost.
    public var isFrontmost: Bool

    public init(pid: Int32, bundleId: String?, name: String, bundlePath: String, isFrontmost: Bool) {
        self.pid = pid; self.bundleId = bundleId; self.name = name
        self.bundlePath = bundlePath; self.isFrontmost = isFrontmost
    }
}

/// Resources one app uses: adds up every process inside its .app bundle (helpers, renderers...).
public struct AppUsage: Identifiable, Sendable, Hashable {
    public var id: String { app.bundlePath }
    public var app: RunningApp
    public var footprint: UInt64
    public var cpu: Double
    public var processCount: Int
    public var startDate: Date
    public var lastActive: Date
    /// Identity of the app's main process, used to quit exactly this app.
    public var identity: ProcessIdentity? = nil
    /// Main processes of further running copies of the same bundle (one row for all of them, RAM counted once).
    public var otherInstances: [ProcessIdentity] = []
}

public struct ProcessSnapshot: Sendable {
    public var timestamp: Date
    public var processes: [ProcessRow]
    public var groups: [GroupUsage]
    public var sessions: [ClaudeCodeSession]
    public var apps: [AppUsage] = []
    public var devServers: [DevServer] = []
    /// CLI agent sessions other than Claude Code (Codex CLI, Gemini CLI...).
    public var agentSessions: [AgentSession] = []
    /// MCP servers inside live agent sessions.
    public var mcpServers: [MCPServer] = []
    /// Agent sessions whose memory keeps growing or is very large.
    public var memoryWarnings: [SessionMemoryWarning] = []
    /// Heavy jobs (builds, tests) running now.
    public var heavyJobs: [HeavyJob] = []
    /// Total footprint of the readable processes.
    public var readableTotal: UInt64
    public var unreadableCount: Int

    public static let empty = ProcessSnapshot(timestamp: .distantPast, processes: [], groups: [], sessions: [], readableTotal: 0, unreadableCount: 0)

    public func item(_ group: WorkCategory, _ name: String) -> ItemUsage? {
        self.groups.first { $0.group == group }?.items.first { $0.name == name }
    }
}

/// Reads and analyzes processes across samples: computes % CPU and tracks last activity.
/// Not thread safe: call from one queue only (the app uses its own serial queue).
public final class ProcessAnalyzer: @unchecked Sendable {
    /// Above this (average % CPU between two samples) a process counts as active.
    public var activityThreshold: Double = 2.0

    private var cache: [String: (String, [String])] = [:]
    private var cpuBefore: [String: UInt64] = [:]
    private var lastSample: Date?
    private var lastActive: [String: Date] = [:]
    private var sessionDirectories: [String: String?] = [:]
    private var devDirectories: [String: String?] = [:]
    private let lineage = LineageTracker()
    private let sessionTrend = TrendHistory()
    private let readWorkingDirectory: (Int32) -> String?
    private let readPorts: (Int32) -> [ListeningPort]
    private let uid: UInt32

    public init(readWorkingDirectory: @escaping (Int32) -> String? = ProcessReader.workingDirectory,
                readPorts: @escaping (Int32) -> [ListeningPort] = PortReader.listeningPorts,
                uid: UInt32 = getuid()) {
        self.readWorkingDirectory = readWorkingDirectory
        self.readPorts = readPorts
        self.uid = uid
    }

    public func run(apps: [RunningApp] = [], now: Date = Date()) -> ProcessSnapshot {
        analyze(ProcessReader.readAll(cache: &cache), apps: apps, now: now)
    }

    public func analyze(_ list: [ProcessRecord], apps: [RunningApp] = [], now: Date) -> ProcessSnapshot {
        let kind = ProcessClassifier.classify(list)

        // % CPU from the CPU time difference between two samples.
        let wall = lastSample.map { now.timeIntervalSince($0) } ?? 0
        var cpu: [Int32: Double] = [:]
        var cpuNow: [String: UInt64] = [:]
        for t in list {
            guard let budget = t.cpuNanos else { continue }
            cpuNow[t.key] = budget
            if wall > 0.5, let before = cpuBefore[t.key], budget >= before {
                cpu[t.pid] = Double(budget - before) / (wall * 1e9) * 100
            }
        }
        cpuBefore = cpuNow
        lastSample = now

        let rows = list.map { t in
            ProcessRow(id: t.key, pid: t.pid,
                             name: t.path.isEmpty ? t.name : (t.path as NSString).lastPathComponent,
                             path: t.path,
                             kind: kind[t.pid] ?? Classification(.other, t.appName),
                             footprint: t.footprint, cpu: cpu[t.pid] ?? 0, startDate: t.startDate)
        }

        // Group by category and item.
        var byItem: [Classification: [ProcessRow]] = [:]
        for h in rows { byItem[h.kind, default: []].append(h) }
        var alive: Set<String> = []
        var itemList: [ItemUsage] = []
        for (classification, items) in byItem {
            let id = "muc:\(classification.group.rawValue)/\(classification.item)"
            alive.insert(id)
            let c = items.reduce(0) { $0 + $1.cpu }
            let last = updateActivity(id, active: c >= activityThreshold, now: now)
            itemList.append(ItemUsage(group: classification.group, name: classification.item,
                                     footprint: items.reduce(0) { $0 + ($1.footprint ?? 0) },
                                     cpu: c, processCount: items.count,
                                     earliestStart: items.map(\.startDate).min() ?? now,
                                     lastActive: last))
        }
        let groupList = Dictionary(grouping: itemList, by: \.group).map { group, items in
            GroupUsage(group: group,
                       footprint: items.reduce(0) { $0 + $1.footprint },
                       cpu: items.reduce(0) { $0 + $1.cpu },
                       processCount: items.reduce(0) { $0 + $1.processCount },
                       items: items.sorted { $0.footprint > $1.footprint })
        }.sorted { $0.footprint > $1.footprint }

        // Claude Code sessions: a claude process whose parent is not claude. The child tree is added up.
        let byPID = Dictionary(list.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        var children: [Int32: [Int32]] = [:]
        for t in list { children[t.ppid, default: []].append(t.pid) }
        var sessions: [ClaudeCodeSession] = []
        for t in list where ProcessClassifier.isClaudeCode(t) {
            if let p = byPID[t.ppid], ProcessClassifier.isClaudeCode(p) { continue }
            var tree: [Int32] = []
            var queue = [t.pid]
            while let x = queue.popLast(), tree.count < 500 {
                tree.append(x)
                queue.append(contentsOf: children[x] ?? [])
            }
            let fp = tree.reduce(UInt64(0)) { $0 + (byPID[$1]?.footprint ?? 0) }
            let c = tree.reduce(0.0) { $0 + (cpu[$1] ?? 0) }
            let id = "phien:\(t.key)"
            alive.insert(id)
            let last = updateActivity(id, active: c >= activityThreshold, now: now)
            if sessionDirectories[t.key] == nil { sessionDirectories[t.key] = .some(readWorkingDirectory(t.pid)) }
            sessions.append(ClaudeCodeSession(id: t.key, pid: t.pid, startDate: t.startDate, footprint: fp, cpu: c,
                                         directory: sessionDirectories[t.key] ?? nil, lastActive: last))
        }
        sessions.sort { $0.startDate < $1.startDate }

        // Assign processes to GUI apps by the longest matching bundle path
        // (Simulator.app lives inside Xcode.app, so the longest bundle must win).
        let bundlesByLength = apps.sorted { $0.bundlePath.count > $1.bundlePath.count }
        var byApp: [String: [ProcessRecord]] = [:]
        for t in list where !t.path.isEmpty {
            if let a = bundlesByLength.first(where: { t.path.hasPrefix($0.bundlePath + "/") }) {
                byApp[a.bundlePath, default: []].append(t)
            }
        }
        var appList: [AppUsage] = []
        // One row per bundle: an app running twice (Chrome with two profiles) has two NSRunningApplications with the
        // same bundle path. Its processes were counted once per copy, giving two identical rows with doubled RAM.
        // The frontmost copy (else the earliest pid) stands for the app; the others are quit together with it.
        var copies: [String: [RunningApp]] = [:]
        for a in apps { copies[a.bundlePath, default: []].append(a) }
        let byPIDAll = Dictionary(list.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        for (path, group) in copies {
            let ordered = group.sorted { ($0.isFrontmost ? 0 : 1, $0.pid) < ($1.isFrontmost ? 0 : 1, $1.pid) }
            let a = ordered[0]
            let others = ordered.dropFirst().compactMap { byPIDAll[$0.pid].map(ProcessIdentity.init) }
            let items = byApp[path] ?? []
            let c = items.reduce(0.0) { $0 + (cpu[$1.pid] ?? 0) }
            let id = "app:\(a.bundlePath)"
            alive.insert(id)
            let last = updateActivity(id, active: c >= activityThreshold || a.isFrontmost, now: now)
            appList.append(AppUsage(app: a, footprint: items.reduce(0) { $0 + ($1.footprint ?? 0) }, cpu: c,
                                     processCount: items.count, startDate: items.map(\.startDate).min() ?? now, lastActive: last,
                                     identity: items.first { $0.pid == a.pid }.map(ProcessIdentity.init), otherInstances: others))
        }
        appList.sort { $0.footprint != $1.footprint ? $0.footprint > $1.footprint : $0.app.bundlePath < $1.app.bundlePath }

        var devKeys: Set<String> = []
        let byPIDForDev = byPID
        // CLI agents other than Claude Code. The working directory is read once per session.
        let agentList = AgentSessionBuilder.from(list, cpu: cpu, directory: { [self] pid in
            guard let t = byPIDForDev[pid] else { return nil }
            devKeys.insert(t.key)
            if devDirectories[t.key] == nil { devDirectories[t.key] = .some(readWorkingDirectory(pid)) }
            return devDirectories[t.key] ?? nil
        }, lastActive: { [self] id, c in
            alive.insert(id)
            return updateActivity(id, active: c >= activityThreshold, now: now)
        })


        // Remember which session each process belongs to, so orphans can tell where they came from.
        var roots: [LineageTracker.Root] = sessions.compactMap { s in
            byPID[s.pid].map { LineageTracker.Root(process: $0, agent: "Claude Code", directory: s.directory, sessionID: s.id) }
        }
        roots += agentList.compactMap { s in
            byPID[s.pid].map { LineageTracker.Root(process: $0, agent: s.tool, directory: s.directory, sessionID: s.id) }
        }
        lineage.update(roots: roots, list: list, now: now)
        let mcpList = MCPBuilder.from(list, cpu: cpu, origin: lineage.origin(of:))

        // Memory trend per agent session (one point per minute, 35 minutes).
        var warnings: [SessionMemoryWarning] = []
        let trendInputs = sessions.map { ($0.id, "Claude Code", $0.directory, $0.footprint) }
            + agentList.map { ($0.id, $0.tool, $0.directory, $0.footprint) }
        for (id, agent, directory, footprint) in trendInputs {
            sessionTrend.add(id, footprint, now: now)
            if let kind = MemoryGrowth.check(sessionTrend.get(id), now: now) {
                warnings.append(SessionMemoryWarning(sessionID: id, agent: agent,
                                                     projectName: directory.map { ($0 as NSString).lastPathComponent },
                                                     footprint: footprint, kind: kind))
            }
        }
        sessionTrend.keep(only: Set(trendInputs.map(\.0)))

        // Dev servers and orphaned processes. Ports are only read for processes worth checking, to stay light.
        var ports: [Int32: [ListeningPort]] = [:]
        for t in list where DevServerBuilder.shouldReadPorts(t, uid: uid) {
            let c = readPorts(t.pid)
            if !c.isEmpty { ports[t.pid] = c }
        }
        let devList = DevServerBuilder.from(list, ports: ports, cpu: cpu, directory: { [self] pid in
            guard let t = byPIDForDev[pid] else { return nil }
            devKeys.insert(t.key)
            if devDirectories[t.key] == nil { devDirectories[t.key] = .some(readWorkingDirectory(pid)) }
            return devDirectories[t.key] ?? nil
        }, lastActive: { [self] id, c in
            alive.insert(id)
            return updateActivity(id, active: c >= activityThreshold, now: now)
        }, origin: lineage.origin(of:))

        lastActive = lastActive.filter { alive.contains($0.key) }
        let sessionKeys = Set(sessions.map(\.id))
        sessionDirectories = sessionDirectories.filter { sessionKeys.contains($0.key) }
        devDirectories = devDirectories.filter { devKeys.contains($0.key) }

        return ProcessSnapshot(
            timestamp: now,
            processes: rows,
            groups: groupList,
            sessions: sessions,
            apps: appList,
            devServers: devList,
            agentSessions: agentList,
            mcpServers: mcpList,
            memoryWarnings: warnings.sorted { $0.footprint > $1.footprint },
            heavyJobs: HeavyJobDetector.jobs(list, cpu: cpu),
            readableTotal: list.reduce(0) { $0 + ($1.footprint ?? 0) },
            unreadableCount: list.filter { $0.footprint == nil }.count
        )
    }

    private func updateActivity(_ id: String, active: Bool, now: Date) -> Date {
        if active || lastActive[id] == nil { lastActive[id] = now }
        return lastActive[id]!
    }
}
