import XCTest
@testable import VibeCore

final class VMRatesTests: XCTestCase {
    func testRatesBetweenTwoSamples() {
        let a = VMCounters(swapIns: 100, swapOuts: 200, compressions: 1000, decompressions: 500, pageouts: 10, pageSize: 16384)
        let b = VMCounters(swapIns: 420, swapOuts: 200, compressions: 1500, decompressions: 600, pageouts: 10, pageSize: 16384)
        let r = VMRates.between(a, b, seconds: 5)!
        XCTAssertEqual(r.swapInBytes, 320 * 16384 / 5, accuracy: 0.1)
        XCTAssertEqual(r.swapOutBytes, 0)
        XCTAssertEqual(r.compressions, 100, accuracy: 0.01)
        XCTAssertEqual(r.decompressions, 20, accuracy: 0.01)
        // Counter went backwards (reboot) or no time passed: no rate.
        XCTAssertNil(VMRates.between(b, a, seconds: 5))
        XCTAssertNil(VMRates.between(a, b, seconds: 0))
    }

    func testReadsRealCounters() {
        XCTAssertNotNil(VMCounters.read())
    }
}

final class HeavyJobTests: XCTestCase {
    let node = "/opt/homebrew/bin/node"

    func testOneXcodeBuildCountsOnce() {
        let list = [
            makeProcess(10, 1, "/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild"),
            makeProcess(11, 10, "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend"),
            makeProcess(12, 10, "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend")
        ]
        let jobs = HeavyJobDetector.jobs(list, cpu: [11: 90, 12: 80])
        XCTAssertEqual(jobs.map(\.kind), ["Xcode build"])
    }

    func testBusyCompilersFromXcodeGUIGroupedByParent() {
        let service = "/Applications/Xcode.app/Contents/SharedFrameworks/XCBuild.framework/Versions/A/PlugIns/XCBBuildService.bundle/Contents/MacOS/XCBBuildService"
        let cc = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend"
        let list = [makeProcess(20, 1, service), makeProcess(21, 20, cc), makeProcess(22, 20, cc), makeProcess(23, 20, cc)]
        XCTAssertEqual(HeavyJobDetector.jobs(list, cpu: [21: 90, 22: 90, 23: 5]).count, 1)
        // Idle compilers are not a job.
        XCTAssertTrue(HeavyJobDetector.jobs(list, cpu: [:]).isEmpty)
    }

    func testOverlappingJobsAndNonJobs() {
        let list = [
            makeProcess(30, 1, node, args: ["node", "/opt/homebrew/lib/node_modules/npm/bin/npm-cli.js", "run", "build"]),
            makeProcess(31, 30, node, args: ["node", "/Users/u/web/node_modules/.bin/next", "build"]),
            makeProcess(40, 1, "/usr/bin/java", args: ["java", "org.gradle.launcher.daemon.bootstrap.GradleDaemon"]),
            makeProcess(50, 1, node, args: ["node", "/Users/u/shop/node_modules/.bin/vite"]),          // dev server, not a job
            makeProcess(60, 1, node, args: ["node", "/Users/u/api/node_modules/.bin/jest"])
        ]
        let busy = HeavyJobDetector.jobs(list, cpu: [40: 120])
        XCTAssertEqual(Set(busy.map(\.kind)), ["npm build", "Gradle build", "jest"])
        // An idle Gradle daemon is not building.
        XCTAssertEqual(Set(HeavyJobDetector.jobs(list, cpu: [:]).map(\.kind)), ["npm build", "jest"])
    }
}

