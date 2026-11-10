import Foundation

// MARK: Agent clients on this Mac

/// Agent apps that can use 8GB Vibe's MCP server. Paths and commands come from each client's official docs
/// (see docs/MCP.md, section 8). Detection only checks that files exist; it never runs a client.
public enum MCPClientKind: String, CaseIterable, Sendable, Identifiable {
    case claudeCode, codex, geminiCLI, cursor, claudeDesktop, antigravity
    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .geminiCLI: return "Gemini CLI"
        case .cursor: return "Cursor"
        case .claudeDesktop: return "Claude Desktop"
        case .antigravity: return "Antigravity"
        }
    }

    /// Lowercased prefixes of the self-declared `tool` names agents use in `register_agent`.
    public var agentNames: [String] {
        switch self {
        case .claudeCode: return ["claude code"]
        case .codex: return ["codex"]
        case .geminiCLI: return ["gemini"]
        case .cursor: return ["cursor"]
        case .claudeDesktop: return ["claude desktop"]
        case .antigravity: return ["antigravity"]
        }
    }
}

/// How 8GB Vibe adds or removes its entry for one client.
public enum MCPInstallMethod: Equatable, Sendable {
    /// The client's own command (`claude mcp add`, `codex mcp add`, `gemini mcp add`). Preferred.
    case command(add: [String], remove: [String])
    /// Edit a JSON file: only the key "8gbvibe" inside "mcpServers".
    case json(URL)
    /// Edit Codex's TOML file: only the table [mcp_servers.8gbvibe] (when the codex command is not found).
    case toml(URL)
}

public struct MCPClient: Identifiable, Equatable, Sendable {
    public var kind: MCPClientKind
    public var id: String { kind.rawValue }
    /// The file where the client keeps user-level MCP servers (read to show the state).
    public var configFile: URL
    public var method: MCPInstallMethod
    /// Shown after install or removal when the client only reads its config at start.
    public var reopenHint: Bool
}

public enum MCPConfigState: Equatable, Sendable {
    case notInstalled
    case installed
    /// The config file exists but could not be read or parsed (`corrupt`, `notAnObject`...). Nothing is written to it.
    case unreadable(MCPConfigError)
}

/// What exists on disk, injected so tests use a fake HOME.
public struct MCPProbe: Sendable {
    public var home: String
    public var exists: @Sendable (String) -> Bool
    public var isExecutable: @Sendable (String) -> Bool
    /// `command -v <name>` in a login shell, or nil.
    public var which: @Sendable (String) -> String?
    /// Shared command folders searched besides the login shell's PATH (none in tests).
    public var systemBins: [String]

    public init(home: String, exists: @escaping @Sendable (String) -> Bool, isExecutable: @escaping @Sendable (String) -> Bool,
                which: @escaping @Sendable (String) -> String?, systemBins: [String] = ["/opt/homebrew/bin", "/usr/local/bin"]) {
        self.home = home; self.exists = exists; self.isExecutable = isExecutable; self.which = which; self.systemBins = systemBins
    }

    public static let live = MCPProbe(home: NSHomeDirectory(),
                                      exists: { FileManager.default.fileExists(atPath: $0) },
                                      isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
                                      which: { MCPInstall.loginShellWhich($0) })

    /// A test probe: everything under `home` is real files; no shell lookup unless given.
    public static func fake(home: String, which: [String: String] = [:]) -> MCPProbe {
        MCPProbe(home: home, exists: { FileManager.default.fileExists(atPath: $0) },
                 isExecutable: { FileManager.default.isExecutableFile(atPath: $0) }, which: { which[$0] }, systemBins: [])
    }

    func find(_ name: String, candidates: [String]) -> String? {
        if let p = which(name), !p.isEmpty, isExecutable(p) { return p }
        return (systemBins.map { "\($0)/\(name)" } + candidates).first(where: isExecutable)
    }
}

public enum MCPClients {
    public static let key = MCPInstall.serverName

