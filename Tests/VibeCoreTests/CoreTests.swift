import XCTest
@testable import VibeCore

final class FormatTests: XCTestCase {
    func testSize() {
        XCTAssertEqual(Format.bytes(UInt64(8.8 * Format.GB)), "8,8 GB")
        XCTAssertEqual(Format.bytes(512 * 1024 * 1024), "512 MB")
        XCTAssertEqual(Format.bytes(UInt64(1536 * Format.GB)), "1.536,0 GB")
    }

    func testDuration() {
        XCTAssertEqual(Format.duration(30), "30 giây")
        XCTAssertEqual(Format.duration(40 * 60), "40 phút")
        XCTAssertEqual(Format.duration(42 * 3600), "1 ngày 18 giờ")
        XCTAssertEqual(Format.duration(48 * 3600), "2 ngày")
    }
}

final class MemoryTests: XCTestCase {
    func testFromPageCounts() {
        // Real numbers measured on an 8 GB Mac, 16 KB pages.
        let memoryInfo = Memory.fromPageCounts(internalPages: 84336, purgeable: 0, wired: 154755, compressor: 197090,
                                 external: 50422, free: 4261, pageSize: 16384, total: 8 << 30)
        XCTAssertEqual(memoryInfo.wired, 154755 * 16384)
        XCTAssertEqual(memoryInfo.used, (84336 + 154755 + 197090) * 16384)
        XCTAssertEqual(memoryInfo.usedRatio, Double(memoryInfo.used) / Double(8 << 30), accuracy: 1e-9)
    }

    func testPurgeableAboveInternal() {
        let memoryInfo = Memory.fromPageCounts(internalPages: 10, purgeable: 20, wired: 0, compressor: 0, external: 0, free: 0, pageSize: 1, total: 100)
        XCTAssertEqual(memoryInfo.app, 0)
        XCTAssertEqual(memoryInfo.cache, 20)
    }
}

final class ProcArgsTests: XCTestCase {
    func testParse() {
        var buf: [UInt8] = []
        withUnsafeBytes(of: Int32(3)) { buf.append(contentsOf: $0) }
        // Appended one C string at a time: older Swift compilers (Xcode 16) time out type-checking one long `+` chain.
        func cString(_ s: String) -> [UInt8] { Array(s.utf8) + [0] }
        buf += cString("/usr/bin/java")
        buf += [0, 0]
        for arg in ["java", "-cp", "org.gradle.launcher.daemon.bootstrap.GradleDaemon", "PATH=/bin"] {
            buf += cString(arg)
        }
        XCTAssertEqual(ProcessReader.parseProcArgs(buf), ["java", "-cp", "org.gradle.launcher.daemon.bootstrap.GradleDaemon"])
    }
}

func makeProcess(_ pid: Int32, _ ppid: Int32, _ path: String, uid: UInt32 = 501, startDate: TimeInterval = 0,
        fp: UInt64? = 100, cpu: UInt64? = 0, args: [String] = []) -> ProcessRecord {
    ProcessRecord(pid: pid, ppid: ppid, uid: uid, name: (path as NSString).lastPathComponent, path: path,
              startDate: Date(timeIntervalSince1970: startDate), footprint: fp, cpuNanos: cpu, arguments: args)
}

final class ProcessClassifierTests: XCTestCase {
    let claudeCode = "/Users/u/Library/Application Support/Claude/claude-code/2.1.309/abc/claude.app/Contents/MacOS/claude"
    let vm = "/System/Library/Frameworks/Virtualization.framework/Versions/A/XPCServices/com.apple.Virtualization.VirtualMachine.xpc/Contents/MacOS/com.apple.Virtualization.VirtualMachine"

