import Darwin
import XCTest
@testable import VibeCore

final class DevProcessClassifierTests: XCTestCase {
    let node = "/opt/homebrew/bin/node"

    func testKind() {
        let next = makeProcess(10, 1, node, args: ["node", "/Users/u/web/node_modules/.bin/next", "dev"])
        XCTAssertEqual(DevProcessClassifier.serverKind(root: next, tree: []), "Next.js")
        let vite = makeProcess(11, 1, node, args: ["node", "/Users/u/app/node_modules/vite/bin/vite.js", "--port", "5173"])
        XCTAssertEqual(DevProcessClassifier.serverKind(root: vite, tree: []), "Vite")
        let worker = makeProcess(12, 1, node, args: ["next-server (v15.0.3)"])
        XCTAssertEqual(DevProcessClassifier.serverKind(root: worker, tree: []), "Next.js")
        let py = makeProcess(13, 1, "/opt/homebrew/bin/python3", args: ["python3", "-m", "http.server", "8000"])
        XCTAssertEqual(DevProcessClassifier.serverKind(root: py, tree: []), "Python http.server")
        let uv = makeProcess(14, 1, "/opt/homebrew/bin/python3", args: ["python3", "/Users/u/api/.venv/bin/uvicorn", "main:app"])
        XCTAssertEqual(DevProcessClassifier.serverKind(root: uv, tree: []), "Uvicorn")
        let mcp = makeProcess(15, 1, node, args: ["node", "/Users/u/.npm/_npx/abc/node_modules/@playwright/mcp/cli.js"])
        XCTAssertEqual(DevProcessClassifier.serverKind(root: mcp, tree: []), "Playwright")
        let mcp2 = makeProcess(16, 1, node, args: ["node", "/Users/u/.npm/_npx/x/node_modules/.bin/github-mcp-server"])
        XCTAssertEqual(DevProcessClassifier.serverKind(root: mcp2, tree: []), "MCP server")
        let plainNode = makeProcess(17, 1, node, args: ["node", "/Users/u/x/server.js"])
        XCTAssertEqual(DevProcessClassifier.serverKind(root: plainNode, tree: []), "Node")
    }

    func testKindFromChildren() {
        // npm run dev is only a launcher; the real kind is in the child process.
        let npm = makeProcess(20, 1, node, args: ["node", "/opt/homebrew/lib/node_modules/npm/bin/npm-cli.js", "run", "dev"])
        let next = makeProcess(21, 20, node, args: ["node", "/Users/u/web/node_modules/.bin/next", "dev"])
        XCTAssertEqual(DevProcessClassifier.serverKind(root: npm, tree: [next]), "Next.js")
        XCTAssertEqual(DevProcessClassifier.serverKind(root: npm, tree: []), "npm")
    }

    func testCommandSummaryStopsAtFlag() {
        let t = makeProcess(30, 1, node, args: ["node", "/Users/u/web/node_modules/.bin/next", "dev", "--token", "bi-mat"])
        XCTAssertEqual(DevProcessClassifier.commandSummary(t), "next dev")
        let npm = makeProcess(31, 1, node, args: ["node", "/opt/homebrew/lib/node_modules/npm/bin/npm-cli.js", "run", "dev"])
        XCTAssertEqual(DevProcessClassifier.commandSummary(npm), "npm run dev")
        let py = makeProcess(32, 1, "/opt/homebrew/bin/python3", args: ["/opt/homebrew/bin/python3", "-m", "http.server", "8000"])
        XCTAssertEqual(DevProcessClassifier.commandSummary(py), "python3 -m http.server 8000")
        XCTAssertFalse(DevProcessClassifier.commandSummary(t).contains("bi-mat"))
        // Process name rewritten by npm into one string.
        let title = makeProcess(33, 1, node, args: ["npm exec tsx src/index.ts   ", "", ""])
        XCTAssertEqual(DevProcessClassifier.commandSummary(title), "npm exec tsx src/index.ts")
        XCTAssertEqual(DevProcessClassifier.serverKind(root: title, tree: []), "tsx")
    }

    func testProjectName() {
        let t = makeProcess(40, 1, node, args: ["node", "/Users/u/CODE/shop/node_modules/.bin/vite"])
        XCTAssertEqual(DevProcessClassifier.projectName(directory: "/Users/u/CODE/shop", root: t), "shop")
        XCTAssertEqual(DevProcessClassifier.projectName(directory: "/", root: t), "shop")
    }
}

final class DevServerBuilderTests: XCTestCase {
    let node = "/opt/homebrew/bin/node"
    let terminal = "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"
    let claude = "/Users/u/Library/Application Support/Claude/claude-code/2.1.309/abc/claude.app/Contents/MacOS/claude"

