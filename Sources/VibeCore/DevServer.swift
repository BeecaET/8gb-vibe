import Darwin
import Foundation

/// A TCP port a process is listening on.
public struct ListeningPort: Sendable, Hashable, Comparable {
    public var number: UInt16
    /// true: reachable only from this Mac (127.0.0.1, ::1). false: other devices on the network can reach it too.
    public var localOnly: Bool

    public init(number: UInt16, localOnly: Bool) { self.number = number; self.localOnly = localOnly }
    public static func < (a: ListeningPort, b: ListeningPort) -> Bool { a.number < b.number }
}

/// Reads listening TCP ports through libproc. Only the user's own processes can be read.
public enum PortReader {
    public static func listeningPorts(pid: Int32) -> [ListeningPort] {
        let byteCount = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard byteCount > 0 else { return [] }
        let step = MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(byteCount) / step + 16)
        let read = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, Int32(fds.count * step))
        guard read > 0 else { return [] }

        var byPort: [UInt16: Bool] = [:]
        for fd in fds.prefix(Int(read) / step) where fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            var si = socket_fdinfo()
            let size = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &si, size) == size,
                  si.psi.soi_kind == SOCKINFO_TCP else { continue }
            let tcp = si.psi.soi_proto.pri_tcp
            guard tcp.tcpsi_state == TSI_S_LISTEN else { continue }
            let ini = tcp.tcpsi_ini
            let number = UInt16(bigEndian: UInt16(truncatingIfNeeded: ini.insi_lport))
            guard number > 0 else { continue }
            let loopback: Bool
            if ini.insi_vflag & UInt8(INI_IPV4) != 0 {
                let a = UInt32(bigEndian: ini.insi_laddr.ina_46.i46a_addr4.s_addr)
                loopback = a >> 24 == 127
            } else {
                var a6 = ini.insi_laddr.ina_6
                let b = withUnsafeBytes(of: &a6) { Array($0) }
                loopback = b.count == 16 && b[0..<15].allSatisfy { $0 == 0 } && b[15] == 1
            }
            // Same port on IPv4 and IPv6: count as "this Mac only" only when every socket is loopback.
            byPort[number] = (byPort[number] ?? true) && loopback
        }
        return byPort.map { ListeningPort(number: $0.key, localOnly: $0.value) }.sorted()
    }
}

/// Recognizes development processes (node, python...) and the server kind from command line arguments.
public enum DevProcessClassifier {
    /// Code runtimes. Orphan detection only looks at this group.
    static let runtimes: Set<String> = ["node", "bun", "deno", "python", "python3", "Python", "ruby", "php",
                                          "java", "uv", "uvx", "esbuild", "tsx"]
    /// Shells and wrappers: skipped when looking for who started a server.
    static let shell: Set<String> = ["zsh", "bash", "sh", "fish", "dash", "login", "sudo", "env", "script", "caffeinate", "nohup",
                                       // Codex runs agent commands inside a Seatbelt sandbox.
                                       "sandbox-exec"]
    /// Development services often run in the background through launchd (Homebrew, Android...). Other background services are hidden.
    static let devServices: Set<String> = ["postgres", "redis-server", "mysqld", "mariadbd", "mongod", "memcached", "nginx",
                                         "caddy", "httpd", "adb", "ollama", "minio", "rabbitmq-server", "beam.smp",
                                         "valkey-server", "clickhouse", "meilisearch", "typesense-server"]
    /// Command launchers: not used as the kind name when a more specific kind is found in the tree.
    static let launchers: Set<String> = ["npm", "pnpm", "yarn", "npx", "bun", "corepack", "node", "uv", "uvx"]