final class MeasurementRecorderTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)   // on a minute boundary
    let page: UInt64 = 16384

    func snapshot(_ t: Date, pressure: MemoryPressure = .normal) -> SystemSnapshot {
        SystemSnapshot(timestamp: t, memory: Memory(total: 8 << 30, app: 4 << 30, wired: 2 << 30, compressed: 1 << 30, cache: 0, free: 0),
                       pressure: pressure, swap: Swap(total: 10 << 30, used: 6 << 30), disk: Disk(total: 0, free: 0),
                       load: LoadAverage(m1: 0, m5: 0, m15: 0), coreCount: 8)
    }

    func counters(_ swapPages: UInt64) -> VMCounters {
        VMCounters(swapIns: swapPages, swapOuts: 0, compressions: 0, decompressions: 0, pageouts: 0, pageSize: page)
    }

    func processSnapshot(_ t: Date, claude: UInt64, chrome: UInt64, jobs: Int) -> ProcessSnapshot {
        var r = ProcessSnapshot.empty
        r.timestamp = t
        r.groups = [GroupUsage(group: .claude, footprint: claude, cpu: 0, processCount: 1, items: []),
                    GroupUsage(group: .browsers, footprint: chrome, cpu: 0, processCount: 1, items: [])]
        r.heavyJobs = (0..<jobs).map { HeavyJob(kind: "next build", pid: Int32(100 + $0)) }
        return r
    }

    /// Five quiet minutes, then swap starts while the Claude group grows: the first strained minute names Claude.
    func testRowsStrainAndSuspect() {
        let rec = MeasurementRecorder(store: nil, now: t0)
        var swapPages: UInt64 = 0
        for s in stride(from: 0, through: 9 * 60, by: 5) {
            let t = t0.addingTimeInterval(Double(s))
            let minute = s / 60
            if minute >= 6 { swapPages += 200 }   // 200 pages per 5 s = about 39 MB per minute
            rec.addSystem(snapshot(t), counters: counters(swapPages))
            if s % 60 == 0 {
                rec.addProcesses(processSnapshot(t, claude: (3000 + UInt64(minute) * 150) << 20, chrome: 2000 << 20, jobs: minute >= 7 ? 2 : 0))
            }
        }
        let rows = rec.rows
        XCTAssertEqual(rows.count, 9)
        XCTAssertFalse(rows[5].strained)
        XCTAssertTrue(rows[6].strained)
        XCTAssertGreaterThan(rows[6].swapInMB, MeasurementRecorder.strainSwapMB)
        XCTAssertTrue(rows[6].suspect.hasPrefix("Claude"), rows[6].suspect)
        XCTAssertEqual(rows[7].suspect, "", "only the first minute of an episode names a suspect")
        XCTAssertEqual(rows[7].heavyJobs, 2)
    }

    func testPressureAloneIsStrain() {
        let rec = MeasurementRecorder(store: nil, now: t0)
        rec.addSystem(snapshot(t0, pressure: .warning), counters: counters(0))
        rec.addSystem(snapshot(t0.addingTimeInterval(61)), counters: counters(0))
        XCTAssertEqual(rec.rows.first?.pressure, 1)
        XCTAssertEqual(rec.rows.first?.strained, true)
    }
}

final class MeasurementStoreTests: XCTestCase {
    func temp() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("8gb-test-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: u) }
        return u
    }

    func row(_ t: Date, strained: Bool = false, heavy: Int = 0, suspect: String = "") -> MinuteRow {
        MinuteRow(minute: t, pressure: strained ? 1 : 0, swapInMB: 1.5, swapOutMB: 0, compressionsPerSec: 10, decompressionsPerSec: 5,
                  pageoutMB: 0, swapUsedGB: 6.25, ramUsedPercent: 82, wiredGB: 2, heavyJobs: heavy,
                  heavyKinds: heavy > 0 ? "next build+jest" : "", strained: strained, suspect: suspect)
    }