    func run(_ list: [ProcessRecord], ports: [Int32: [ListeningPort]], directory: [Int32: String] = [:]) -> [DevServer] {
        DevServerBuilder.from(list, ports: ports, cpu: [:], directory: { directory[$0] }, lastActive: { _, _ in Date(timeIntervalSince1970: 0) })
    }

    func testGroupsTreeAndFindsOwner() {
        let list = [
            makeProcess(100, 1, terminal),
            makeProcess(101, 100, "/usr/bin/login"),
            makeProcess(102, 101, "/bin/zsh"),
            makeProcess(103, 102, node, fp: 50, args: ["node", "/opt/homebrew/lib/node_modules/npm/bin/npm-cli.js", "run", "dev"]),
            makeProcess(104, 103, node, fp: 300, args: ["node", "/Users/u/web/node_modules/.bin/next", "dev"]),
            makeProcess(105, 104, node, fp: 200, args: ["next-server (v15)"])
        ]
        let items = run(list, ports: [105: [ListeningPort(number: 3000, localOnly: false)]], directory: [103: "/Users/u/web"])
        XCTAssertEqual(items.count, 1)
        let d = items[0]
        XCTAssertEqual(d.pid, 103)
        XCTAssertEqual(d.serverKind, "Next.js")
        XCTAssertEqual(d.ports.map(\.number), [3000])
        XCTAssertTrue(d.exposedToNetwork)
        XCTAssertEqual(d.owner, .app("Terminal"))
        XCTAssertEqual(d.footprint, 550)
        XCTAssertEqual(d.processIdentities.map(\.pid).first, 103)
        XCTAssertEqual(Set(d.processIdentities.map(\.pid)), [103, 104, 105])
        XCTAssertEqual(d.projectName, "web")
    }

    func testOrphans() {
        let list = [
            // Orphaned Vite, still listening on a port.
            makeProcess(200, 1, node, args: ["node", "/Users/u/shop/node_modules/.bin/vite"]),
            // Orphaned MCP server, no port.
            makeProcess(201, 1, node, args: ["node", "/Users/u/.npm/_npx/a/node_modules/@modelcontextprotocol/server-filesystem/dist/index.js"]),
            // Database started by launchd: background service, not orphaned.
            makeProcess(202, 1, "/opt/homebrew/opt/postgresql@16/bin/postgres"),
            // Non-dev background service (printer driver): dropped.
            makeProcess(204, 1, "/Library/Printers/x/ccpd"),
            // Node started by launchd, folder "/": background service, no port, so dropped.
            makeProcess(203, 1, node, args: ["node", "/Users/u/Library/Application Support/x/agent.js"])
        ]
        let items = run(list, ports: [200: [ListeningPort(number: 5173, localOnly: true)], 202: [ListeningPort(number: 5432, localOnly: true)],
                             204: [ListeningPort(number: 59687, localOnly: false)]],
                      directory: [200: "/Users/u/shop", 201: "/Users/u/proj", 203: "/"])
        let byPID = Dictionary(uniqueKeysWithValues: items.map { ($0.pid, $0) })
        XCTAssertEqual(byPID[200]?.owner, .orphaned)
        XCTAssertEqual(byPID[201]?.owner, .orphaned)
        XCTAssertEqual(byPID[201]?.serverKind, "MCP server")
        XCTAssertEqual(byPID[202]?.owner, .backgroundService)
        XCTAssertNil(byPID[203])
        XCTAssertNil(byPID[204])
        // Orphans sort first.
        XCTAssertTrue(items.first?.orphaned ?? false)
    }

    func testSkipsAgentsAndAppInternalProcesses() {
        let code = "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin)"
        let list = [
            makeProcess(300, 1, claude),
            // MCP server child of Claude Code, no port: not shown.
            makeProcess(301, 300, node, args: ["node", "/x/node_modules/@modelcontextprotocol/server-memory/index.js"]),
            // Dev server Claude Code started through a shell, with a port: owner is Claude Code.
            makeProcess(302, 300, "/bin/zsh"),
            makeProcess(303, 302, node, args: ["node", "/Users/u/web/node_modules/.bin/vite"]),
            // VS Code internal language server (no shell in between), with a port: dropped.
            makeProcess(304, 1, code),
            makeProcess(305, 304, node, args: ["node", "/Users/u/.vscode/extensions/x/server.js"])
        ]
        let items = run(list, ports: [303: [ListeningPort(number: 5173, localOnly: true)], 305: [ListeningPort(number: 9000, localOnly: true)]],
                      directory: [300: "/Users/u/web"])
        XCTAssertEqual(items.map(\.pid), [303])
        XCTAssertEqual(items[0].owner, .agent(name: "Claude Code", directory: "/Users/u/web"))
        XCTAssertEqual(items[0].ownerDescription, "Claude Code (web)")
    }