    func testSingleRules() {
        let items: [(String, Classification)] = [
            ("/Applications/Claude.app/Contents/MacOS/Claude", Classification(.claude, ItemName.appClaude)),
            ("/Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app/Contents/MacOS/Claude Helper (Renderer)", Classification(.claude, ItemName.appClaude)),
            (claudeCode, Classification(.claude, ItemName.claudeCode)),
            ("/Applications/Xcode.app/Contents/MacOS/Xcode", Classification(.xcode, ItemName.xcode)),
            ("/Library/Developer/CoreSimulator/Volumes/iOS_23F77/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 26.5.simruntime/Contents/Resources/RuntimeRoot/usr/libexec/dasd", Classification(.xcode, ItemName.simulator)),
            ("/Applications/Zalo.app/Contents/Frameworks/Zalo Helper (Renderer).app/Contents/MacOS/Zalo Helper (Renderer)", Classification(.chat, "Zalo")),
            ("/Applications/Docker.app/Contents/MacOS/com.docker.backend", Classification(.docker, ItemName.dockerDesktop)),
            ("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", Classification(.browsers, "Google Chrome")),
            ("/Users/u/Library/Application Support/SynologyDrive/SynologyDrive.app/Contents/MacOS/cloud-drive-daemon", Classification(.cloudSync, "Synology Drive"))
        ]
        for (p, expected) in items {
            XCTAssertEqual(ProcessClassifier.classifyOne(makeProcess(1, 1, p)).0, expected, p)
        }
    }

    func testGradleByArguments() {
        let t = makeProcess(5, 1, "/Library/Java/JavaVirtualMachines/jdk/Contents/Home/bin/java",
                   args: ["java", "org.gradle.launcher.daemon.bootstrap.GradleDaemon", "8.10"])
        XCTAssertEqual(ProcessClassifier.classifyOne(t).0, Classification(.android, ItemName.gradle))
    }

    func testChildInheritsParent() {
        // node (MCP server) running under a Claude Code session counts toward Claude Code.
        let list = [makeProcess(10, 1, claudeCode), makeProcess(11, 10, "/opt/homebrew/bin/node"), makeProcess(12, 11, "/usr/bin/git")]
        let result = ProcessClassifier.classify(list)
        XCTAssertEqual(result[11], Classification(.claude, ItemName.claudeCode))
        XCTAssertEqual(result[12], Classification(.claude, ItemName.claudeCode))
    }

    func testRootProcessDoesNotInherit() {
        let list = [makeProcess(10, 1, claudeCode), makeProcess(11, 10, "/usr/sbin/something", uid: 0)]
        XCTAssertEqual(ProcessClassifier.classify(list)[11], Classification(.system, ItemName.system))
    }

    func testGuessVMOwner() {
        // Claude opened at 0, Docker at 1000. A VM started at 600 belongs to Claude.
        let list = [
            makeProcess(1176, 1, "/Applications/Claude.app/Contents/MacOS/Claude", startDate: 0),
            makeProcess(2000, 1, "/Applications/Docker.app/Contents/MacOS/com.docker.backend", startDate: 1000),
            makeProcess(3670, 1, vm, startDate: 600),
            makeProcess(3700, 1, vm, startDate: 1010)
        ]
        let result = ProcessClassifier.classify(list)
        XCTAssertEqual(result[3670], Classification(.claude, ItemName.claudeVM))
        XCTAssertEqual(result[3700], Classification(.docker, ItemName.dockerVM))
    }

    func testVMWithUnknownOwner() {
        XCTAssertEqual(ProcessClassifier.classify([makeProcess(5, 1, vm, startDate: 5)])[5], Classification(.other, ItemName.otherVM))
    }
}

final class ProcessAnalyzerTests: XCTestCase {
    let claudeCodePath = "/Users/u/Library/Application Support/Claude/claude-code/2.1.309/abc/claude.app/Contents/MacOS/claude"

