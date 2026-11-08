import XCTest
@testable import VibeCore

final class HardwareProfileTests: XCTestCase {
    let gb: UInt64 = 1 << 30

    func testTiers() {
        XCTAssertEqual(OptimizationProfile.tier(ramBytes: 8 * gb), .gb8)
        XCTAssertEqual(OptimizationProfile.tier(ramBytes: 12 * gb), .gb8)
        XCTAssertEqual(OptimizationProfile.tier(ramBytes: 16 * gb), .gb16)
        XCTAssertEqual(OptimizationProfile.tier(ramBytes: 18 * gb), .gb16)
        XCTAssertEqual(OptimizationProfile.tier(ramBytes: 24 * gb), .gb24Plus)
        XCTAssertEqual(OptimizationProfile.tier(ramBytes: 64 * gb), .gb24Plus)
    }

    func testProfilesScaleWithRAM() {
        let p8 = OptimizationProfile.make(tier: .gb8, intel: false, cores: 8)
        let p16 = OptimizationProfile.make(tier: .gb16, intel: false, cores: 8)
        let p24 = OptimizationProfile.make(tier: .gb24Plus, intel: false, cores: 8)
        XCTAssertLessThan(p8.thresholds.swapYellowGB, p16.thresholds.swapYellowGB)
        XCTAssertLessThan(p16.thresholds.swapRedGB, p24.thresholds.swapRedGB)
        XCTAssertLessThan(p8.thresholds.sessionsYellow, p16.thresholds.sessionsYellow)
        XCTAssertLessThan(p8.headroomReserve, p24.headroomReserve)
        XCTAssertLessThan(p8.freezeSevereMBPerMin, p24.freezeSevereMBPerMin)
        XCTAssertEqual(p8.name, "8 GB")
        // CPU load thresholds follow the core count.
        XCTAssertEqual(OptimizationProfile.make(tier: .gb8, intel: false, cores: 10).thresholds.load5Yellow, 20)
    }

    func testIntelHasSameSwapThresholds() {
        let arm = OptimizationProfile.make(tier: .gb8, intel: false, cores: 4)
        let intel = OptimizationProfile.make(tier: .gb8, intel: true, cores: 4)
        XCTAssertEqual(intel.freezeSevereMBPerMin, arm.freezeSevereMBPerMin)  // no Intel factor (stage 1)
        XCTAssertEqual(intel.name, "8 GB Intel")
    }

    /// Values the user never touched move to the new defaults; values the user changed stay.
    func testUserChangesAreKept() {
        let oldDefaults = Thresholds()
        var mine = Thresholds()
        mine.swapRedGB = 9            // changed by the user
        mine.idleMinutes = 45         // changed by the user
        let newDefaults = OptimizationProfile.make(tier: .gb16, intel: false, cores: 8).thresholds
        let r = mine.adopting(newDefaults: newDefaults, previousDefaults: oldDefaults)
        XCTAssertEqual(r.swapRedGB, 9)
        XCTAssertEqual(r.idleMinutes, 45)
        XCTAssertEqual(r.swapYellowGB, newDefaults.swapYellowGB)
        XCTAssertEqual(r.sessionsYellow, newDefaults.sessionsYellow)
    }

    func testRescanRules() {
        let info = HardwareScanner.scan()
        let q = HardwareScanner.Quick(model: info.model, ramBytes: info.ramBytes, macOSVersion: info.macOSVersion)
        XCTAssertTrue(HardwareScanner.needsRescan(nil, quick: q))
        XCTAssertFalse(HardwareScanner.needsRescan(info, quick: q))
        var older = info; older.schema = 0
        XCTAssertTrue(HardwareScanner.needsRescan(older, quick: q))
        XCTAssertTrue(HardwareScanner.needsRescan(info, quick: HardwareScanner.Quick(model: info.model, ramBytes: info.ramBytes * 2, macOSVersion: info.macOSVersion)))
        XCTAssertTrue(HardwareScanner.needsRescan(info, quick: HardwareScanner.Quick(model: info.model, ramBytes: info.ramBytes, macOSVersion: "99.0")))
    }

    func testStoreScansOnceThenReuses() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("8gb-hw-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let store = HardwareStore(file: dir.appendingPathComponent("hardware.json"))
        var scans = 0
        let fake = { () -> HardwareInfo in
            scans += 1
            return HardwareInfo(schema: HardwareInfo.currentSchema, scannedAt: Date(timeIntervalSince1970: 1_800_000_000), model: "Mac14,2",
                                modelName: "MacBook Air (M2, 2022)", chip: "Apple M2", appleSilicon: true, performanceCores: 4,
                                efficiencyCores: 4, totalCores: 8, ramBytes: 8 << 30, diskBytes: 494 << 30, diskInternal: true,
                                diskFormat: "APFS", macOSVersion: "27.0", tools: ["Xcode"])
        }
        let q = HardwareScanner.Quick(model: "Mac14,2", ramBytes: 8 << 30, macOSVersion: "27.0")
        let first = store.loadOrScan(quick: q, scan: fake)
        XCTAssertTrue(first.rescanned)
        let second = store.loadOrScan(quick: q, scan: fake)
        XCTAssertFalse(second.rescanned)
        XCTAssertEqual(scans, 1)
        XCTAssertEqual(second.info.summary, "MacBook Air (M2, 2022), 8 GB")
        XCTAssertEqual(OptimizationProfile.forHardware(second.info).tier, .gb8)
        // macOS update: scanned again.
        _ = store.loadOrScan(quick: HardwareScanner.Quick(model: "Mac14,2", ramBytes: 8 << 30, macOSVersion: "27.1"), scan: fake)
        XCTAssertEqual(scans, 2)
        let perms = try FileManager.default.attributesOfItem(atPath: store.file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.intValue, 0o600)
    }

    func testRealScanLooksSane() {
        let h = HardwareScanner.scan()
        XCTAssertFalse(h.model.isEmpty)
        XCTAssertGreaterThan(h.ramBytes, 1 << 30)
        XCTAssertGreaterThan(h.totalCores, 0)
        XCTAssertFalse(h.macOSVersion.isEmpty)
    }

    func testToolsOnlyChecksExistence() {
        let tools = HardwareScanner.installedTools { $0 == "/Applications/Xcode-beta.app" || $0 == "/Applications/OrbStack.app" }
        XCTAssertEqual(tools, ["Xcode", "OrbStack"])
    }

    func testHeadroomUsesProfileReserve() {
        let memory = Memory.fromPageCounts(internalPages: 0, purgeable: 0, wired: 1 << 30, compressor: 0, external: 0, free: 0,
                                           pageSize: 1, total: 16 << 30)
        let result = ProcessSnapshot(timestamp: Date(), processes: [],
                                     groups: [GroupUsage(group: .other, footprint: 8 << 30, cpu: 0, processCount: 1, items: [])],
                                     sessions: [], readableTotal: 0, unreadableCount: 0)
        let budget = RAMBudget(memory: memory, snapshot: result)
        let small = SessionHeadroom(budget: budget, sessions: [], reserve: 512 << 20)
        let large = SessionHeadroom(budget: budget, sessions: [], reserve: 2 << 30)
        XCTAssertGreaterThan(small.availableRAM, large.availableRAM)
    }
}
