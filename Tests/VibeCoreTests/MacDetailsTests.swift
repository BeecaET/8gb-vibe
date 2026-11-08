import XCTest
import IOKit.ps
@testable import VibeCore

final class MacDetailsTests: XCTestCase {
    func testYearFromName() {
        XCTAssertEqual(MacDetails.year(fromModelName: "MacBook Air (M2, 2022)"), 2022)
        XCTAssertEqual(MacDetails.year(fromModelName: "MacBook Pro (16-inch, 2019)"), 2019)
        XCTAssertNil(MacDetails.year(fromModelName: "Mac14,2"))
    }

    func testBatteryParse() {
        let reg: [String: Any] = ["CycleCount": 155, "DesignCycleCount9C": 1000, "ExternalConnected": true, "IsCharging": false,
                                  "BatteryData": ["DesignCapacity": 4563, "NominalChargeCapacity": 4864]]
        let ps: [String: Any] = [kIOPSCurrentCapacityKey: 80, kIOPSMaxCapacityKey: 100, kIOPSBatteryHealthKey: "Good"]
        let b = BatteryInfo.parse(registry: reg, powerSource: ps)!
        XCTAssertEqual(b.cycleCount, 155)
        XCTAssertEqual(b.designCapacity, 4563)
        XCTAssertEqual(b.capacityPercent, 107, "a new battery can be above its design")
        XCTAssertEqual(b.chargePercent, 80)
        XCTAssertEqual(b.onAC, true)
        XCTAssertEqual(b.isCharging, false)
        XCTAssertEqual(b.health, "Good")
        // AppleRawMaxCapacity wins when present.
        XCTAssertEqual(BatteryInfo.parse(registry: ["DesignCapacity": 5000, "AppleRawMaxCapacity": 4000], powerSource: nil)?.capacityPercent, 80)
    }

    func testBatteryMissingFieldsStayNil() {
        XCTAssertNil(BatteryInfo.parse(registry: [:], powerSource: nil), "no battery")
        let b = BatteryInfo.parse(registry: ["CycleCount": 3], powerSource: nil)!
        XCTAssertNil(b.capacityPercent)
        XCTAssertNil(b.health)
        XCTAssertNil(b.chargePercent)
        XCTAssertNil(b.onAC)
    }

    func testToolsReadVersionFromInfoPlist() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("8gb-tools-\(UUID().uuidString)").path
        addTeardownBlock { try? FileManager.default.removeItem(atPath: root) }
        let xcode = root + "/Applications/Xcode.app/Contents"
        try FileManager.default.createDirectory(atPath: xcode, withIntermediateDirectories: true)
        NSDictionary(dictionary: ["CFBundleShortVersionString": "26.1"]).write(toFile: xcode + "/Info.plist", atomically: true)
        try FileManager.default.createDirectory(atPath: root + "/Applications/OrbStack.app", withIntermediateDirectories: true)
        let tools = MacDetails.tools(root: root)
        XCTAssertEqual(tools.map(\.name), ["Xcode", "OrbStack"])
        XCTAssertEqual(tools[0].version, "26.1")
        XCTAssertNil(tools[1].version, "no Info.plist: not guessed")
    }

    func testOldSavedScanStillLoadsAndIsRescanned() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("hw-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        let old = """
        {"schema":1,"scannedAt":"2026-11-01T10:00:00Z","model":"Mac14,2","modelName":"MacBook Air (M2, 2022)","chip":"Apple M2",
         "appleSilicon":true,"performanceCores":4,"efficiencyCores":4,"totalCores":8,"ramBytes":8589934592,"diskBytes":494000000000,
         "diskInternal":true,"diskFormat":"APFS","macOSVersion":"27.0","tools":[]}
        """
        try Data(old.utf8).write(to: file)
        let store = HardwareStore(file: file)
        let loaded = try XCTUnwrap(store.load())
        XCTAssertNil(loaded.gpuCores)
        XCTAssertNil(loaded.toolDetails)
        XCTAssertTrue(HardwareScanner.needsRescan(loaded, quick: .init(model: "Mac14,2", ramBytes: 8589934592, macOSVersion: "27.0")))
        var fresh = loaded
        fresh.schema = HardwareInfo.currentSchema
        fresh.gpuCores = 10
        fresh.toolDetails = [ToolInfo(name: "Xcode", version: "26.1", path: "/Applications/Xcode.app")]
        store.save(fresh)
        XCTAssertEqual(store.load()?.gpuCores, 10)
        XCTAssertEqual(store.load()?.toolDetails?.first?.version, "26.1")
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertFalse(try String(contentsOf: file, encoding: .utf8).lowercased().contains("serial"))
    }

    /// Reads this Mac (read-only) and prints what was found; checks only what every Mac has.
    func testLiveReadOnThisMac() {
        let h = HardwareScanner.scan()
        let live = MacLive.read()
        print("details:", h.modelYear as Any, h.architecture as Any, h.gpuCores as Any, h.macOSFull as Any, h.macOSBuild as Any,
              h.diskModel as Any, h.diskMedium as Any, h.smartCapable as Any, h.toolDetails?.map { "\($0.name) \($0.version ?? "?")" } as Any)
        print("live:", live.battery as Any, live.displays, live.uptime as Any, live.thermal, live.lowPowerMode, live.diskFree as Any)
        XCTAssertNotNil(h.architecture)
        XCTAssertNotNil(h.macOSBuild)
        XCTAssertNotNil(live.uptime)
    }
}
