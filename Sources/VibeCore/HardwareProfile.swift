import Darwin
import Foundation
import IOKit

// MARK: Hardware scan

/// What this Mac is, scanned once (sysctl, IOKit, file checks; no network) and saved for later launches.
public struct HardwareInfo: Codable, Sendable, Hashable {
    /// Bumped when fields are added or their meaning changes: forces a rescan.
    public static let currentSchema = 2

    public var schema: Int
    public var scannedAt: Date
    /// Model identifier, for example "Mac14,2".
    public var model: String
    /// Marketing name when available, for example "MacBook Air (M2, 2022)".
    public var modelName: String
    /// "Apple M2", "Intel(R) Core(TM) i5-...".
    public var chip: String
    public var appleSilicon: Bool
    public var performanceCores: Int
    public var efficiencyCores: Int
    public var totalCores: Int
    public var ramBytes: UInt64
    public var diskBytes: UInt64
    public var diskInternal: Bool
    /// "APFS" and so on.
    public var diskFormat: String
    /// "27.0" (major.minor).
    public var macOSVersion: String
    /// Developer tools found in /Applications (not opened): Xcode, Docker, Android Studio, OrbStack.
    public var tools: [String]

    // Schema 2: details for the Mac page. Optional: nil means "could not be read" (never guessed).
    /// Year from the marketing name ("MacBook Air (M2, 2022)" -> 2022).
    public var modelYear: Int?
    /// "arm64" or "x86_64".
    public var architecture: String?
    /// GPU cores (IOKit AGXAccelerator "gpu-core-count", Apple silicon).
    public var gpuCores: Int?
    /// RAM type: not published without other tools on Apple silicon; kept for Macs that do.
    public var memoryType: String?
    /// "27.0.1" and the build "26A428".
    public var macOSFull: String?
    public var macOSBuild: String?
    /// Internal disk model ("APPLE SSD AP0512Z") and medium ("Solid State"). The serial number is never read into this.
    public var diskModel: String?
    public var diskMedium: String?
    /// Whether the NVMe drive reports SMART support. The SMART status itself needs another tool: not read.
    public var smartCapable: Bool?
    /// Developer tools with their version from Info.plist.
    public var toolDetails: [ToolInfo]?

    /// RAM in whole GB, for display and tiers.
    public var ramGB: Int { Int((Double(ramBytes) / Double(1 << 30)).rounded()) }

    /// "MacBook Air (M2, 2022), 8 GB".
    public var summary: String { "\(modelName), \(ramGB) GB" }
}

public enum HardwareScanner {
    /// Full scan. Fast (a few milliseconds): sysctl, one IOKit property, file existence checks.
    public static func scan(now: Date = Date()) -> HardwareInfo {
        let model = sysctlString("hw.model") ?? "Mac"
        let arm = sysctlInt("hw.optional.arm64") == 1
        let p = sysctlInt("hw.perflevel0.physicalcpu") ?? 0
        let e = sysctlInt("hw.perflevel1.physicalcpu") ?? 0
        let total = sysctlInt("hw.physicalcpu") ?? (p + e)
        let root = URL(fileURLWithPath: "/")
        let v = try? root.resourceValues(forKeys: [.volumeIsInternalKey, .volumeTotalCapacityKey, .volumeLocalizedFormatDescriptionKey])
        let disk = MacDetails.internalDisk()
        return HardwareInfo(
            schema: HardwareInfo.currentSchema, scannedAt: now, model: model,
            modelName: productName() ?? model,
            chip: sysctlString("machdep.cpu.brand_string") ?? (arm ? "Apple silicon" : "Intel"),
            appleSilicon: arm, performanceCores: arm ? p : total, efficiencyCores: arm ? e : 0, totalCores: total,
            ramBytes: SystemReader.totalRAM(),
            diskBytes: UInt64(v?.volumeTotalCapacity ?? 0), diskInternal: v?.volumeIsInternal ?? true,
            diskFormat: v?.volumeLocalizedFormatDescription ?? "",
            macOSVersion: osVersion(), tools: installedTools(),
            modelYear: MacDetails.year(fromModelName: productName() ?? ""),
            architecture: MacDetails.architecture(), gpuCores: MacDetails.gpuCores(), memoryType: nil,
            macOSFull: MacDetails.macOSFull(), macOSBuild: sysctlString("kern.osversion"),
            diskModel: disk.model, diskMedium: disk.medium, smartCapable: disk.smart,
            toolDetails: MacDetails.tools())
    }

    /// The cheap part checked at every launch: if any of these changed, the saved scan is out of date.
    public struct Quick: Sendable, Hashable {
        public var model: String
        public var ramBytes: UInt64
        public var macOSVersion: String
    }

    public static func quick() -> Quick {
        Quick(model: sysctlString("hw.model") ?? "Mac", ramBytes: SystemReader.totalRAM(), macOSVersion: osVersion())
    }

    /// A saved scan needs redoing when missing, from an older schema, or the model, RAM or macOS changed.
    public static func needsRescan(_ saved: HardwareInfo?, quick: Quick) -> Bool {
        guard let s = saved else { return true }
        return s.schema != HardwareInfo.currentSchema || s.model != quick.model || s.ramBytes != quick.ramBytes
            || s.macOSVersion != quick.macOSVersion
    }