    func testCSVRoundTripAndPrivateFiles() throws {
        let store = MeasurementStore(directory: temp())
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let r = row(t, strained: true, heavy: 2, suspect: "Claude Code (shop) +420 MB")
        store.append(r)
        store.append(row(t.addingTimeInterval(60)))
        let back = store.rows(since: t.addingTimeInterval(-1))
        XCTAssertEqual(back.count, 2)
        XCTAssertEqual(back[0], r)
        let file = try XCTUnwrap(store.files().first)
        let perms = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.intValue, 0o600)
    }

    func testOldHeaderUpgradedWhenAppending() throws {
        let dir = temp()
        let store = MeasurementStore(directory: dir)
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        store.append(row(t))
        let file = try XCTUnwrap(store.files().first)
        // Simulate a file written by 1.1.1: 14-column header and a 14-field row.
        let oldHeader = MinuteRow.header.split(separator: ",").prefix(14).joined(separator: ",")
        let oldRow = row(t).csv.split(separator: ",", omittingEmptySubsequences: false).prefix(14).joined(separator: ",")
        try Data((oldHeader + "\n" + oldRow + "\n").utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)

        store.append(row(t.addingTimeInterval(60)))
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(String(lines[0]), MinuteRow.header)
        XCTAssertEqual(store.rows(since: t.addingTimeInterval(-1)).count, 2)
        let perms = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.intValue, 0o600)
    }

    func testKeepsAtMostFourteenDays() {
        let store = MeasurementStore(directory: temp())
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        for d in 0..<20 { store.append(row(t.addingTimeInterval(Double(d) * 86_400))) }
        XCTAssertEqual(store.files().count, MeasurementStore.maxDays)
        XCTAssertEqual(store.rows(since: .distantPast).first?.minute, t.addingTimeInterval(6 * 86_400))
    }

    func testSummaryPerWorkSession() {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        var rows: [MinuteRow] = []
        // Session 1: 10 minutes, strained minutes 3-6, two overlapping jobs in minutes 4-5.
        for m in 0..<10 {
            rows.append(row(t.addingTimeInterval(Double(m) * 60), strained: (3...6).contains(m),
                            heavy: (4...5).contains(m) ? 2 : 0, suspect: m == 3 ? "Claude Code (shop) +300 MB" : ""))
        }
        // Session 2 after a 2 hour gap: 5 quiet minutes.
        for m in 0..<5 { rows.append(row(t.addingTimeInterval(7200 + Double(m) * 60))) }
        let s = MeasurementSummary.sessions(rows)
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s[0].minutes, 10)
        XCTAssertEqual(s[0].strainedMinutes, 4)
        XCTAssertEqual(s[0].strainedWithHeavy, 2)
        XCTAssertEqual(s[0].strainedResident, 2)
        XCTAssertEqual(s[0].overlapEpisodes, 1)
        XCTAssertEqual(s[0].suspects, ["Claude Code (shop) (1)"])
        XCTAssertEqual(s[1].strainedMinutes, 0)
        XCTAssertTrue(MeasurementSummary.report(rows, folder: URL(fileURLWithPath: "/tmp")).contains("2 buổi"))
    }
}

final class MeasurementLockTests: XCTestCase {
    /// A second store on the same folder (another running copy of the app) does not write.
    func testOnlyOneWriter() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("8gb-lock-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let a = MeasurementStore(directory: dir)
        let b = MeasurementStore(directory: dir)
        XCTAssertTrue(a.acquireLock())
        XCTAssertFalse(b.acquireLock())
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let r = MinuteRow(minute: t, pressure: 0, swapInMB: 0, swapOutMB: 0, compressionsPerSec: 0, decompressionsPerSec: 0,
                          pageoutMB: 0, swapUsedGB: 0, ramUsedPercent: 0, wiredGB: 0, heavyJobs: 0, heavyKinds: "", strained: false, suspect: "")
        b.append(r)
        XCTAssertTrue(a.rows(since: .distantPast).isEmpty)
        a.append(r)
        XCTAssertEqual(a.rows(since: .distantPast).count, 1)
    }
}

final class ResponsivenessTests: XCTestCase {
    func testProbeKeepsMaximaAndResets() {
        let p = ResponsivenessProbe()
        p.record(timer: 0.2)
        p.record(timer: 1.5, main: 0.3)
        p.record(main: 4.0)
        let m = p.takeMinute()
        XCTAssertEqual(m.timerLag, 1.5)
        XCTAssertEqual(m.mainLag, 4.0)
        XCTAssertEqual(p.takeMinute().mainLag, 0)
    }

    /// Rows written before the lag columns existed still load.
    func testOldRowsStillParse() {
        let old = "2027-01-15T08:00:00Z,1,1.5,0.0,10,5,0.0,6.25,82,2.00,0,,1,"
        let r = MinuteRow(csv: old)
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.mainLagMs, 0)
        var new = r!
        new.mainLagMs = 1234; new.timerLagMs = 56; new.sampleGapS = 21.5
        XCTAssertEqual(MinuteRow(csv: new.csv), new)
    }

    func testRecorderRecordsSampleGap() {
        let rec = MeasurementRecorder(store: nil)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let s = { (t: Date) in SystemSnapshot(timestamp: t, memory: Memory(total: 8 << 30, app: 0, wired: 0, compressed: 0, cache: 0, free: 0),
                                              pressure: .normal, swap: Swap(total: 0, used: 0), disk: Disk(total: 0, free: 0),
                                              load: LoadAverage(m1: 0, m5: 0, m15: 0), coreCount: 8) }
        rec.addSystem(s(t0), counters: nil)
        rec.addSystem(s(t0.addingTimeInterval(5)), counters: nil)
        rec.addSystem(s(t0.addingTimeInterval(47)), counters: nil)   // the app stalled for 42 s
        rec.addSystem(s(t0.addingTimeInterval(61)), counters: nil)
        XCTAssertEqual(rec.rows.first?.sampleGapS, 42)
    }
}