    func testCandidateAndSuggestion() {
        let list = [makeProcess(400, 1, node, fp: 400 << 20, args: ["node", "/Users/u/shop/node_modules/.bin/vite"])]
        let engine = ProcessAnalyzer(readWorkingDirectory: { _ in "/Users/u/shop" },
                            readPorts: { $0 == 400 ? [ListeningPort(number: 5173, localOnly: true)] : [] }, uid: 501)
        let result = engine.analyze(list, now: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(result.devServers.count, 1)
        let u = CandidateBuilder.from(result).first { $0.id == result.devServers[0].id }
        XCTAssertNotNil(u)
        XCTAssertEqual(u?.name, "Vite (shop), port 5173")
        XCTAssertTrue(u?.isProcess ?? false)
        // Idle long enough to become a suggestion.
        let result2 = engine.analyze(list, now: Date(timeIntervalSince1970: 1000 + 3600))
        let suggestions = SuggestionBuilder.from(result2, idleTime: 1800, now: Date(timeIntervalSince1970: 1000 + 3600))
        XCTAssertTrue(suggestions.contains { $0.id == result.devServers[0].id })
    }
}

final class PortReaderTests: XCTestCase {
    /// Opens a real port on 127.0.0.1 in the test process, then reads it back.
    func testReadsOwnPort() throws {
        let s = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(s, 0)
        defer { close(s) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        XCTAssertEqual(result, 0)
        XCTAssertEqual(listen(s, 1), 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.getsockname(s, $0, &length) }
        }
        let number = UInt16(bigEndian: address.sin_port)
        let items = PortReader.listeningPorts(pid: getpid())
        XCTAssertTrue(items.contains(ListeningPort(number: number, localOnly: true)), "\(items)")
    }
}

final class ProcessIdentityTests: XCTestCase {
    func testChecksIdentityBeforeSignal() throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        p.arguments = ["30"]
        try p.run()
        defer { if p.isRunning { p.terminate() } }

        var cache: [String: (String, [String])] = [:]
        let t = try XCTUnwrap(ProcessReader.read(pid: p.processIdentifier, cache: &cache))
        let d = ProcessIdentity(t)
        XCTAssertTrue(d.isSameProcess())
        // Different start time: treated as a reused pid.
        XCTAssertFalse(ProcessIdentity(pid: d.pid, seconds: d.seconds - 5, microseconds: d.microseconds).isSameProcess())
        // Another user: no signal allowed.
        XCTAssertFalse(d.isSameProcess(uid: 0))

        p.terminate()
        p.waitUntilExit()
        XCTAssertFalse(d.isSameProcess())
    }
    /// B2: a signal only reaches the exact process that was seen, owned by this user.
    func testSendOnlyHitsSameProcess() throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        p.arguments = ["30"]
        try p.run()
        defer { if p.isRunning { p.terminate() } }
        var cache: [String: (String, [String])] = [:]
        let d = ProcessIdentity(try XCTUnwrap(ProcessReader.read(pid: p.processIdentifier, cache: &cache)))

        // Reused pid (different start time) or another user: nothing is sent, the process keeps running.
        XCTAssertFalse(ProcessIdentity(pid: d.pid, seconds: d.seconds - 5, microseconds: d.microseconds).send(SIGTERM))
        XCTAssertFalse(d.send(SIGTERM, uid: 0))
        XCTAssertTrue(p.isRunning)
        // Protected processes (here: pretending the test process is the app itself) are never signaled.
        XCTAssertFalse(d.send(SIGTERM, selfPID: d.pid))
        XCTAssertTrue(p.isRunning)

        // The real identity: stopped.
        XCTAssertTrue(d.canStop())
        XCTAssertTrue(d.send(SIGTERM))
        p.waitUntilExit()
        XCTAssertFalse(p.isRunning)
        // Gone: a second signal is not sent.
        XCTAssertFalse(d.send(SIGTERM))
    }

    /// Quit methods built from snapshots carry identities, never bare pids.
    func testCandidatesCarryIdentities() {
        let start = Date(timeIntervalSince1970: 1234.5)
        let row = makeProcess(42, 1, "/opt/homebrew/bin/node", startDate: start.timeIntervalSince1970,
                              args: ["node", "/Users/u/shop/node_modules/.bin/vite"])
        let engine = ProcessAnalyzer(readWorkingDirectory: { _ in "/Users/u/shop" }, readPorts: { _ in [] }, uid: 501)
        let result = engine.analyze([row], now: Date(timeIntervalSince1970: 2000))
        let u = CandidateBuilder.from(result).first { $0.id.hasPrefix("dev:") }
        XCTAssertEqual(u?.quitMethod, .processes([ProcessIdentity(pid: 42, startDate: start)]))
    }
}
