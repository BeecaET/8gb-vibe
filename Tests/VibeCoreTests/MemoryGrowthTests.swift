import XCTest
@testable import VibeCore

final class MemoryGrowthTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 100_000)
    let mb: UInt64 = 1 << 20

    /// One point per minute for `minutes` minutes, value from `f(minute)`.
    func series(_ minutes: Int, _ f: (Int) -> UInt64) -> [(Date, UInt64)] {
        (0...minutes).map { (t0.addingTimeInterval(Double($0) * 60), f($0)) }
    }

    func testSteadyGrowthIsReported() {
        let p = series(31) { 500 * mb + UInt64($0) * 15 * mb }   // +150 MB per 10 minutes
        guard case let .growing(step)? = MemoryGrowth.check(p, now: p.last!.0) else { return XCTFail("expected growing") }
        XCTAssertEqual(Double(step) / Double(mb), 150, accuracy: 20)
    }

    func testFlatOrNoisyIsNotReported() {
        XCTAssertNil(MemoryGrowth.check(series(31) { _ in 600 * mb }, now: t0.addingTimeInterval(31 * 60)))
        // Up then down: not steady.
        XCTAssertNil(MemoryGrowth.check(series(31) { $0 < 20 ? 500 * mb + UInt64($0) * 20 * mb : 600 * mb }, now: t0.addingTimeInterval(31 * 60)))
    }

    func testShortHistoryIsNotReported() {
        let p = series(12) { 500 * mb + UInt64($0) * 50 * mb }
        XCTAssertNil(MemoryGrowth.check(p, now: p.last!.0))
    }

    func testLargeSessionIsReportedAtOnce() {
        XCTAssertEqual(MemoryGrowth.check([(t0, 2300 * mb)], now: t0), .large)
    }

    func testWiredRise() {
        let rising = series(31) { 1500 * mb + UInt64($0) * 30 * mb }   // kernel leak at 30 MB/min
        XCTAssertNotNil(MemoryGrowth.wiredRise(rising, now: rising.last!.0))
        XCTAssertNil(MemoryGrowth.wiredRise(series(31) { _ in 1800 * mb }, now: t0.addingTimeInterval(31 * 60)))
    }

    func testTrendHistoryKeepsOnePointPerMinute() {
        let h = TrendHistory()
        for s in 0..<600 { h.add("a", UInt64(s), now: t0.addingTimeInterval(Double(s) * 5)) }   // 50 minutes every 5 s
        let p = h.get("a")
        XCTAssertLessThanOrEqual(p.count, 36)
        XCTAssertEqual(p.last?.1, 599)
        h.keep(only: [])
        XCTAssertTrue(h.get("a").isEmpty)
    }

    /// End to end: a Claude Code session growing for 30 minutes becomes a suggestion; nothing is done automatically.
    func testAnalyzerSuggestsRestartingGrowingSession() {
        let e = ProcessAnalyzer(readWorkingDirectory: { _ in "/Users/u/shop" }, readPorts: { _ in [] }, uid: 501)
        let claude = "/Users/u/.local/share/claude/versions/2.1.400/claude"
        var last = ProcessSnapshot.empty
        for m in 0...31 {
            let p = makeProcess(100, 1, claude, startDate: 10, fp: 400 * mb + UInt64(m) * 20 * mb)
            last = e.analyze([p], now: t0.addingTimeInterval(Double(m) * 60))
        }
        XCTAssertEqual(last.memoryWarnings.first?.projectName, "shop")
        let s = SuggestionBuilder.from(last, idleTime: 3600, now: t0.addingTimeInterval(31 * 60))
        let g = s.first { if case .restartSession = $0.kind { return true }; return false }
        XCTAssertNotNil(g)
        XCTAssertTrue(g?.detail.contains("claude -c") ?? false)
    }
}

final class AgentDetectionTests: XCTestCase {
    func testAntigravityCLI() {
        XCTAssertEqual(DevProcessClassifier.agentName(makeProcess(1, 1, "/opt/homebrew/bin/agy")), "Antigravity CLI")
    }

    /// Codex runs commands inside sandbox-exec: a dev server started that way belongs to the Codex session.
    func testSandboxExecIsSkippedWhenFindingOwner() {
        let list = [
            makeProcess(10, 1, "/opt/homebrew/bin/codex"),
            makeProcess(11, 10, "/usr/bin/sandbox-exec"),
            makeProcess(12, 11, "/bin/zsh"),
            makeProcess(13, 12, "/opt/homebrew/bin/node", args: ["node", "/Users/u/web/node_modules/.bin/vite"])
        ]
        let ds = DevServerBuilder.from(list, ports: [13: [ListeningPort(number: 5173, localOnly: true)]], cpu: [:],
                                       directory: { _ in "/Users/u/web" }, lastActive: { _, _ in Date() })
        XCTAssertEqual(ds.first?.owner, .agent(name: "Codex CLI", directory: "/Users/u/web"))
    }
}