    /// Package or command name -> server kind to display.
    static let knownKinds: [String: String] = [
        "next": "Next.js", "next-server": "Next.js", "vite": "Vite", "nuxt": "Nuxt", "nuxi": "Nuxt", "astro": "Astro",
        "webpack": "webpack", "webpack-dev-server": "webpack", "react-scripts": "Create React App",
        "@sveltejs": "SvelteKit", "remix": "Remix", "@remix-run": "Remix", "expo": "Expo", "@expo": "Expo",
        "react-native": "Metro", "metro": "Metro", "storybook": "Storybook", "@storybook": "Storybook",
        "nodemon": "nodemon", "ts-node": "ts-node", "tsx": "tsx", "http-server": "http-server", "serve": "serve",
        "json-server": "json-server", "wrangler": "Wrangler", "firebase-tools": "Firebase", "vercel": "Vercel",
        "parcel": "Parcel", "@angular": "Angular", "gatsby": "Gatsby", "@11ty": "Eleventy",
        "@docusaurus": "Docusaurus", "turbo": "Turborepo", "esbuild": "esbuild",
        "@playwright": "Playwright", "playwright": "Playwright", "puppeteer": "Puppeteer",
        "@modelcontextprotocol": "MCP server",
        "uvicorn": "Uvicorn", "gunicorn": "Gunicorn", "flask": "Flask", "django": "Django", "streamlit": "Streamlit",
        "gradio": "Gradio", "jupyter": "Jupyter", "jupyter-lab": "Jupyter", "jupyter-notebook": "Jupyter",
        "fastapi": "FastAPI", "mkdocs": "MkDocs", "http.server": "Python http.server",
        "npm": "npm", "pnpm": "pnpm", "yarn": "yarn", "npx": "npx"
    ]

    /// Turns a script file name into a command name: npm-cli.js -> npm, pnpm.cjs -> pnpm.
    static func commandName(_ s: String) -> String {
        var b = (s as NSString).lastPathComponent
        for tail in [".js", ".cjs", ".mjs", ".ts", ".py"] where b.hasSuffix(tail) { b = String(b.dropLast(tail.count)) }
        if b.hasSuffix("-cli") { b = String(b.dropLast(4)) }
        return b
    }

    /// Normalized arguments. npm and Next.js rename their process to one string with spaces ("npm exec tsx src/index.ts"): split it.
    static func arguments(_ t: ProcessRecord) -> [String] {
        // The overwritten argument area leaves empty strings behind: drop them.
        let items = t.arguments.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if let head = items.first, head.contains(" "), !head.hasPrefix("/") {
            return head.split(separator: " ").map(String.init) + items.dropFirst()
        }
        return items
    }

    static func fileName(_ t: ProcessRecord) -> String {
        t.path.isEmpty ? t.name : (t.path as NSString).lastPathComponent
    }

    /// Browser downloaded by Playwright or Puppeteer to run tests.
    public static func isTestBrowser(_ t: ProcessRecord) -> Bool {
        t.path.contains("/ms-playwright/") || t.path.contains("/puppeteer/")
            || t.name.hasPrefix("Google Chrome for Testing") || t.name.hasPrefix("chrome-headless-shell")
    }

    public static func isRuntime(_ t: ProcessRecord) -> Bool {
        runtimes.contains(fileName(t)) || runtimes.contains(t.name) || isTestBrowser(t)
    }

    public static func isShell(_ t: ProcessRecord) -> Bool {
        shell.contains(fileName(t)) || shell.contains(t.name) || t.name.hasPrefix("-")
    }

    /// CLI AI agent (not a dev server). Returns the name shown as the server's "owner".
    public static func agentName(_ t: ProcessRecord) -> String? {
        if ProcessClassifier.isClaudeCode(t) { return "Claude Code" }
        // Executable name, or the script name when run through node (npm installs: argv[1] is the command path, for example /opt/homebrew/bin/gemini).
        var name: Set<String> = [fileName(t)]
        for a in arguments(t).prefix(2) { name.insert(commandName(a)) }
        let a = arguments(t).prefix(2).joined(separator: " ")
        if name.contains("codex") || a.contains("@openai/codex") { return "Codex CLI" }
        if name.contains("gemini") || a.contains("@google/gemini-cli") { return "Gemini CLI" }
        // Antigravity CLI replaced Gemini CLI for most accounts in 2026.
        if name.contains("agy") || a.contains("antigravity-cli") { return "Antigravity CLI" }
        if name.contains("copilot") || a.contains("@github/copilot") { return "Copilot CLI" }
        if name.contains("cursor-agent") { return "Cursor CLI" }
        if name.contains("opencode") || a.contains("opencode-ai") { return "OpenCode" }
        if name.contains("aider") { return "Aider" }
        return nil
    }

