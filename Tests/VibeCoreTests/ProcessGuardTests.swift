import XCTest
@testable import VibeCore

final class ProcessGuardTests: XCTestCase {
    private func reason(_ path: String, name: String? = nil, pid: Int32 = 5000, claudeCode: Bool = false) -> String? {
        ProcessGuard.reason(pid: pid, name: name ?? (path as NSString).lastPathComponent, path: path,
                   isClaudeCode: claudeCode, selfIdentifier: 4000)
    }

    func testSystemProcessesBlocked() {
        XCTAssertNotNil(reason("/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow"))
        XCTAssertNotNil(reason("/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"))
        XCTAssertNotNil(reason("/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock"))
        XCTAssertNotNil(reason("/System/Library/CoreServices/SystemUIServer.app/Contents/MacOS/SystemUIServer"))
        XCTAssertNotNil(reason("/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter"))
        XCTAssertNotNil(reason("/usr/libexec/trustd"))
        XCTAssertNotNil(reason("/usr/sbin/cfprefsd"))
    }

    func testUnreadablePathStillBlockedByName() {
        XCTAssertNotNil(reason("", name: "loginwindow"))
        XCTAssertNotNil(reason("", name: "Dock"))
        XCTAssertNotNil(reason("", name: "WindowServer"))
    }

    func testLoginwindowHasOwnReason() {
        XCTAssertTrue(reason("/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow")!.contains("logs you out"))
    }

    func testClaudeAndClaudeCodeAreBlocked() {
        XCTAssertNotNil(reason("/Applications/Claude.app/Contents/MacOS/Claude"))
        XCTAssertNotNil(reason("/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper"))
        XCTAssertNotNil(reason("/opt/homebrew/bin/node", claudeCode: true))
        let cli = ProcessRecord(pid: 6000, ppid: 1, uid: 501, name: "node", path: "/opt/homebrew/bin/node", startDate: Date(),
                            footprint: nil, cpuNanos: nil, arguments: ["node", "/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js"])
        XCTAssertNotNil(ProcessGuard.reason(cli, selfIdentifier: 4000))
    }

    func testSelfAndLowPIDs() {
        XCTAssertNotNil(reason("/Applications/8GB Vibe.app/Contents/MacOS/8GBVibe", pid: 4000))
        XCTAssertNotNil(reason("/sbin/launchd", pid: 1))
        XCTAssertNotNil(reason("/x", pid: 0))
    }

    func testRegularProcessCanQuit() {
        XCTAssertNil(reason("/bin/sleep"))
        XCTAssertNil(reason("/opt/homebrew/bin/node"))
        XCTAssertNil(reason("/Applications/Docker.app/Contents/MacOS/com.docker.backend"))
        XCTAssertNil(reason("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"))
        // Apple apps in /System/Applications can still be quit.
        XCTAssertNil(reason("/System/Applications/Mail.app/Contents/MacOS/Mail"))
        XCTAssertNil(reason("/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app/Contents/MacOS/Safari"))
    }

    func testProcessRowKind() {
        let t = ProcessRow(id: "1", pid: 6001, name: "node", path: "/usr/local/bin/node",
                                 kind: Classification(.claude, ItemName.claudeCode), footprint: nil, cpu: 0, startDate: Date())
        XCTAssertNotNil(ProcessGuard.reason(t, selfIdentifier: 4000))
        var other = t
        other.kind = Classification(.other, "Other")
        XCTAssertNil(ProcessGuard.reason(other, selfIdentifier: 4000))
    }

    /// Reads real processes, sends no signal.
    func testReadsRealProcesses() throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        p.arguments = ["30"]
        try p.run()
        defer { p.terminate() }
        XCTAssertNil(ProcessGuard.currentReason(pid: p.processIdentifier))
        XCTAssertNotNil(ProcessGuard.currentReason(pid: getpid()))

        var cache: [String: (String, [String])] = [:]
        if let lw = ProcessReader.readAll(cache: &cache).first(where: { $0.name == "loginwindow" }) {
            XCTAssertNotNil(ProcessGuard.currentReason(pid: lw.pid))
        }
    }
}