    func testCPUAndSessions() {
        let engine = ProcessAnalyzer(readWorkingDirectory: { _ in "/Users/u/CODE/du-an" })
        let t0 = Date(timeIntervalSince1970: 1000)
        // Each session: a wrapper process (parent) plus the real claude process (child), like Claude desktop.
        func items(cpuA: UInt64, cpuB: UInt64) -> [ProcessRecord] {
            [makeProcess(100, 1, claudeCodePath, fp: 0, cpu: 0), makeProcess(101, 100, claudeCodePath, fp: 250 << 20, cpu: cpuA),
             makeProcess(102, 101, "/opt/homebrew/bin/node", fp: 50 << 20, cpu: 0),
             makeProcess(200, 1, claudeCodePath, fp: 0, cpu: 0), makeProcess(201, 200, claudeCodePath, fp: 200 << 20, cpu: cpuB)]
        }
        _ = engine.analyze(items(cpuA: 0, cpuB: 0), now: t0)
        // 10 seconds later: session A used 5 seconds of CPU (50 %), session B used none.
        let result = engine.analyze(items(cpuA: 5_000_000_000, cpuB: 0), now: t0.addingTimeInterval(10))
        XCTAssertEqual(result.sessions.count, 2)
        let a = result.sessions.first { $0.pid == 100 }!
        let b = result.sessions.first { $0.pid == 200 }!
        XCTAssertEqual(a.footprint, 300 << 20)
        XCTAssertEqual(a.cpu, 50, accuracy: 0.01)
        XCTAssertEqual(a.lastActive, t0.addingTimeInterval(10))
        XCTAssertEqual(b.lastActive, t0)
        XCTAssertEqual(a.projectName, "du-an")

        let suggestions = SuggestionBuilder.from(result, idleTime: 5, now: t0.addingTimeInterval(10))
        XCTAssertEqual(suggestions.first?.kind, Suggestion.Kind.archiveClaudeSessions)
        XCTAssertEqual(suggestions.first?.freed, 200 << 20)
    }

    func testBudget() {
        let engine = ProcessAnalyzer(readWorkingDirectory: { _ in nil })
        let result = engine.analyze([makeProcess(1, 1, "/Applications/Claude.app/Contents/MacOS/Claude", fp: 6 << 30),
                              makeProcess(2, 1, "/Applications/Zalo.app/Contents/MacOS/Zalo", fp: 1 << 30)], now: Date())
        let memoryInfo = Memory(total: 8 << 30, app: 0, wired: 2 << 30, compressed: 0, cache: 0, free: 0)
        let budget = RAMBudget(memory: memoryInfo, snapshot: result)
        XCTAssertEqual(budget.demand, 9 << 30)
        XCTAssertEqual(budget.overflow, 1 << 30)
    }
}

final class ThresholdsTests: XCTestCase {
    func makeSnapshot(swapGB: Double, freeGB: Double, load5: Double, pressure: MemoryPressure = .normal) -> SystemSnapshot {
        SystemSnapshot(timestamp: Date(), memory: Memory(total: 8 << 30, app: 0, wired: 0, compressed: 0, cache: 0, free: 0),
                       pressure: pressure, swap: Swap(total: 0, used: UInt64(swapGB * Format.GB)),
                       disk: Disk(total: 460 << 30, free: UInt64(freeGB * Format.GB)),
                       load: LoadAverage(m1: 0, m5: load5, m15: 0), coreCount: 8)
    }