    /// Names that may match `knownKinds`: each argument's file name, the package right after node_modules, the module after `-m`.
    static func nameCandidates(_ t: ProcessRecord) -> [String] {
        var items: [String] = []
        let normalizedArgs = arguments(t)
        let args = normalizedArgs.isEmpty ? [t.path] : normalizedArgs
        for (i, a) in args.enumerated() {
            if a == "-m", i + 1 < args.count { items.append(args[i + 1]) }
            if a.hasPrefix("next-server") { items.append("next-server") }
            if let r = a.range(of: "node_modules/", options: .backwards) {
                let after = a[r.upperBound...].split(separator: "/")
                if let packageName = after.first { items.append(String(packageName)) }
            }
            if a.hasPrefix("-") { continue }
            items.append(commandName(a))
            if (a as NSString).lastPathComponent == "manage.py" { items.append("django") }
        }
        if isTestBrowser(t) { items.append(t.path.contains("/puppeteer/") ? "puppeteer" : "playwright") }
        return items
    }

    /// Most specific server kind readable from one process. nil if it is only a generic launcher.
    static func specificKind(_ t: ProcessRecord) -> String? {
        for name in nameCandidates(t) {
            if name.hasSuffix("-mcp") || name.hasPrefix("mcp-server") || name.hasSuffix("-mcp-server") { return "MCP server" }
            if let l = knownKinds[name], !launchers.contains(name) { return l }
        }
        return nil
    }

    /// Kind of the whole tree: prefer the specific kind closest to the root, else the launcher or runtime name.
    public static func serverKind(root: ProcessRecord, tree: [ProcessRecord]) -> String {
        if let l = specificKind(root) { return l }
        for t in tree { if let l = specificKind(t) { return l } }
        for name in nameCandidates(root) where launchers.contains(name) && name != "node" { return knownKinds[name] ?? name }
        let f = fileName(root)
        switch f {
        case "node": return "Node"
        case "python", "python3", "Python": return "Python"
        case "bun": return "Bun"
        case "deno": return "Deno"
        case "ruby": return "Ruby"
        case "php": return "PHP"
        case "java": return "Java"
        default: return f
        }
    }

    /// Short command to display: command name and a few leading arguments, stopping at the first flag so values such as tokens are not shown.
    public static func commandSummary(_ t: ProcessRecord) -> String {
        var args = arguments(t)
        guard !args.isEmpty else { return fileName(t) }
        // Drop the leading runtime path (node, python...) when a script follows it.
        if args.count > 1, runtimes.contains(commandName(args[0])) {
            let head = commandName(args[0])
            if args[1] == "-m", args.count > 2 {
                args = [head, "-m"] + args.dropFirst(2)
            } else if !args[1].hasPrefix("-") {
                args.removeFirst()
            }
        }
        var items: [String] = []
        for (i, a) in args.enumerated() {
            if i > 0, a.hasPrefix("-"), a != "-m" { break }
            items.append(i == 0 || a.hasPrefix("/") ? commandName(a) : a)
            if items.count >= 4 { break }
        }
        let s = items.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return fileName(t) }
        return s.count > 60 ? String(s.prefix(59)) + "…" : s
    }

    /// Project name: the working directory, or the folder holding node_modules in the script path.
    public static func projectName(directory: String?, root: ProcessRecord) -> String? {
        if let m = directory, m != "/", m != NSHomeDirectory() { return (m as NSString).lastPathComponent }
        for a in root.arguments {
            if let r = a.range(of: "/node_modules/") {
                return (String(a[..<r.lowerBound]) as NSString).lastPathComponent
            }
        }
        return nil
    }
}