    /// The clients present on this Mac, in a fixed order. `appsRoot` is "/Applications" (tests pass a fake one).
    public static func detect(server: String, probe: MCPProbe = .live, appsRoot: String = "/Applications") -> [MCPClient] {
        let h = probe.home
        func app(_ name: String) -> Bool { probe.exists("\(appsRoot)/\(name).app") || probe.exists("\(h)/Applications/\(name).app") }
        func url(_ p: String) -> URL { URL(fileURLWithPath: p) }
        var list: [MCPClient] = []

        // Claude Code: `claude mcp add --scope user`; user servers live in ~/.claude.json (top-level "mcpServers").
        if let claude = probe.find("claude", candidates: ["\(h)/.local/bin/claude", "\(h)/.claude/local/claude"]) {
            list.append(MCPClient(kind: .claudeCode, configFile: url("\(h)/.claude.json"),
                                  method: .command(add: MCPInstall.claudeAdd(claude: claude, server: server), remove: MCPInstall.claudeRemove(claude: claude)),
                                  reopenHint: true))
        }
        // Codex: `codex mcp add <name> -- <command>`; also bundled in ChatGPT.app. Config ~/.codex/config.toml.
        let codexConfig = "\(h)/.codex/config.toml"
        if let codex = probe.find("codex", candidates: ["\(h)/.local/bin/codex",
                                                        "\(appsRoot)/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"]) {
            list.append(MCPClient(kind: .codex, configFile: url(codexConfig),
                                  method: .command(add: [codex, "mcp", "add", key, "--", server], remove: [codex, "mcp", "remove", key]), reopenHint: true))
        } else if probe.exists(codexConfig) {
            list.append(MCPClient(kind: .codex, configFile: url(codexConfig), method: .toml(url(codexConfig)), reopenHint: true))
        }
        // Gemini CLI: `gemini mcp add -s user`; default scope is project, so the flag is required.
        if let gemini = probe.find("gemini", candidates: ["\(h)/.local/bin/gemini"]) {
            list.append(MCPClient(kind: .geminiCLI, configFile: url("\(h)/.gemini/settings.json"),
                                  method: .command(add: [gemini, "mcp", "add", "-s", "user", key, server], remove: [gemini, "mcp", "remove", "-s", "user", key]),
                                  reopenHint: true))
        }
        // Cursor: ~/.cursor/mcp.json.
        if app("Cursor") || probe.exists("\(h)/.cursor") {
            let f = "\(h)/.cursor/mcp.json"
            list.append(MCPClient(kind: .cursor, configFile: url(f), method: .json(url(f)), reopenHint: true))
        }
        // Claude Desktop: ~/Library/Application Support/Claude/claude_desktop_config.json; needs a full restart.
        if app("Claude") {
            let f = "\(h)/Library/Application Support/Claude/claude_desktop_config.json"
            list.append(MCPClient(kind: .claudeDesktop, configFile: url(f), method: .json(url(f)), reopenHint: true))
        }
        // Antigravity (app and CLI): ~/.gemini/config/mcp_config.json.
        let agConfig = "\(h)/.gemini/config/mcp_config.json"
        if app("Antigravity") || probe.exists(agConfig) {
            list.append(MCPClient(kind: .antigravity, configFile: url(agConfig), method: .json(url(agConfig)), reopenHint: true))
        }
        return list
    }

    /// Whether 8GB Vibe's entry is in the client's config file. Only reads.
    public static func state(_ c: MCPClient) -> MCPConfigState {
        let path = c.configFile.path
        guard FileManager.default.fileExists(atPath: path) else { return .notInstalled }
        guard let data = FileManager.default.contents(atPath: path), let text = String(data: data, encoding: .utf8) else {
            return .unreadable(.corrupt)
        }
        if c.kind == .codex {
            return TOMLServerEdit.contains(text) ? .installed : .notInstalled
        }
        do { return try JSONServerEdit.contains(text) ? .installed : .notInstalled }
        catch { return .unreadable(error as? MCPConfigError ?? .corrupt) }
    }

    /// The entry written into JSON configs.
    public static func entry(server: String) -> [String: Any] { ["command": server, "args": [String]()] }

    /// Agents connected through MCP that declared this client's name (self-declared, not authenticated).
    public static func connected(_ kind: MCPClientKind, in state: HubState) -> [AgentRecord] {
        state.agents.filter { a in kind.agentNames.contains { a.tool.lowercased().hasPrefix($0) } }
    }
}

// MARK: JSON edit that keeps everything else

public enum MCPConfigError: Error, Equatable, Sendable {
    case corrupt
    case notAnObject
    case serversNotAnObject
    case alreadyPresent
    case notPresent
    case verifyFailed
}

/// Adds or removes one key inside "mcpServers" by editing the text in place: every other byte of the file stays
/// as it was (spacing, order, other servers). The result is parsed again and compared before it is used.
public enum JSONServerEdit {
    public static let key = MCPInstall.serverName

