import XCTest
@testable import VibeCore

final class MCPDetectorTests: XCTestCase {
    let node = "/opt/homebrew/bin/node"

    func testNames() {
        XCTAssertEqual(MCPDetector.name(makeProcess(1, 1, node, args: ["node", "/x/node_modules/@modelcontextprotocol/server-filesystem/dist/index.js", "/Users/u"])), "filesystem")
        XCTAssertEqual(MCPDetector.name(makeProcess(2, 1, node, args: ["node", "/Users/u/.npm/_npx/a/node_modules/@playwright/mcp/cli.js"])), "playwright")
        XCTAssertEqual(MCPDetector.name(makeProcess(3, 1, node, args: ["node", "/x/node_modules/@upstash/context7-mcp/dist/index.js"])), "context7")
        XCTAssertEqual(MCPDetector.name(makeProcess(4, 1, "/opt/homebrew/bin/github-mcp-server", args: ["github-mcp-server", "stdio"])), "github")
        XCTAssertEqual(MCPDetector.name(makeProcess(5, 1, "/opt/homebrew/bin/python3", args: ["python3", "-m", "mcp_server_git"])), "git")
        XCTAssertEqual(MCPDetector.name(makeProcess(6, 1, "/Users/u/.local/bin/uvx", args: ["uvx", "mcp-server-fetch"])), "fetch")
        // Not MCP servers.
        XCTAssertNil(MCPDetector.name(makeProcess(7, 1, node, args: ["node", "/Users/u/web/node_modules/.bin/vite"])))
        XCTAssertNil(MCPDetector.name(makeProcess(8, 1, "/bin/zsh")))
    }
}

final class LineageTests: XCTestCase {
    let node = "/opt/homebrew/bin/node"
    let claude = "/Users/u/.local/share/claude/versions/2.1.400/claude"

    /// A Claude Code session with a dev server and two MCP servers; later the session exits.
    func scenario() -> (alive: [ProcessRecord], afterExit: [ProcessRecord]) {
        let session = makeProcess(100, 1, claude, startDate: 10)
        let shell = makeProcess(101, 100, "/bin/zsh", startDate: 20)
        let vite = makeProcess(102, 101, node, startDate: 30, fp: 300, args: ["node", "/Users/u/shop/node_modules/.bin/vite"])
        let pw = makeProcess(103, 100, node, startDate: 15, fp: 400, args: ["node", "/x/node_modules/@playwright/mcp/cli.js"])
        let fs = makeProcess(104, 100, node, startDate: 15, fp: 100, args: ["node", "/x/node_modules/@modelcontextprotocol/server-filesystem/index.js"])
        // After the session exits, its children are reparented to launchd.
        var vite2 = vite; vite2.ppid = 1
        var pw2 = pw; pw2.ppid = 1
        var fs2 = fs; fs2.ppid = 1
        return ([session, shell, vite, pw, fs], [vite2, pw2, fs2])
    }

    func engine() -> ProcessAnalyzer {
        ProcessAnalyzer(readWorkingDirectory: { $0 == 100 ? "/Users/u/shop" : "/" },
                        readPorts: { $0 == 102 ? [ListeningPort(number: 5173, localOnly: true)] : [] }, uid: 501)
    }

    func testMCPPerSessionAndDuplicates() {
        let e = engine()
        let (alive, _) = scenario()
        // A second session with its own Playwright MCP.
        let other = [makeProcess(200, 1, claude, startDate: 40),
                     makeProcess(201, 200, node, startDate: 41, fp: 500, args: ["node", "/x/node_modules/@playwright/mcp/cli.js"])]
        let r = e.analyze(alive + other, now: Date(timeIntervalSince1970: 1000))
        let first = r.mcpServers.filter { $0.origin?.sessionID == r.sessions.first { $0.pid == 100 }?.id }
        XCTAssertEqual(Set(first.map(\.name)), ["playwright", "filesystem"])
        let dup = MCPBuilder.duplicates(r.mcpServers)
        XCTAssertEqual(dup.map(\.name), ["playwright"])
        XCTAssertEqual(dup.first?.count, 2)
        XCTAssertEqual(dup.first?.footprint, 900)
    }

    func testOrphansRememberTheirSession() {
        let e = engine()
        let (alive, afterExit) = scenario()
        _ = e.analyze(alive, now: Date(timeIntervalSince1970: 1000))
        let r = e.analyze(afterExit, now: Date(timeIntervalSince1970: 1000 + 7200))

        let orphans = r.devServers.filter(\.orphaned)
        XCTAssertEqual(Set(orphans.map(\.pid)), [102, 103, 104])
        for d in orphans {
            XCTAssertEqual(d.origin?.agent, "Claude Code")
            XCTAssertEqual(d.origin?.projectName, "shop")
            XCTAssertEqual(d.origin?.endedAt, Date(timeIntervalSince1970: 1000))
        }
        // MCP servers of an ended session are no longer counted as live MCP.
        XCTAssertTrue(r.mcpServers.isEmpty)

        // The three orphans of the session become one candidate, stopped together.
        let grouped = CandidateBuilder.orphanCandidates(r)
        XCTAssertEqual(grouped.count, 1)
        XCTAssertEqual(grouped.first?.id, "orphans:\(alive[0].key)")
        XCTAssertEqual(grouped.first?.footprint, 800)
        if case let .processes(ids)? = grouped.first?.quitMethod {
            XCTAssertEqual(Set(ids.map(\.pid)), [102, 103, 104])
        } else {
            XCTFail("expected processes")
        }
        XCTAssertTrue(grouped.first?.note.contains("2 h") ?? false, grouped.first?.note ?? "")
    }

    func testUnknownOriginStaysPlainOrphan() {
        // The app never saw the session: orphans are listed one by one, without an origin.
        let e = engine()
        let (_, afterExit) = scenario()
        let r = e.analyze(afterExit, now: Date(timeIntervalSince1970: 5000))
        XCTAssertTrue(r.devServers.filter(\.orphaned).allSatisfy { $0.origin == nil })
        XCTAssertEqual(CandidateBuilder.orphanCandidates(r).count, r.devServers.filter(\.orphaned).count)
    }
}