/// A dev server or development process still running, with its whole child process tree.
public struct DevServer: Identifiable, Sendable, Hashable {
    /// Who started this server.
    public enum Owner: Sendable, Hashable {
        /// A running CLI AI agent (Claude Code, Codex...), with the session's folder.
        case agent(name: String, directory: String?)
        /// A GUI app, through a shell: Terminal, iTerm, VS Code...
        case app(String)
        /// A service started by launchd (for example a database installed with Homebrew).
        case backgroundService
        /// Whatever started it has quit (agent finished, Terminal window closed) but the process still runs.
        case orphaned
    }

    public var id: String
    public var pid: Int32
    public var serverKind: String
    public var command: String
    public var ports: [ListeningPort]
    public var directory: String?
    public var projectName: String?
    public var owner: Owner
    /// Every process in the tree, root first. Used when stopping.
    public var processIdentities: [ProcessIdentity]
    public var footprint: UInt64
    public var cpu: Double
    public var startDate: Date
    public var lastActive: Date
    /// For orphans: the agent session that started it, if the app saw that session alive.
    public var origin: ProcessOrigin? = nil

    public var orphaned: Bool { owner == .orphaned }

    /// Has a port open to the network (other devices on the same Wi-Fi can reach it).
    public var exposedToNetwork: Bool { ports.contains { !$0.localOnly } }

    public var ownerDescription: String {
        switch owner {
        case let .agent(name, directory):
            if let m = directory { return "\(name) (\((m as NSString).lastPathComponent))" }
            return name
        case let .app(name): return name
        case .backgroundService: return String(localized: "Dịch vụ nền", bundle: .main)
        case .orphaned:
            if let o = origin { return String(localized: "Mồ côi của \(o.sessionDescription)", bundle: .main) }
            return String(localized: "Mồ côi", bundle: .main)
        }
    }
}

public enum DevServerBuilder {
    /// Whether ports are worth reading: the user's own process, not inside an .app bundle (except test browsers), not a system process.
    public static func shouldReadPorts(_ t: ProcessRecord, uid: UInt32) -> Bool {
        guard t.uid == uid, !t.path.isEmpty else { return false }
        if DevProcessClassifier.isTestBrowser(t) || DevProcessClassifier.isRuntime(t) { return true }
        let p = t.path
        if p.contains(".app/") { return false }
        for head in ["/System/", "/usr/bin/", "/usr/sbin/", "/usr/libexec/", "/sbin/", "/bin/", "/Library/Apple/"] where p.hasPrefix(head) {
            return false
        }
        if DevProcessClassifier.agentName(t) != nil { return false }
        return true
    }