    func testEvaluate() {
        let m = Thresholds().evaluate(makeSnapshot(swapGB: 8.8, freeGB: 29, load5: 30, pressure: .warning), sessionCount: 16)
        XCTAssertEqual(m[.swap], .critical)
        XCTAssertEqual(m[.disk], .warning)
        XCTAssertEqual(m[.load], .warning)
        XCTAssertEqual(m[.pressure], .warning)
        XCTAssertEqual(m[.claudeSessions], .critical)
        XCTAssertEqual(m[.slowMac], .critical, "swap above red and load above yellow")
        XCTAssertEqual(Thresholds().evaluate(makeSnapshot(swapGB: 8.8, freeGB: 100, load5: 10, pressure: .warning), sessionCount: 0)[.slowMac], .ok,
                       "high swap with an idle CPU is not slow yet")
        XCTAssertEqual(Thresholds().evaluate(makeSnapshot(swapGB: 4, freeGB: 100, load5: 20, pressure: .warning), sessionCount: 0)[.slowMac], .warning)
        XCTAssertEqual(Thresholds().evaluate(makeSnapshot(swapGB: 1, freeGB: 100, load5: 4), sessionCount: 2).values.max(), .ok)
    }

    func testThrottleSendsOnlyWhenRising() {
        var engine = AlertThrottle(interval: 600)
        let t = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(engine.check([.swap: .warning], now: t).count, 1)
        XCTAssertEqual(engine.check([.swap: .warning], now: t.addingTimeInterval(5)).count, 0, "no change, no notification")
        XCTAssertEqual(engine.check([.swap: .critical], now: t.addingTimeInterval(10)).count, 0, "interval not over yet")
        XCTAssertEqual(engine.check([.swap: .ok], now: t.addingTimeInterval(700)).count, 0)
        XCTAssertEqual(engine.check([.swap: .critical], now: t.addingTimeInterval(800)).count, 1)
    }
}

final class BackgroundItemsTests: XCTestCase {
    func testParse() {
        let m = BackgroundItemReader.analyze(["Label": "com.x.agent", "ProgramArguments": ["/usr/local/bin/x", "-d"],
                                     "RunAtLoad": true, "KeepAlive": ["SuccessfulExit": false]],
                                    file: "/Library/LaunchAgents/com.x.agent.plist", scope: .allUsers)
        XCTAssertEqual(m.label, "com.x.agent")
        XCTAssertEqual(m.program, "/usr/local/bin/x")
        XCTAssertTrue(m.runAtLoad)
        XCTAssertTrue(m.keepAlive)
    }
}

final class CandidateTests: XCTestCase {
    func app(_ pid: Int32, _ bundlePath: String, id: String?, before: Bool = false) -> RunningApp {
        RunningApp(pid: pid, bundleId: id, name: ((bundlePath as NSString).lastPathComponent as NSString).deletingPathExtension,
                      bundlePath: bundlePath, isFrontmost: before)
    }