    static func osVersion() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion)"
    }

    static let toolPaths: [(String, [String])] = [
        ("Xcode", ["/Applications/Xcode.app", "/Applications/Xcode-beta.app"]),
        ("Docker", ["/Applications/Docker.app"]),
        ("OrbStack", ["/Applications/OrbStack.app"]),
        ("Android Studio", ["/Applications/Android Studio.app"])
    ]

    static func installedTools(fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)) -> [String] {
        toolPaths.filter { $0.1.contains(where: fileExists) }.map(\.0)
    }

    /// Marketing name from the device tree (Apple silicon). nil on Macs that do not publish it.
    static func productName() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard let data = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Data else { return nil }
        let name = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
        return name.isEmpty ? nil : name
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }

    static func sysctlInt(_ name: String) -> Int? {
        var v: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &v, &size, nil, 0) == 0 else { return nil }
        return Int(v)
    }
}

/// Saves the scan as hardware.json (0600) in Application Support.
public struct HardwareStore: Sendable {
    public let file: URL

    public init(file: URL) { self.file = file }

    public static var defaultFile: URL {
        MeasurementStore.defaultDirectory.deletingLastPathComponent().appendingPathComponent("hardware.json")
    }

    public func load() -> HardwareInfo? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(HardwareInfo.self, from: data)
    }

    public func save(_ info: HardwareInfo) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(info) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    /// Loads the saved scan, rescanning when needed. `rescanned` tells whether a new scan was made (first launch or changes).
    public func loadOrScan(quick: HardwareScanner.Quick = HardwareScanner.quick(),
                           scan: () -> HardwareInfo = { HardwareScanner.scan() }) -> (info: HardwareInfo, rescanned: Bool) {
        let saved = load()
        if !HardwareScanner.needsRescan(saved, quick: quick), let s = saved { return (s, false) }
        let fresh = scan()
        save(fresh)
        return (fresh, true)
    }
}

// MARK: Optimization profiles

/// Default settings that depend on the Mac. Values are starting points (estimates), not measurements,
/// except where noted in docs/CHUC_NANG.md. Anything the user changed in Settings is kept.
public struct OptimizationProfile: Sendable, Equatable {
    public enum Tier: String, Sendable, CaseIterable {
        case gb8, gb16, gb24Plus
    }

    public var tier: Tier
    public var intel: Bool
    /// Alert thresholds used as defaults.
    public var thresholds: Thresholds
    /// RAM kept for the system and file cache when estimating room for more agent sessions.
    public var headroomReserve: UInt64
    /// "Your Mac may freeze soon": swap MB per minute that warns alone, and the lower level that warns when doubling.
    public var freezeSevereMBPerMin: Double
    public var freezeRisingMBPerMin: Double
    /// Process scan interval in the background, seconds.
    public var backgroundScanSeconds: TimeInterval

    public static func tier(ramBytes: UInt64) -> Tier {
        let gb = Double(ramBytes) / Double(1 << 30)
        if gb <= 12 { return .gb8 }
        if gb <= 20 { return .gb16 }
        return .gb24Plus
    }

    /// "8 GB", "16 GB", "24 GB+" (and " Intel").
    public var name: String {
        let base: String
        switch tier {
        case .gb8: base = "8 GB"
        case .gb16: base = "16 GB"
        case .gb24Plus: base = "24 GB+"
        }
        return intel ? base + " Intel" : base
    }

    public static func forHardware(_ h: HardwareInfo) -> OptimizationProfile {
        make(tier: tier(ramBytes: h.ramBytes), intel: !h.appleSilicon, cores: max(1, h.totalCores))
    }

    public static func make(tier: Tier, intel: Bool, cores: Int) -> OptimizationProfile {
        var t = Thresholds()
        let reserve: UInt64
        let severe: Double, rising: Double
        let scan: TimeInterval
        switch tier {
        case .gb8:
            t.swapYellowGB = 3; t.swapRedGB = 6
            t.sessionsYellow = 4; t.sessionsRed = 8
            reserve = 512 << 20; severe = 3000; rising = 1000; scan = 60
        case .gb16:
            t.swapYellowGB = 4; t.swapRedGB = 8
            t.sessionsYellow = 8; t.sessionsRed = 12
            reserve = 1 << 30; severe = 4000; rising = 1500; scan = 45
        case .gb24Plus:
            t.swapYellowGB = 6; t.swapRedGB = 12
            t.sessionsYellow = 12; t.sessionsRed = 20
            reserve = 2 << 30; severe = 6000; rising = 2000; scan = 30
        }
        // CPU load thresholds follow the core count (2 and 4 runnable threads per core).
        t.load5Yellow = Double(cores * 2); t.load5Red = Double(cores * 4)
        // No Intel factor: there is no measured evidence that Intel Macs freeze at lower swap rates.
        return OptimizationProfile(tier: tier, intel: intel, thresholds: t, headroomReserve: reserve,
                                   freezeSevereMBPerMin: severe, freezeRisingMBPerMin: rising, backgroundScanSeconds: scan)
    }
}

public extension Thresholds {
    /// Moves to new defaults while keeping what the user changed: a field equal to the previous default
    /// (never touched) takes the new default; any other value is the user's own and stays.
    func adopting(newDefaults new: Thresholds, previousDefaults old: Thresholds) -> Thresholds {
        var r = self
        func pick<T: Equatable>(_ kp: WritableKeyPath<Thresholds, T>) { if self[keyPath: kp] == old[keyPath: kp] { r[keyPath: kp] = new[keyPath: kp] } }
        pick(\.swapYellowGB); pick(\.swapRedGB); pick(\.diskFreeYellowGB); pick(\.diskFreeRedGB)
        pick(\.load5Yellow); pick(\.load5Red); pick(\.sessionsYellow); pick(\.sessionsRed); pick(\.idleMinutes)
        return r
    }
}
