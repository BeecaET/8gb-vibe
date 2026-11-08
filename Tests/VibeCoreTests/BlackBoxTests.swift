import XCTest
@testable import VibeCore

final class BlackBoxTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func temp() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("8gb-bb-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: u) }
        return u
    }

    func sample(_ s: Double, pressure: Int = 0, swap: Double = 0, suspect: String = "") -> BlackBoxSample {
        BlackBoxSample(time: t0.addingTimeInterval(s), pressure: pressure, swapMBPerMin: swap, swapUsedGB: 9, suspect: suspect)
    }

    func testNothingWrittenWhenCalm() {
        let dir = temp()
        let bb = BlackBox(directory: dir)
        for i in 0..<100 { bb.add(sample(Double(i * 5))) }
        XCTAssertTrue(bb.readAll().isEmpty)
        XCTAssertLessThanOrEqual(bb.ring.count, BlackBox.capacity)
    }

    func testGapWhileStrainedIsAnIncidentAndOnDisk() {
        let dir = temp()
        let bb = BlackBox(directory: dir)
        for i in 0..<12 { bb.add(sample(Double(i * 5), pressure: 1, swap: 2000 + Double(i) * 500, suspect: i == 8 ? "Claude Code (shop) +900 MB" : "")) }
        // The app could not run for 3 minutes.
        let incident = bb.add(sample(55 + 180, pressure: 1, swap: 4000))
        XCTAssertEqual(incident?.kind, .gap)
        XCTAssertEqual(incident?.duration, 180)
        XCTAssertEqual(incident?.start, t0.addingTimeInterval(55))
        XCTAssertEqual(incident?.suspect, "Claude Code (shop) +900 MB")
        XCTAssertEqual(incident?.peakSwapMBPerMin, 7500)
        XCTAssertEqual(bb.readAll().count, 13)
        // Survives a restart of the app.
        XCTAssertEqual(BlackBox(directory: dir).incidents.count, 1)
        let file = bb.files().first!
        let perms = try? FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.intValue, 0o600)
    }

    func testGapWhileCalmIsNotAnIncident() {
        let bb = BlackBox(directory: nil)
        bb.add(sample(0))
        XCTAssertNil(bb.add(sample(3600)), "sleep with a calm Mac is not a freeze")
    }

    func testPreviousRunEndedWhileStrained() {
        let dir = temp()
        let a = BlackBox(directory: dir)
        for i in 0..<6 { a.add(sample(Double(i * 5), pressure: 2, swap: 9000, suspect: "Docker +1200 MB")) }
        let b = BlackBox(directory: dir)
        XCTAssertNil(b.checkPreviousRun(previousRunWasClean: true, now: t0.addingTimeInterval(600)))
        let i = b.checkPreviousRun(previousRunWasClean: false, now: t0.addingTimeInterval(600))
        XCTAssertEqual(i?.kind, .endedWhileStrained)
        XCTAssertNil(i?.duration)
        XCTAssertEqual(i?.suspect, "Docker +1200 MB")
    }

    func testUIStall() {
        let bb = BlackBox(directory: nil)
        XCTAssertNil(bb.uiLag(2, at: t0))
        XCTAssertEqual(bb.uiLag(14, at: t0)?.kind, .uiStall)
    }
}

