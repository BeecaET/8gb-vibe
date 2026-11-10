import Foundation

/// The agent session a process was started under, remembered while the agent was alive.
/// Lets an orphaned process say where it came from after its agent has exited.
public struct ProcessOrigin: Sendable, Hashable {
    /// Agent name, for example "Claude Code" or "Codex CLI".
    public var agent: String
    /// The session's working directory.
    public var directory: String?
    /// ID of the session (`ClaudeCodeSession.id` or `AgentSession.id`).
    public var sessionID: String
    /// When the session was last seen alive. nil while it is still running.
    public var endedAt: Date?

    public init(agent: String, directory: String?, sessionID: String, endedAt: Date? = nil) {
        self.agent = agent; self.directory = directory; self.sessionID = sessionID; self.endedAt = endedAt
    }

    public var projectName: String? { directory.map { ($0 as NSString).lastPathComponent } }

    /// "Claude Code (shop)".
    public var sessionDescription: String {
        projectName.map { "\(agent) (\($0))" } ?? agent
    }

    /// "Orphaned from the Claude Code session in shop, ended 2 h ago."
    public func orphanNote(now: Date) -> String {
        let session = projectName.map { String(localized: "the \(agent) session in \($0)", bundle: .main) }
            ?? String(localized: "the \(agent) session", bundle: .main)
        guard let end = endedAt else { return String(localized: "Orphaned from \(session).", bundle: .main) }
        return String(localized: "Orphaned from \(session), which ended \(Format.duration(max(0, now.timeIntervalSince(end)))) ago.", bundle: .main)
    }
}

/// Remembers which agent session each process belongs to, across samples.
/// Not thread safe: used only from `ProcessAnalyzer` on its own queue.
public final class LineageTracker: @unchecked Sendable {
    /// Process key (`ProcessRecord.key`) -> origin.
    private var origins: [String: ProcessOrigin] = [:]
    /// Session ID -> last time it was seen alive.
    private var lastSeen: [String: Date] = [:]

    public init() {}

    /// A live agent session and its root process.
    public struct Root {
        public var process: ProcessRecord
        public var agent: String
        public var directory: String?
        public var sessionID: String
        public init(process: ProcessRecord, agent: String, directory: String?, sessionID: String) {
            self.process = process; self.agent = agent; self.directory = directory; self.sessionID = sessionID
        }
    }

    /// Records every descendant of the live sessions, then drops entries of processes that have exited.
    public func update(roots: [Root], list: [ProcessRecord], now: Date) {
        var children: [Int32: [ProcessRecord]] = [:]
        for t in list { children[t.ppid, default: []].append(t) }
        for r in roots {
            lastSeen[r.sessionID] = now
            let origin = ProcessOrigin(agent: r.agent, directory: r.directory, sessionID: r.sessionID)
            var queue = children[r.process.pid] ?? []
            var count = 0
            while let t = queue.popLast(), count < 1000 {
                count += 1
                origins[t.key] = origin
                queue.append(contentsOf: children[t.pid] ?? [])
            }
        }
        let alive = Set(list.map(\.key))
        origins = origins.filter { alive.contains($0.key) }
        let referenced = Set(origins.values.map(\.sessionID)).union(roots.map(\.sessionID))
        lastSeen = lastSeen.filter { referenced.contains($0.key) }
        liveSessions = Set(roots.map(\.sessionID))
    }

    private var liveSessions: Set<String> = []

    /// Origin of a process, with `endedAt` filled in when its session is no longer running.
    public func origin(of t: ProcessRecord) -> ProcessOrigin? {
        guard var o = origins[t.key] else { return nil }
        if !liveSessions.contains(o.sessionID) { o.endedAt = lastSeen[o.sessionID] }
        return o
    }
}

/// One MCP server process tree started by an agent session.
public struct MCPServer: Identifiable, Sendable, Hashable {
    public var id: String
    public var pid: Int32
    /// Short name, for example "playwright", "filesystem".
    public var name: String
    /// Includes child processes (for example the browser Playwright starts).
    public var footprint: UInt64
    public var cpu: Double
    /// Session that runs it, if known.
    public var origin: ProcessOrigin?
}