    static func parse(_ text: String) throws -> [String: Any] {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [:] }
        guard let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) else { throw MCPConfigError.corrupt }
        guard let dict = obj as? [String: Any] else { throw MCPConfigError.notAnObject }
        return dict
    }

    public static func contains(_ text: String) throws -> Bool {
        let d = try parse(text)
        guard let s = d["mcpServers"] else { return false }
        guard let servers = s as? [String: Any] else { throw MCPConfigError.serversNotAnObject }
        return servers[key] != nil
    }

    /// Pretty text for the entry, indented to `indent` (the entry's own line).
    static func entryText(_ entry: [String: Any], indent: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: entry, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        let lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
        return lines.enumerated().map { $0.offset == 0 ? $0.element : indent + $0.element }.joined(separator: "\n")
    }

    public static func add(_ text: String, entry: [String: Any]) throws -> String {
        let before = try parse(text)
        if let s = before["mcpServers"], !(s is [String: Any]) { throw MCPConfigError.serversNotAnObject }
        if (before["mcpServers"] as? [String: Any])?[key] != nil { throw MCPConfigError.alreadyPresent }
        var result: String
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result = "{\n  \"mcpServers\": {\n    \"\(key)\": \(entryText(entry, indent: "    "))\n  }\n}\n"
        } else {
            let chars = Array(text.utf16)
            var scanner = JSONScanner(chars)
            let root = try scanner.object(at: scanner.skipSpace(0))
            if let servers = root.members.first(where: { $0.key == "mcpServers" }) {
                let inner = try scanner.object(at: servers.valueStart)
                result = insert(into: inner, chars: chars, member: "\"\(key)\": ", entry: entry, childIndentFallback: indentOf(servers.keyStart, chars) + "  ")
            } else {
                let rootIndent = root.members.first.map { indentOf($0.keyStart, chars) } ?? "  "
                let block = "{\n\(rootIndent)  \"\(key)\": \(entryText(entry, indent: rootIndent + "  "))\n\(rootIndent)}"
                result = insertRaw(into: root, chars: chars, member: "\"mcpServers\": " + block, childIndentFallback: "  ")
            }
        }
        try verify(before: before, after: result, added: true)
        return result
    }

    public static func remove(_ text: String) throws -> String {
        let before = try parse(text)
        guard let servers = before["mcpServers"] as? [String: Any], servers[key] != nil else { throw MCPConfigError.notPresent }
        let chars = Array(text.utf16)
        var scanner = JSONScanner(chars)
        let root = try scanner.object(at: scanner.skipSpace(0))
        guard let s = root.members.first(where: { $0.key == "mcpServers" }) else { throw MCPConfigError.notPresent }
        let inner = try scanner.object(at: s.valueStart)
        guard let i = inner.members.firstIndex(where: { $0.key == key }) else { throw MCPConfigError.notPresent }
        let result = String(decoding: removing(member: i, of: inner, in: chars), as: UTF16.self)
        try verify(before: before, after: result, added: false)
        return result
    }

    /// Text without member `i` of `obj`: the exact inverse of `insertRaw`.
    static func removing(member i: Int, of obj: JSONScanner.Object, in chars: [UInt16]) -> [UInt16] {
        let m = obj.members[i]
        let range: Range<Int>
        if obj.members.count == 1 {
            range = (obj.open + 1)..<obj.close                     // leaves "{}"
        } else if i > 0 {
            range = obj.members[i - 1].valueEnd..<m.valueEnd       // from the comma after the previous value
        } else {
            range = m.keyStart..<obj.members[1].keyStart           // through the comma and space before the next key
        }
        var out = chars
        out.replaceSubrange(range, with: [])
        return out
    }

    /// Removes an empty "mcpServers" member (one that 8GB Vibe added). Returns nil when it is not there or not empty.
    public static func removeEmptyServers(_ text: String) -> String? {
        guard let d = try? parse(text), let s = d["mcpServers"] as? [String: Any], s.isEmpty else { return nil }
        let chars = Array(text.utf16)
        var scanner = JSONScanner(chars)
        guard let root = try? scanner.object(at: scanner.skipSpace(0)),
              let i = root.members.firstIndex(where: { $0.key == "mcpServers" }) else { return nil }
        let out = String(decoding: removing(member: i, of: root, in: chars), as: UTF16.self)
        guard var after = try? parse(out), after["mcpServers"] == nil else { return nil }
        var b = d
        b["mcpServers"] = nil; after["mcpServers"] = nil
        return NSDictionary(dictionary: after).isEqual(to: b) ? out : nil
    }

    /// The edit changed only our key: everything else parses to the same value.
    static func verify(before: [String: Any], after: String, added: Bool) throws {
        guard var a = try? parse(after) else { throw MCPConfigError.verifyFailed }
        var b = before
        var sa = a["mcpServers"] as? [String: Any] ?? [:]
        var sb = b["mcpServers"] as? [String: Any] ?? [:]
        guard (sa[key] != nil) == added else { throw MCPConfigError.verifyFailed }
        sa[key] = nil; sb[key] = nil
        if b["mcpServers"] == nil, added, sa.isEmpty { a["mcpServers"] = nil } else { a["mcpServers"] = sa; b["mcpServers"] = sb }
        guard NSDictionary(dictionary: a).isEqual(to: b) else { throw MCPConfigError.verifyFailed }
    }

    static func indentOf(_ pos: Int, _ chars: [UInt16]) -> String {
        var i = pos
        while i > 0, chars[i - 1] == 0x20 || chars[i - 1] == 0x09 { i -= 1 }
        return String(decoding: chars[i..<pos], as: UTF16.self)
    }

    static func insert(into obj: JSONScanner.Object, chars: [UInt16], member: String, entry: [String: Any], childIndentFallback: String) -> String {
        let indent = obj.members.last.map { indentOf($0.keyStart, chars) } ?? childIndentFallback
        return insertRaw(into: obj, chars: chars, member: member + entryText(entry, indent: indent), childIndentFallback: childIndentFallback)
    }

    /// Inserts `member` after the last member (or into an empty object), on its own line with the siblings' indent.
    static func insertRaw(into obj: JSONScanner.Object, chars: [UInt16], member: String, childIndentFallback: String) -> String {
        var out = chars
        if let last = obj.members.last {
            let indent = indentOf(last.keyStart, chars)
            let piece = ",\n" + indent + member
            out.insert(contentsOf: Array(piece.utf16), at: last.valueEnd)
        } else {
            let closeIndent = indentOf(obj.open, chars)
            let childIndent = closeIndent + (childIndentFallback.isEmpty ? "  " : String(childIndentFallback.suffix(2)))
            let piece = "\n" + childIndent + member + "\n" + closeIndent
            out.replaceSubrange((obj.open + 1)..<obj.close, with: Array(piece.utf16))
        }
        return String(decoding: out, as: UTF16.self)
    }
}