    /// Groups processes into a list of dev servers.
    /// - ports: listening ports by pid (only needed for processes passing `shouldReadPorts`).
    /// - Only keeps trees with a listening port, or orphaned runtime trees.
    public static func from(_ list: [ProcessRecord], ports: [Int32: [ListeningPort]], cpu: [Int32: Double],
                          directory: (Int32) -> String?, lastActive: (String, Double) -> Date,
                          origin: (ProcessRecord) -> ProcessOrigin? = { _ in nil }) -> [DevServer] {
        let byPID = Dictionary(list.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        var children: [Int32: [Int32]] = [:]
        for t in list { children[t.ppid, default: []].append(t.pid) }

        func isDev(_ t: ProcessRecord) -> Bool {
            guard DevProcessClassifier.agentName(t) == nil else { return false }
            if DevProcessClassifier.isRuntime(t) {
                // Gradle and Kotlin daemons are already on the Free RAM page.
                return ProcessClassifier.classifyOne(t).0.group != .android
            }
            return !(ports[t.pid] ?? []).isEmpty
        }

        // Root: a dev process whose parent is not a dev process.
        var root: [ProcessRecord] = []
        for t in list where isDev(t) {
            if let parent = byPID[t.ppid], isDev(parent) { continue }
            root.append(t)
        }

        var result: [DevServer] = []
        for g in root {
            // The whole child tree, capped so it cannot loop.
            var tree: [ProcessRecord] = []
            var queue = [g.pid]
            while let x = queue.popLast(), tree.count < 300 {
                if let t = byPID[x] { tree.append(t) }
                queue.append(contentsOf: children[x] ?? [])
            }
            // Split into steps: older Swift compilers (Xcode 16) time out type-checking the one-line form.
            let treeAllPorts: [ListeningPort] = tree.flatMap { (p: ProcessRecord) -> [ListeningPort] in ports[p.pid] ?? [] }
            let treeNumbers: [UInt16] = Array(Set(treeAllPorts.map { $0.number })).sorted()
            let treePorts: [ListeningPort] = treeNumbers.map { (number: UInt16) -> ListeningPort in
                let same = treeAllPorts.filter { $0.number == number }
                return ListeningPort(number: number, localOnly: same.allSatisfy { $0.localOnly })
            }

            guard let owner = findOwner(g, byPID: byPID, directory: directory) else { continue }
            let m = directory(g.pid)
            var resolvedOwner = owner
            // Orphans only count for code runtimes. A process started by launchd has "/" as working directory: treat it as a background service.
            // A known origin (the agent session that started it has ended) always means orphaned.
            let knownOrigin = owner == .orphaned ? origin(g) : nil
            if owner == .orphaned, knownOrigin == nil, !DevProcessClassifier.isRuntime(g) || m == "/" { resolvedOwner = .backgroundService }
            guard !treePorts.isEmpty || resolvedOwner == .orphaned else { continue }
            if resolvedOwner == .backgroundService, !DevProcessClassifier.isRuntime(g), !DevProcessClassifier.devServices.contains(DevProcessClassifier.fileName(g)) { continue }

            let c = tree.reduce(0.0) { $0 + (cpu[$1.pid] ?? 0) }
            let id = "dev:\(g.key)"
            result.append(DevServer(id: id, pid: g.pid, serverKind: DevProcessClassifier.serverKind(root: g, tree: Array(tree.dropFirst())),
                                command: DevProcessClassifier.commandSummary(g), ports: treePorts, directory: m,
                                projectName: DevProcessClassifier.projectName(directory: m, root: g), owner: resolvedOwner,
                                processIdentities: tree.map(ProcessIdentity.init),
                                footprint: tree.reduce(0) { $0 + ($1.footprint ?? 0) }, cpu: c,
                                startDate: g.startDate, lastActive: lastActive(id, c), origin: knownOrigin))
        }
        return result.sorted { ($0.orphaned ? 0 : 1, $0.ports.first?.number ?? .max) < ($1.orphaned ? 0 : 1, $1.ports.first?.number ?? .max) }
    }

    /// Walks up the parents, skipping shells, to find who started it. nil: an app's internal child process (no shell in between), skipped.
    static func findOwner(_ g: ProcessRecord, byPID: [Int32: ProcessRecord], directory: (Int32) -> String?) -> DevServer.Owner? {
        var p = g.ppid
        var viaShell = false
        var step = 0
        while step < 40 {
            step += 1
            if p <= 1 { return .orphaned }
            guard let t = byPID[p] else { return .orphaned }
            if let name = DevProcessClassifier.agentName(t) { return .agent(name: name, directory: directory(t.pid)) }
            if DevProcessClassifier.isShell(t) {
                viaShell = true
                p = t.ppid
                continue
            }
            if t.path.contains(".app/") {
                return viaShell ? .app(t.appName) : nil
            }
            // tmux, screen and other wrappers: treated as the owner.
            return .app(DevProcessClassifier.fileName(t))
        }
        return .orphaned
    }
}