    /// Chrome started twice (two profiles) is two NSRunningApplications with one bundle path:
    /// one row, RAM counted once, both copies quit together.
    func testSameBundleRunningTwiceIsOneRow() {
        let engine = ProcessAnalyzer(readWorkingDirectory: { _ in nil })
        let t0 = Date(timeIntervalSince1970: 0)
        let chrome = "/Applications/Google Chrome.app"
        let apps = [app(10, chrome, id: "com.google.Chrome"), app(20, chrome, id: "com.google.Chrome", before: true)]
        let list = [
            makeProcess(10, 1, chrome + "/Contents/MacOS/Google Chrome", fp: 500 << 20),
            makeProcess(11, 10, chrome + "/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper", fp: 100 << 20),
            makeProcess(20, 1, chrome + "/Contents/MacOS/Google Chrome", startDate: 5, fp: 400 << 20),
        ]
        let result = engine.analyze(list, apps: apps, now: t0)
        let rows = result.apps.filter { $0.app.bundlePath == chrome }
        XCTAssertEqual(rows.count, 1, "one row per bundle")
        XCTAssertEqual(rows.first?.footprint, 1000 << 20, "RAM counted once, not once per copy")
        XCTAssertEqual(rows.first?.app.pid, 20, "the frontmost copy stands for the app")
        XCTAssertEqual(rows.first?.otherInstances, [ProcessIdentity(pid: 10, startDate: t0)])

        let candidates = CandidateBuilder.from(result).filter { $0.id == "app:\(chrome)" }
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.quitMethod,
                       .app(ProcessIdentity(pid: 20, startDate: t0.addingTimeInterval(5)), bundleId: "com.google.Chrome",
                            others: [ProcessIdentity(pid: 10, startDate: t0)]))
    }

    func testListAndIdle() {
        let engine = ProcessAnalyzer(readWorkingDirectory: { _ in nil })
        let t0 = Date(timeIntervalSince1970: 0)
        let apps = [
            app(1, "/Applications/Xcode.app", id: "com.apple.dt.Xcode"),
            app(2, "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app", id: "com.apple.iphonesimulator"),
            app(3, "/Applications/Claude.app", id: "com.anthropic.claudefordesktop"),
            app(4, "/Applications/8GB Vibe.app", id: "vn.beeca.8gbvibe"),
            app(5, "/Applications/Google Chrome.app", id: "com.google.Chrome", before: true)
        ]
        let list = [
            makeProcess(1, 1, "/Applications/Xcode.app/Contents/MacOS/Xcode", fp: 900 << 20),
            makeProcess(2, 1, "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app/Contents/MacOS/Simulator", fp: 100 << 20),
            makeProcess(20, 1, "/Library/Developer/CoreSimulator/Volumes/iOS/RuntimeRoot/usr/libexec/dasd", fp: 300 << 20),
            makeProcess(3, 1, "/Applications/Claude.app/Contents/MacOS/Claude", fp: 1 << 30),
            makeProcess(4, 1, "/Applications/8GB Vibe.app/Contents/MacOS/8GBVibe", fp: 20 << 20),
            makeProcess(5, 1, "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", fp: 400 << 20),
            makeProcess(6, 1, "/usr/bin/java", fp: 700 << 20, args: ["java", "org.gradle.launcher.daemon.bootstrap.GradleDaemon"])
        ]
        _ = engine.analyze(list, apps: apps, now: t0)
        let result = engine.analyze(list, apps: apps, now: t0.addingTimeInterval(3600))
        let uv = CandidateBuilder.from(result, selfIdentifier: "vn.beeca.8gbvibe")
        let byID = Dictionary(uniqueKeysWithValues: uv.map { ($0.id, $0) })

        XCTAssertNil(byID["app:/Applications/8GB Vibe.app"], "never lists itself")
        XCTAssertEqual(byID["app:/Applications/Xcode.app"]?.footprint, 900 << 20, "Simulator.app is not counted in Xcode")
        XCTAssertEqual(byID["simulator"]?.footprint, 400 << 20)
        XCTAssertNotNil(byID["app:/Applications/Claude.app"]?.blockedReason)
        XCTAssertEqual(byID["android/Gradle"]?.quitMethod, .processes([ProcessIdentity(pid: 6, startDate: t0)]))

        let suggestions = SuggestionBuilder.from(result, idleTime: 1800, selfIdentifier: "vn.beeca.8gbvibe", now: t0.addingTimeInterval(3600))
        let ids = Set(suggestions.map(\.id))
        XCTAssertTrue(ids.contains("app:/Applications/Xcode.app"))
        XCTAssertTrue(ids.contains("simulator"))
        XCTAssertTrue(ids.contains("android/Gradle"))
        XCTAssertFalse(ids.contains("app:/Applications/Google Chrome.app"), "the frontmost app is never suggested")
        XCTAssertFalse(ids.contains("app:/Applications/Claude.app"), "Claude is blocked, never suggested")
    }

    func testSlowMacCritical() {
        let h = SystemSnapshot(timestamp: Date(), memory: Memory(total: 8 << 30, app: 0, wired: 0, compressed: 0, cache: 0, free: 0),
                               pressure: .warning, swap: Swap(total: 0, used: 10 << 30),
                               disk: Disk(total: 460 << 30, free: 100 << 30), load: LoadAverage(m1: 0, m5: 25, m15: 0), coreCount: 8)
        XCTAssertEqual(Thresholds().evaluate(h, sessionCount: 0)[.slowMac], .critical)
    }
}

