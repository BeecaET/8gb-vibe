import XCTest
@testable import VibeCore

/// All tests use a fake HOME and a fake /Applications in a temp folder. No real config is read or written.
final class MCPClientsTests: XCTestCase {
    let server = "/Applications/8GB Vibe.app/Contents/Helpers/8gbvibe-mcp"
    var root: URL!
    var home: String { root.appendingPathComponent("home").path }
    var apps: String { root.appendingPathComponent("Applications").path }
    /// Install ledger inside the temp folder (never the real Application Support).
    var ledger: URL { root.appendingPathComponent("mcp-installs.json") }

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("8gb-clients-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(atPath: root.appendingPathComponent("home").path, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(atPath: root.appendingPathComponent("Applications").path, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    func put(_ rel: String, _ text: String, perms: Int = 0o600) {
        let u = URL(fileURLWithPath: home).appendingPathComponent(rel)
        try! FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: u.path, contents: Data(text.utf8), attributes: [.posixPermissions: perms])
    }
    func read(_ rel: String) -> String { try! String(contentsOfFile: URL(fileURLWithPath: home).appendingPathComponent(rel).path, encoding: .utf8) }
    func app(_ name: String) { try! FileManager.default.createDirectory(atPath: "\(apps)/\(name).app", withIntermediateDirectories: true) }
    func backups(_ dir: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: URL(fileURLWithPath: home).appendingPathComponent(dir).path)) ?? []).filter { $0.contains(".bak-8gbvibe-") }
    }
    func exe(_ path: String) {
        try! FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
    }

    func testDetectOnlyWhatExists() {
        XCTAssertTrue(MCPClients.detect(server: server, probe: .fake(home: home), appsRoot: apps).isEmpty)
        app("Claude"); app("Antigravity")
        put(".cursor/mcp.json", "{}")
        exe("\(home)/.local/bin/claude")
        exe("\(apps)/ChatGPT.app/Contents/Resources/codex-cli/bin/codex")
        let list = MCPClients.detect(server: server, probe: .fake(home: home), appsRoot: apps)
        XCTAssertEqual(list.map(\.kind), [.claudeCode, .codex, .cursor, .claudeDesktop, .antigravity])
        guard case let .command(add, remove) = list[1].method else { return XCTFail() }
        XCTAssertEqual(Array(add.dropFirst()), ["mcp", "add", "8gbvibe", "--", server])
        XCTAssertEqual(Array(remove.dropFirst()), ["mcp", "remove", "8gbvibe"])
        XCTAssertEqual(list[4].configFile.path, "\(home)/.gemini/config/mcp_config.json")
        XCTAssertEqual(list[3].configFile.path, "\(home)/Library/Application Support/Claude/claude_desktop_config.json")
    }

    func testGeminiUsesUserScopeAndCodexFallsBackToTOML() {
        exe("\(home)/.local/bin/gemini")
        put(".codex/config.toml", "model = \"o3\"\n")
        let list = MCPClients.detect(server: server, probe: .fake(home: home), appsRoot: apps)
        guard case let .command(add, remove) = list.first(where: { $0.kind == .geminiCLI })?.method else { return XCTFail() }
        XCTAssertEqual(Array(add.dropFirst()), ["mcp", "add", "-s", "user", "8gbvibe", server])
        XCTAssertEqual(Array(remove.dropFirst()), ["mcp", "remove", "-s", "user", "8gbvibe"])
        XCTAssertEqual(list.first { $0.kind == .codex }?.method, .toml(URL(fileURLWithPath: "\(home)/.codex/config.toml")))
    }

    func testJSONAddAndRemoveKeepsOtherServersAndFormat() throws {
        let original = """
        {
            "mcpServers": {
                "github": {
                    "command": "npx",
                    "args": ["-y", "@x/github"]
                }
            },
            "other": [1, 2,   3]
        }

        """
        put(".cursor/mcp.json", original, perms: 0o644)
        app("Cursor")
        let c = MCPClients.detect(server: server, probe: .fake(home: home), appsRoot: apps).first { $0.kind == .cursor }!
        XCTAssertEqual(MCPClients.state(c), .notInstalled)
        guard case let .done(backup) = try MCPFileInstaller.apply(c, install: true, server: server, ledger: ledger) else { return XCTFail() }
        XCTAssertEqual(MCPClients.state(c), .installed)
        let added = read(".cursor/mcp.json")
        XCTAssertTrue(added.hasPrefix(String(original.prefix(original.range(of: "}\n    },")!.lowerBound.utf16Offset(in: original) + 1))))
        XCTAssertTrue(added.contains("\"other\": [1, 2,   3]"), "untouched parts keep their spacing")
        XCTAssertTrue(added.contains("        \"8gbvibe\": {"), "same indent as the sibling server")
        XCTAssertEqual(try String(contentsOf: backup!, encoding: .utf8), original)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: c.configFile.path)[.posixPermissions] as? NSNumber)?.intValue, 0o644)
        XCTAssertThrowsError(try MCPFileInstaller.apply(c, install: true, server: server, ledger: ledger)) { XCTAssertEqual($0 as? MCPConfigError, .alreadyPresent) }
        _ = try MCPFileInstaller.apply(c, install: false, server: server, now: Date().addingTimeInterval(5), ledger: ledger)
        XCTAssertEqual(read(".cursor/mcp.json"), original, "removal gives back the exact original text")
        XCTAssertEqual(backups(".cursor").count, 2)
    }

    func testFirstMemberAndOnlyMemberRemoval() throws {
        let first = #"{"mcpServers": {"8gbvibe": {"command": "x"}, "b": {"command": "y"}}}"#
        XCTAssertEqual(try JSONServerEdit.remove(first), #"{"mcpServers": {"b": {"command": "y"}}}"#)
        let only = "{\n  \"mcpServers\": {\n    \"8gbvibe\": {\"command\": \"x\"}\n  }\n}"
        XCTAssertEqual(try JSONServerEdit.remove(only), "{\n  \"mcpServers\": {}\n}")
    }

    func testAddWhereMcpServersIsMissingOrEmptyOrFileEmpty() throws {
        let desktop = "{\n  \"preferences\": {\n    \"x\": true\n  }\n}\n"
        let r = try JSONServerEdit.add(desktop, entry: MCPClients.entry(server: server))
        XCTAssertTrue(try JSONServerEdit.contains(r))
        XCTAssertTrue(r.hasPrefix("{\n  \"preferences\": {\n    \"x\": true\n  },\n  \"mcpServers\": {"))
        XCTAssertTrue(try JSONServerEdit.contains(try JSONServerEdit.add("{\"mcpServers\": {}}", entry: MCPClients.entry(server: server))))
        XCTAssertTrue(try JSONServerEdit.contains(try JSONServerEdit.add("{}", entry: MCPClients.entry(server: server))))
        // Antigravity's file on this Mac is empty (0 bytes).
        XCTAssertTrue(try JSONServerEdit.contains(try JSONServerEdit.add("", entry: MCPClients.entry(server: server))))
        let withSlash = try JSONServerEdit.add("{}", entry: MCPClients.entry(server: server))
        XCTAssertTrue(withSlash.contains("\"/Applications/8GB Vibe.app/Contents/Helpers/8gbvibe-mcp\""))
    }

    func testCorruptFileIsNeverWritten() {
        app("Antigravity")
        let bad = "{ \"mcpServers\": { \"a\": 1, } // comment\n"
        put(".gemini/config/mcp_config.json", bad)
        let c = MCPClients.detect(server: server, probe: .fake(home: home), appsRoot: apps).first { $0.kind == .antigravity }!
        XCTAssertEqual(MCPClients.state(c), .unreadable(.corrupt))
        XCTAssertThrowsError(try MCPFileInstaller.apply(c, install: true, server: server, ledger: ledger))
        XCTAssertEqual(read(".gemini/config/mcp_config.json"), bad)
        XCTAssertTrue(backups(".gemini/config").isEmpty)
        XCTAssertThrowsError(try JSONServerEdit.add(#"{"mcpServers": []}"#, entry: [:])) { XCTAssertEqual($0 as? MCPConfigError, .serversNotAnObject) }
        XCTAssertThrowsError(try JSONServerEdit.add("[1]", entry: [:])) { XCTAssertEqual($0 as? MCPConfigError, .notAnObject) }
    }

    func testRemoveWhenNotInstalled() {
        XCTAssertThrowsError(try JSONServerEdit.remove(#"{"mcpServers": {"a": {}}}"#)) { XCTAssertEqual($0 as? MCPConfigError, .notPresent) }
    }

    func testTOMLKeepsEverythingElse() throws {
        let original = """
        model = "o3"

        [mcp_servers.node_repl]
        command = "node"

        [mcp_servers.node_repl.env]
        A = "1"

        [profiles.fast]
        model = "x"

        """
        put(".codex/config.toml", original)
        let c = MCPClients.detect(server: server, probe: .fake(home: home), appsRoot: apps).first { $0.kind == .codex }!
        XCTAssertEqual(MCPClients.state(c), .notInstalled)
        _ = try MCPFileInstaller.apply(c, install: true, server: server, ledger: ledger)
        XCTAssertEqual(MCPClients.state(c), .installed)
        XCTAssertTrue(read(".codex/config.toml").hasPrefix(original))
        _ = try MCPFileInstaller.apply(c, install: false, server: server, now: Date().addingTimeInterval(5), ledger: ledger)
        XCTAssertEqual(read(".codex/config.toml"), original)
        // Our table in the middle, with a sub-table: only ours goes.
        let mid = "a = 1\n[mcp_servers.8gbvibe]\ncommand = \"x\"\n[mcp_servers.8gbvibe.env]\nB = \"2\"\n[mcp_servers.other]\ncommand = \"y\"\n"
        XCTAssertEqual(try TOMLServerEdit.remove(mid), "a = 1\n[mcp_servers.other]\ncommand = \"y\"\n")
    }

    // Removal gives back the exact bytes from before the install when 8GB Vibe added "mcpServers" or the file.
    func roundTrip(_ rel: String, _ original: String?, client kind: MCPClientKind) throws -> String? {
        if let original { put(rel, original) }
        let c = MCPClients.detect(server: server, probe: .fake(home: home), appsRoot: apps).first { $0.kind == kind }!
        _ = try MCPFileInstaller.apply(c, install: true, server: server, ledger: ledger)
        XCTAssertEqual(MCPClients.state(c), .installed)
        _ = try MCPFileInstaller.apply(c, install: false, server: server, now: Date().addingTimeInterval(5), ledger: ledger)
        return try? String(contentsOf: c.configFile, encoding: .utf8)
    }

    func testRemovalRestoresExactBytes() throws {
        app("Claude"); app("Antigravity"); app("Cursor")
        let desktop = "{\n  \"preferences\": {\n    \"x\": true\n  },\n  \"coworkUserFilesPath\": \"/a b\"\n}"
        XCTAssertEqual(try roundTrip("Library/Application Support/Claude/claude_desktop_config.json", desktop, client: .claudeDesktop), desktop)
        XCTAssertEqual(try roundTrip(".cursor/mcp.json", "{}", client: .cursor), "{}")
        XCTAssertEqual(try roundTrip(".gemini/config/mcp_config.json", "", client: .antigravity), "", "empty file stays empty")
        XCTAssertEqual(try roundTrip(".gemini/config/mcp_config.json", "\n", client: .antigravity), "\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: "\(home)/.cursor/x"))
    }

    func testFileCreatedByInstallIsRemovedAgain() throws {
        app("Cursor")
        XCTAssertNil(try roundTrip(".cursor/mcp.json", nil, client: .cursor), "the file 8GB Vibe created is gone")
        XCTAssertEqual(backups(".cursor").count, 1, "the backup of what was removed stays")
    }

    func testEmptyServersKeptWhenNotOurs() throws {
        app("Cursor")
        // "mcpServers" was there before: keep it, even empty.
        XCTAssertEqual(try roundTrip(".cursor/mcp.json", "{\"mcpServers\": {}}", client: .cursor), "{\"mcpServers\": {}}")
        // We added "mcpServers", then the user added a server: keep it with that server.
        put(".cursor/mcp.json", "{\"a\": 1}")
        let c = MCPClients.detect(server: server, probe: .fake(home: home), appsRoot: apps).first { $0.kind == .cursor }!
        _ = try MCPFileInstaller.apply(c, install: true, server: server, ledger: ledger)
        let withUser = try JSONServerEdit.add(read(".cursor/mcp.json").replacingOccurrences(of: "8gbvibe", with: "user-server"), entry: ["command": "x"])
        put(".cursor/mcp.json", withUser)
        _ = try MCPFileInstaller.apply(c, install: false, server: server, now: Date().addingTimeInterval(5), ledger: ledger)
        XCTAssertTrue(read(".cursor/mcp.json").contains("user-server"))
        // No ledger entry (installed by an older version): only our key goes.
        put(".cursor/mcp.json", "{\"a\": 1, \"mcpServers\": {\"8gbvibe\": {\"command\": \"x\"}}}")
        _ = try MCPFileInstaller.apply(c, install: false, server: server, now: Date().addingTimeInterval(9), ledger: ledger)
        XCTAssertEqual(read(".cursor/mcp.json"), "{\"a\": 1, \"mcpServers\": {}}")
    }

    func testConnectedIsSeparateFromInstalled() {
        var s = HubState()
        s.agents = [AgentRecord(id: "a1", tool: "Codex CLI", project: "api", task: nil, pid: 1, registeredAt: Date(), lastSeen: Date())]
        XCTAssertEqual(MCPClients.connected(.codex, in: s).count, 1)
        XCTAssertTrue(MCPClients.connected(.claudeCode, in: s).isEmpty)
    }
}

/// Runs only with VIBE_REAL_COPY=<dir> (a temp copy of real config files): install then remove must give back
/// the exact original bytes. Never touches the real files.
final class MCPRealCopyTests: XCTestCase {
    func testRoundTripOnCopies() throws {
        guard let dir = ProcessInfo.processInfo.environment["VIBE_REAL_COPY"] else { throw XCTSkip("no copy dir") }
        let probe = MCPProbe.fake(home: "\(dir)/home")
        let list = MCPClients.detect(server: "/Applications/8GB Vibe.app/Contents/Helpers/8gbvibe-mcp", probe: probe, appsRoot: "\(dir)/Applications")
        let files = list.filter { if case .command = $0.method { return false }; return true }
        XCTAssertFalse(files.isEmpty)
        for c in files {
            let before = (try? String(contentsOf: c.configFile, encoding: .utf8)) ?? ""
            print("client", c.kind.rawValue, "state", MCPClients.state(c))
            let ledger = URL(fileURLWithPath: "\(dir)/mcp-installs.json")
            _ = try MCPFileInstaller.apply(c, install: true, server: "/Applications/8GB Vibe.app/Contents/Helpers/8gbvibe-mcp", ledger: ledger)
            XCTAssertEqual(MCPClients.state(c), .installed, c.kind.rawValue)
            _ = try MCPFileInstaller.apply(c, install: false, server: "", now: Date().addingTimeInterval(3), ledger: ledger)
            let after = try String(contentsOf: c.configFile, encoding: .utf8)
            XCTAssertEqual(after, before, c.kind.rawValue)
            print(c.kind.rawValue, before == after ? "identical after remove" : "differs: \(before.count) vs \(after.count)")
        }
    }
}