/// MCP servers grouped by name, for "the same MCP runs N times" warnings.
public struct MCPDuplicate: Identifiable, Sendable, Hashable {
    public var id: String { name }
    public var name: String
    public var count: Int
    public var footprint: UInt64
}

public enum MCPDetector {
    /// MCP server name from a process, or nil if it is not an MCP server.
    public static func name(_ t: ProcessRecord) -> String? {
        let args = DevProcessClassifier.arguments(t)
        let candidates = (args.isEmpty ? [t.path] : args)
        for (i, a) in candidates.enumerated() {
            if a == "-m", i + 1 < candidates.count, let n = normalized(candidates[i + 1]) { return n }
            if a.hasPrefix("-") { continue }
            if let r = a.range(of: "@modelcontextprotocol/server-") {
                let rest = a[r.upperBound...].split(separator: "/").first.map(String.init) ?? ""
                return rest.isEmpty ? "mcp" : rest.lowercased()
            }
            if a.contains("@playwright/mcp") { return "playwright" }
            // Package right after node_modules, for example node_modules/@upstash/context7-mcp/dist/index.js.
            if let r = a.range(of: "node_modules/", options: .backwards) {
                let parts = a[r.upperBound...].split(separator: "/").map(String.init)
                let package = parts.first?.hasPrefix("@") == true && parts.count > 1 ? parts[1] : parts.first
                if let p = package, let n = normalized(p) { return n }
            }
            if let n = normalized(DevProcessClassifier.commandName(a)) { return n }
        }
        return nil
    }

    /// "mcp-server-fetch", "context7-mcp", "github-mcp-server", "mcp_server_git" -> "fetch", "context7", "github", "git".
    static func normalized(_ raw: String) -> String? {
        let s = raw.lowercased()
        let marked = s.hasPrefix("mcp-") || s.hasPrefix("mcp_") || s.hasSuffix("-mcp") || s.hasSuffix("_mcp")
            || s.hasSuffix("-mcp-server") || s.contains("mcp-server") || s.contains("mcp_server")
        guard marked else { return nil }
        var n = s
        for p in ["mcp-server-", "mcp_server_", "mcp-", "mcp_"] where n.hasPrefix(p) { n = String(n.dropFirst(p.count)); break }
        for x in ["-mcp-server", "-mcp", "_mcp", "-server"] where n.hasSuffix(x) { n = String(n.dropLast(x.count)); break }
        return n.isEmpty ? "mcp" : n
    }
}

public enum MCPBuilder {
    /// MCP servers inside live agent sessions: the topmost MCP process of each tree, with its children added up.
    public static func from(_ list: [ProcessRecord], cpu: [Int32: Double],
                            origin: (ProcessRecord) -> ProcessOrigin?) -> [MCPServer] {
        let byPID = Dictionary(list.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        var children: [Int32: [Int32]] = [:]
        for t in list { children[t.ppid, default: []].append(t.pid) }
        var result: [MCPServer] = []
        for t in list {
            guard let name = MCPDetector.name(t), let o = origin(t), o.endedAt == nil else { continue }
            if let p = byPID[t.ppid], MCPDetector.name(p) != nil { continue }
            var tree: [Int32] = []
            var queue = [t.pid]
            while let x = queue.popLast(), tree.count < 300 {
                tree.append(x)
                queue.append(contentsOf: children[x] ?? [])
            }
            result.append(MCPServer(id: "mcp:\(t.key)", pid: t.pid, name: name,
                                    footprint: tree.reduce(0) { $0 + (byPID[$1]?.footprint ?? 0) },
                                    cpu: tree.reduce(0) { $0 + (cpu[$1] ?? 0) }, origin: o))
        }
        return result.sorted { $0.footprint > $1.footprint }
    }

    /// MCP servers running more than once (usually one copy per agent session).
    public static func duplicates(_ list: [MCPServer]) -> [MCPDuplicate] {
        Dictionary(grouping: list, by: \.name)
            .filter { $0.value.count > 1 }
            .map { MCPDuplicate(name: $0.key, count: $0.value.count, footprint: $0.value.reduce(0) { $0 + $1.footprint }) }
            .sorted { $0.footprint > $1.footprint }
    }
}