/// Finds members of JSON objects by position (UTF-16 offsets). Only used on text that already parsed as JSON.
struct JSONScanner {
    struct Member { var key: String; var keyStart: Int; var valueStart: Int; var valueEnd: Int }
    struct Object { var open: Int; var close: Int; var members: [Member] }

    let c: [UInt16]
    init(_ chars: [UInt16]) { c = chars }

    func skipSpace(_ i: Int) -> Int {
        var i = i
        while i < c.count, [0x20, 0x09, 0x0A, 0x0D].contains(c[i]) { i += 1 }
        return i
    }

    /// End (exclusive) of the string starting at `i` (a quote).
    func stringEnd(_ i: Int) throws -> Int {
        var j = i + 1
        while j < c.count {
            if c[j] == 0x5C { j += 2; continue }
            if c[j] == 0x22 { return j + 1 }
            j += 1
        }
        throw MCPConfigError.corrupt
    }

    /// End (exclusive) of any value starting at `i`.
    func valueEnd(_ i: Int) throws -> Int {
        guard i < c.count else { throw MCPConfigError.corrupt }
        switch c[i] {
        case 0x22: return try stringEnd(i)
        case 0x7B, 0x5B:
            var depth = 0, j = i
            while j < c.count {
                switch c[j] {
                case 0x22: j = try stringEnd(j); continue
                case 0x7B, 0x5B: depth += 1
                case 0x7D, 0x5D: depth -= 1; if depth == 0 { return j + 1 }
                default: break
                }
                j += 1
            }
            throw MCPConfigError.corrupt
        default:
            var j = i
            while j < c.count, ![0x2C, 0x7D, 0x5D, 0x20, 0x09, 0x0A, 0x0D].contains(c[j]) { j += 1 }
            return j
        }
    }