// Stage 1, item 1.7: sleep is not an incident; titles follow the evidence.
final class SleepAndRebootTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func strained(_ s: Double, uptime: Double? = nil, swap: Double = 4000) -> BlackBoxSample {
        BlackBoxSample(time: t0.addingTimeInterval(s), pressure: 1, swapMBPerMin: swap, swapUsedGB: 9, suspect: "", uptime: uptime)
    }

    func testGapWithSleepByUptimeIsNotAnIncident() {
        let bb = BlackBox(directory: nil)
        bb.add(strained(0, uptime: 1000))
        // Wall clock moved 30 min, uptime (stops while asleep) moved 5 s.
        XCTAssertNil(bb.add(strained(1800, uptime: 1005)))
        XCTAssertEqual(bb.incidents.last?.kind, .sleep)
    }

    func testGapWithReportedSleepIsNotAnIncident() {
        let bb = BlackBox(directory: nil)
        bb.add(strained(0))
        bb.noteSleep(at: t0.addingTimeInterval(3))
        bb.noteWake(at: t0.addingTimeInterval(600))
        XCTAssertNil(bb.add(strained(605)))
    }

    func testGapWithoutSleepIsStillAnIncident() {
        let bb = BlackBox(directory: nil)
        bb.add(strained(0, uptime: 1000))
        let i = bb.add(strained(90, uptime: 1090))
        XCTAssertEqual(i?.kind, .gap)
        XCTAssertEqual(i?.likelyFrozen, false, "4 GB/min is not strong evidence")
    }

    func testLikelyFrozenNeedsLongGapAndVeryHeavySwap() {
        let bb = BlackBox(directory: nil)
        bb.add(strained(0, uptime: 1000, swap: 12_000))
        XCTAssertEqual(bb.add(strained(120, uptime: 1120, swap: 12_000))?.likelyFrozen, true)
        let short = BlackBox(directory: nil)
        short.add(strained(0, uptime: 1000, swap: 12_000))
        XCTAssertEqual(short.add(strained(40, uptime: 1040, swap: 12_000))?.likelyFrozen, false)
    }

    func testRebootIsReported() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("8gb-bb-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let a = BlackBox(directory: dir)
        for i in 0..<6 { a.add(strained(Double(i * 5), swap: 9000)) }
        let b = BlackBox(directory: dir)
        XCTAssertEqual(b.checkPreviousRun(previousRunWasClean: false, now: t0.addingTimeInterval(900),
                                          bootTime: t0.addingTimeInterval(300))?.rebooted, true)
        let c = BlackBox(directory: dir)
        XCTAssertEqual(c.checkPreviousRun(previousRunWasClean: false, now: t0.addingTimeInterval(900),
                                          bootTime: t0.addingTimeInterval(-86_400))?.rebooted, false)
        XCTAssertNotNil(BlackBox.bootTime())
    }
}

final class FreezeForecastTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func ring(_ rate: (Int) -> Double, pressure: Int = 1) -> [BlackBoxSample] {
        (0...36).map { BlackBoxSample(time: t0.addingTimeInterval(Double($0 * 5)), pressure: pressure, swapMBPerMin: rate($0), swapUsedGB: 9, suspect: "") }
    }

    func testSevereSwapWarnsOnceThenCoolsDown() {
        var f = FreezeForecast()
        let r = ring { _ in 5000 }
        let now = r.last!.time
        XCTAssertNotNil(f.check(r, now: now))
        XCTAssertNil(f.check(r, now: now.addingTimeInterval(60)), "no piling up")
        XCTAssertNotNil(f.check(r.map { var s = $0; s.time += 16 * 60; return s }, now: now.addingTimeInterval(16 * 60)))
    }

    func testRisingSwapWarnsOnlyUnderPressure() {
        let r = { (p: Int) in self.ring({ $0 < 20 ? 400 : 1500 }, pressure: p) }
        var f = FreezeForecast()
        XCTAssertNotNil(f.check(r(1), now: r(1).last!.time))
        var g = FreezeForecast()
        XCTAssertNil(g.check(r(0), now: r(0).last!.time))
    }

    func testSteadyModerateSwapDoesNotWarn() {
        // About what this Mac does most of the day (500 to 850 MB per minute): no warning.
        var f = FreezeForecast()
        let r = ring { _ in 800 }
        XCTAssertNil(f.check(r, now: r.last!.time))
    }
}

// Stage 1, item 1.6: the measured drop is before minus after, and can be negative.
final class MeasuredDropTests: XCTestCase {
    func testDrop() {
        let d = MeasuredDrop(before: MemoryReading(used: 6 << 30, swap: 3 << 30), after: MemoryReading(used: 5 << 30, swap: (3 << 30) + (100 << 20)))
        XCTAssertEqual(d.ram, 1 << 30)
        XCTAssertEqual(d.swap, -(100 << 20))
        XCTAssertNotNil(MemoryReading.now())
        let json = String(decoding: try! JSONEncoder().encode(d), as: UTF8.self)
        XCTAssertTrue(json.contains("\"ram\""))
    }
}