final class HealthScoreTests: XCTestCase {
    func makeSnapshot(pressure: MemoryPressure, swapGB: Double, load5: Double, freeGB: Double) -> SystemSnapshot {
        SystemSnapshot(timestamp: Date(), memory: Memory(total: 8 << 30, app: 0, wired: 0, compressed: 0, cache: 0, free: 0),
                       pressure: pressure, swap: Swap(total: 0, used: UInt64(swapGB * Format.GB)),
                       disk: Disk(total: 460 << 30, free: UInt64(freeGB * Format.GB)),
                       load: LoadAverage(m1: 0, m5: load5, m15: 0), coreCount: 8)
    }

    func testHealthyMac() {
        XCTAssertEqual(HealthScore.compute(makeSnapshot(pressure: .normal, swapGB: 0.5, load5: 3, freeGB: 120), thresholds: Thresholds()), 100)
    }

    func testOverloadedMac() {
        // Real numbers measured on the morning of 08/11/2026: pressure warning, swap 10.8 GB, load 82, 71 GB free disk,
        // with the Mac actively swapping.
        let d = HealthScore.compute(makeSnapshot(pressure: .warning, swapGB: 10.8, load5: 82, freeGB: 71), thresholds: Thresholds(),
                                    swapIO: 8 * 1_048_576)
        XCTAssertLessThan(d, 40)
        XCTAssertEqual(HealthScore.summary(d), "Máy đang quá tải")
    }

    /// A large swap file without swap I/O costs nothing; only swapping in or out lowers the score.
    func testScoreFollowsSwapIONotSwapSize() {
        let n = Thresholds()
        let quiet = HealthScore.compute(makeSnapshot(pressure: .normal, swapGB: 12, load5: 4, freeGB: 100), thresholds: n, swapIO: 0)
        XCTAssertEqual(quiet, 100)
        let unknown = HealthScore.compute(makeSnapshot(pressure: .normal, swapGB: 12, load5: 4, freeGB: 100), thresholds: n)
        XCTAssertEqual(unknown, 100)
        let mb = 1_048_576.0
        let a = HealthScore.compute(makeSnapshot(pressure: .normal, swapGB: 2, load5: 4, freeGB: 100), thresholds: n, swapIO: 0.5 * mb)
        let b = HealthScore.compute(makeSnapshot(pressure: .normal, swapGB: 2, load5: 4, freeGB: 100), thresholds: n, swapIO: 2 * mb)
        let c = HealthScore.compute(makeSnapshot(pressure: .normal, swapGB: 2, load5: 4, freeGB: 100), thresholds: n, swapIO: 6 * mb)
        XCTAssertGreaterThan(quiet, a)
        XCTAssertGreaterThan(a, b)
        XCTAssertGreaterThan(b, c)
        XCTAssertEqual(c, 75)
    }
}

final class ThresholdsStorageTests: XCTestCase {
    /// Thresholds saved by earlier versions use the old keys and must still load.
    func testDecodesLegacyKeys() throws {
        let json = #"{"swapVangGB":2,"swapDoGB":5,"oTrongVangGB":30,"oTrongDoGB":15,"tai5Vang":12,"tai5Do":24,"phienVang":4,"phienDo":8,"phutRanh":20}"#
        let t = try JSONDecoder().decode(Thresholds.self, from: Data(json.utf8))
        XCTAssertEqual(t.swapYellowGB, 2)
        XCTAssertEqual(t.diskFreeRedGB, 15)
        XCTAssertEqual(t.sessionsRed, 8)
        XCTAssertEqual(t.idleMinutes, 20)
        let roundTrip = try JSONDecoder().decode(Thresholds.self, from: JSONEncoder().encode(t))
        XCTAssertEqual(roundTrip, t)
    }
}