    mutating func object(at i: Int) throws -> Object {
        guard i < c.count, c[i] == 0x7B else { throw MCPConfigError.notAnObject }
        var members: [Member] = []
        var j = skipSpace(i + 1)
        while j < c.count, c[j] != 0x7D {
            guard c[j] == 0x22 else { throw MCPConfigError.corrupt }
            let kStart = j
            let kEnd = try stringEnd(j)
            let raw = String(decoding: c[j..<kEnd], as: UTF16.self)
            let key = (try? JSONSerialization.jsonObject(with: Data(raw.utf8), options: .fragmentsAllowed)) as? String ?? ""
            j = skipSpace(kEnd)
            guard j < c.count, c[j] == 0x3A else { throw MCPConfigError.corrupt }
            let vStart = skipSpace(j + 1)
            let vEnd = try valueEnd(vStart)
            members.append(Member(key: key, keyStart: kStart, valueStart: vStart, valueEnd: vEnd))
            j = skipSpace(vEnd)
            if j < c.count, c[j] == 0x2C { j = skipSpace(j + 1) }
        }
        guard j < c.count else { throw MCPConfigError.corrupt }
        return Object(open: i, close: j, members: members)
    }
}

// MARK: TOML (Codex) edit, only when the codex command is missing

public enum TOMLServerEdit {
    public static let header = "[mcp_servers.\(MCPInstall.serverName)]"

    static func isOurHeader(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        let k = MCPInstall.serverName
        return t == "[mcp_servers.\(k)]" || t == "[mcp_servers.\"\(k)\"]" || t.hasPrefix("[mcp_servers.\(k).") || t.hasPrefix("[mcp_servers.\"\(k)\".")
    }

    public static func contains(_ text: String) -> Bool { text.components(separatedBy: "\n").contains(where: isOurHeader) }

    public static func block(server: String) -> String {
        let escaped = server.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\(header)\ncommand = \"\(escaped)\"\nargs = []\n"
    }

    public static func add(_ text: String, server: String) throws -> String {
        guard !contains(text) else { throw MCPConfigError.alreadyPresent }
        var t = text
        if !t.isEmpty && !t.hasSuffix("\n") { t += "\n" }
        if !t.isEmpty { t += "\n" }
        return t + block(server: server)
    }

    /// Removes our table and its sub-tables, up to the next other table header. Everything else stays.
    public static func remove(_ text: String) throws -> String {
        guard contains(text) else { throw MCPConfigError.notPresent }
        var out: [String] = []
        var skipping = false
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if isOurHeader(line) { skipping = true; continue }
            if skipping, t.hasPrefix("[") { skipping = false }
            if !skipping { out.append(line) }
        }
        // Drop one blank line left where the block was, at the end.
        while out.count > 1, out[out.count - 1].isEmpty, out[out.count - 2].isEmpty { out.removeLast() }
        return out.joined(separator: "\n")
    }
}

// MARK: Safe write

public enum ConfigFileWriter {
    /// Backs up the file (`<name>.bak-8gbvibe-<yyyyMMdd-HHmmss>`, same permissions), writes the new text to a
    /// temporary file in the same folder and renames it over the original (atomic). Keeps the original permissions.
    /// Follows a symlink to its target. Returns the backup URL (nil when the file did not exist).
    @discardableResult
    public static func write(_ text: String, to url: URL, now: Date = Date()) throws -> URL? {
        let fm = FileManager.default
        let target = url.resolvingSymlinksInPath()
        let dir = target.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) { try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        var perms: NSNumber = 0o600
        var backup: URL?
        if fm.fileExists(atPath: target.path) {
            perms = (try? fm.attributesOfItem(atPath: target.path)[.posixPermissions] as? NSNumber) ?? 0o600
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyyMMdd-HHmmss"
            let b = dir.appendingPathComponent("\(target.lastPathComponent).bak-8gbvibe-\(f.string(from: now))")
            if fm.fileExists(atPath: b.path) { try fm.removeItem(at: b) }
            try fm.copyItem(at: target, to: b)
            try fm.setAttributes([.posixPermissions: perms], ofItemAtPath: b.path)
            backup = b
        }
        let tmp = dir.appendingPathComponent(".\(target.lastPathComponent).8gbvibe-tmp")
        guard fm.createFile(atPath: tmp.path, contents: Data(text.utf8), attributes: [.posixPermissions: perms]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard rename(tmp.path, target.path) == 0 else {
            try? fm.removeItem(at: tmp)
            throw CocoaError(.fileWriteUnknown)
        }
        return backup
    }
}

/// Adds or removes 8GB Vibe in a file-based client config. Command-based clients are run by the app.
public enum MCPFileInstaller {
    public enum Outcome: Equatable { case done(backup: URL?) }

    /// What a config file looked like before 8GB Vibe installed into it, so removal can give back the same bytes.
    public enum Origin: String, Codable, Sendable {
        /// The file did not exist.
        case noFile
        /// The file was empty (only whitespace); its exact text is kept in the ledger.
        case emptyFile
        /// The file had no "mcpServers"; 8GB Vibe added it.
        case createdServers
        /// "mcpServers" was already there.
        case existingServers
    }

    struct LedgerEntry: Codable { var origin: Origin; var text: String? }

    /// ~/Library/Application Support/8GB Vibe/mcp-installs.json (0600): config path -> origin at install time.
    public static var defaultLedger: URL {
        MeasurementStore.defaultDirectory.deletingLastPathComponent().appendingPathComponent("mcp-installs.json")
    }

    static func loadLedger(_ url: URL) -> [String: LedgerEntry] {
        guard let d = FileManager.default.contents(atPath: url.path) else { return [:] }
        return (try? JSONDecoder().decode([String: LedgerEntry].self, from: d)) ?? [:]
    }

    static func saveLedger(_ l: [String: LedgerEntry], _ url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        guard let d = try? JSONEncoder().encode(l) else { return }
        FileManager.default.createFile(atPath: url.path, contents: d, attributes: [.posixPermissions: 0o600])
    }

    /// The text that would be written, for the confirmation dialog.
    public static func preview(_ c: MCPClient, server: String) -> String {
        switch c.method {
        case .toml: return TOMLServerEdit.block(server: server)
        default: return "\"\(MCPInstall.serverName)\": " + JSONServerEdit.entryText(MCPClients.entry(server: server), indent: "")
        }
    }

    public static func apply(_ c: MCPClient, install: Bool, server: String, now: Date = Date(), ledger: URL = defaultLedger) throws -> Outcome {
        let url: URL
        let isTOML: Bool
        switch c.method {
        case let .json(u): url = u; isTOML = false
        case let .toml(u): url = u; isTOML = true
        case .command: throw MCPConfigError.verifyFailed
        }
        let fm = FileManager.default
        let path = url.resolvingSymlinksInPath().path
        let existed = fm.fileExists(atPath: url.path)
        var text = ""
        if existed {
            guard let d = fm.contents(atPath: url.path), let t = String(data: d, encoding: .utf8) else { throw MCPConfigError.corrupt }
            text = t
        } else if !install {
            throw MCPConfigError.notPresent
        }
        var book = loadLedger(ledger)
        if isTOML {
            let new = install ? try TOMLServerEdit.add(text, server: server) : try TOMLServerEdit.remove(text)
            return .done(backup: try ConfigFileWriter.write(new, to: url, now: now))
        }
        if install {
            let blank = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let origin: Origin = !existed ? .noFile : blank ? .emptyFile
                : ((try? JSONServerEdit.parse(text))?["mcpServers"] == nil ? .createdServers : .existingServers)
            let new = try JSONServerEdit.add(text, entry: MCPClients.entry(server: server))
            let backup = try ConfigFileWriter.write(new, to: url, now: now)
            book[path] = LedgerEntry(origin: origin, text: origin == .emptyFile ? text : nil)
            saveLedger(book, ledger)
            return .done(backup: backup)
        }
        var new = try JSONServerEdit.remove(text)
        // Give back the bytes from before the install when only what 8GB Vibe added is left.
        if let entry = book[path], entry.origin != .existingServers, let trimmed = JSONServerEdit.removeEmptyServers(new) {
            switch entry.origin {
            case .createdServers: new = trimmed
            case .emptyFile, .noFile:
                if (try? JSONServerEdit.parse(trimmed))?.isEmpty == true { new = entry.text ?? "" }
            case .existingServers: break
            }
        }
        let backup = try ConfigFileWriter.write(new, to: url, now: now)
        if entry(book, path)?.origin == .noFile, new.isEmpty {
            // 8GB Vibe created this file and nothing else is in it: remove it (the backup stays).
            try? fm.removeItem(atPath: path)
        }
        book[path] = nil
        saveLedger(book, ledger)
        return .done(backup: backup)
    }

    private static func entry(_ book: [String: LedgerEntry], _ path: String) -> LedgerEntry? { book[path] }
}
