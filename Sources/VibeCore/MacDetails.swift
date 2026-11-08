import CoreGraphics
import Darwin
import Foundation
import IOKit
import IOKit.ps

/// A developer tool found on disk, with its version from Info.plist (the app is not opened).
public struct ToolInfo: Codable, Sendable, Hashable {
    public var name: String
    public var version: String?
    public var path: String
    public init(name: String, version: String?, path: String) { self.name = name; self.version = version; self.path = path }
}

/// Battery, read live (IOPowerSources and the AppleSmartBattery registry entry). Every field may be missing.
public struct BatteryInfo: Sendable, Equatable {
    /// "Good", "Fair", "Poor", "Check Battery"... as macOS reports it.
    public var health: String?
    public var cycleCount: Int?
    public var designCycles: Int?
    /// mAh.
    public var designCapacity: Int?
    public var fullChargeCapacity: Int?
    /// Percent of charge now.
    public var chargePercent: Int?
    public var isCharging: Bool?
    /// On the power adapter.
    public var onAC: Bool?

    /// Full-charge capacity as a percent of the design capacity (can be above 100 on a new battery).
    public var capacityPercent: Int? {
        guard let d = designCapacity, d > 0, let f = fullChargeCapacity else { return nil }
        return Int((Double(f) / Double(d) * 100).rounded())
    }

    /// Builds from the registry properties and the power-source description. Unknown keys are ignored.
    public static func parse(registry r: [String: Any], powerSource ps: [String: Any]?) -> BatteryInfo? {
        if r.isEmpty && ps == nil { return nil }
        let data = r["BatteryData"] as? [String: Any] ?? [:]
        func int(_ v: Any?) -> Int? { (v as? NSNumber)?.intValue }
        var b = BatteryInfo()
        b.cycleCount = int(r["CycleCount"])
        b.designCycles = int(r["DesignCycleCount9C"])
        b.designCapacity = int(r["DesignCapacity"]) ?? int(data["DesignCapacity"])
        b.fullChargeCapacity = int(r["AppleRawMaxCapacity"]) ?? int(data["NominalChargeCapacity"]) ?? int(r["NominalChargeCapacity"])
        b.isCharging = (r["IsCharging"] as? Bool) ?? (ps?[kIOPSIsChargingKey] as? Bool)
        b.onAC = (r["ExternalConnected"] as? Bool) ?? (ps?[kIOPSPowerSourceStateKey] as? String).map { $0 == kIOPSACPowerValue }
        if let cur = int(ps?[kIOPSCurrentCapacityKey]), let max = int(ps?[kIOPSMaxCapacityKey]), max > 0 {
            b.chargePercent = Int((Double(cur) / Double(max) * 100).rounded())
        }
        b.health = ps?[kIOPSBatteryHealthKey] as? String
        return b
    }

    /// nil on Macs without a battery.
    public static func read() -> BatteryInfo? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        var registry: [String: Any] = [:]
        if service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let d = props?.takeRetainedValue() as? [String: Any] {
                // Keep only what the page shows (the entry also holds a serial number, which is never kept).
                for k in ["CycleCount", "DesignCycleCount9C", "DesignCapacity", "AppleRawMaxCapacity", "NominalChargeCapacity",
                          "IsCharging", "ExternalConnected", "BatteryData"] { registry[k] = d[k] }
                if var data = registry["BatteryData"] as? [String: Any] {
                    data = data.filter { ["DesignCapacity", "NominalChargeCapacity"].contains($0.key) }
                    registry["BatteryData"] = data
                }
            }
            IOObjectRelease(service)
        }
        var source: [String: Any]?
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for ps in list {
                if let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                   d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType { source = d }
            }
        }
        if service == 0 && source == nil { return nil }
        return parse(registry: registry.compactMapValues { $0 }, powerSource: source)
    }
}

/// One display, read live (CoreGraphics).
public struct DisplayInfo: Sendable, Equatable {
    public var builtIn: Bool
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// Points ("looks like").
    public var width: Int
    public var height: Int
    /// Hz; nil when the display does not report it.
    public var refreshHz: Double?

    public static func readAll() -> [DisplayInfo] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).compactMap { id in
            guard let mode = CGDisplayCopyDisplayMode(id) else { return nil }
            return DisplayInfo(builtIn: CGDisplayIsBuiltin(id) != 0, pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight,
                               width: mode.width, height: mode.height, refreshHz: mode.refreshRate > 0 ? mode.refreshRate : nil)
        }
    }
}

/// Values that change while the app runs: read when the Mac page is open, never saved.
public struct MacLive: Sendable, Equatable {
    public var battery: BatteryInfo?
    public var displays: [DisplayInfo]
    public var uptime: TimeInterval?
    /// "nominal", "fair", "serious", "critical".
    public var thermal: String
    public var lowPowerMode: Bool
    public var diskFree: UInt64?

    public static func read(now: Date = Date()) -> MacLive {
        let free = (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage.map { UInt64(max(0, $0)) }
        return MacLive(battery: BatteryInfo.read(), displays: DisplayInfo.readAll(),
                       uptime: BlackBox.bootTime().map { now.timeIntervalSince($0) },
                       thermal: MacDetails.thermalName(ProcessInfo.processInfo.thermalState),
                       lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled, diskFree: free)
    }
}

public enum MacDetails {
    /// The last 4-digit year in a marketing name, or nil.
    public static func year(fromModelName name: String) -> Int? {
        let years = name.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.filter { (2000...2100).contains($0) }
        return years.last
    }

    public static func architecture() -> String? {
        var u = utsname()
        guard uname(&u) == 0 else { return nil }
        let s = withUnsafeBytes(of: &u.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return s.isEmpty ? nil : s
    }

    public static func gpuCores() -> Int? {
        let s = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AGXAccelerator"))
        guard s != 0 else { return nil }
        defer { IOObjectRelease(s) }
        return (IORegistryEntryCreateCFProperty(s, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.intValue
    }

    public static func macOSFull() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// Model and medium of the first internal NVMe/SSD, and whether it reports SMART support. No serial number.
    public static func internalDisk() -> (model: String?, medium: String?, smart: Bool?) {
        var model: String?, medium: String?, smart: Bool?
        var it: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDevice"), &it) == KERN_SUCCESS {
            while case let e = IOIteratorNext(it), e != 0 {
                defer { IOObjectRelease(e) }
                guard model == nil,
                      let ch = IORegistryEntryCreateCFProperty(e, "Device Characteristics" as CFString, kCFAllocatorDefault, 0)?
                        .takeRetainedValue() as? [String: Any],
                      let protocolCh = IORegistryEntryCreateCFProperty(e, "Protocol Characteristics" as CFString, kCFAllocatorDefault, 0)?
                        .takeRetainedValue() as? [String: Any],
                      (protocolCh["Physical Interconnect Location"] as? String) == "Internal" else { continue }
                model = (ch["Product Name"] as? String).map { $0.trimmingCharacters(in: .whitespaces) }
                medium = ch["Medium Type"] as? String
                smart = IORegistryEntryCreateCFProperty(e, "NVMe SMART Capable" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? Bool
            }
            IOObjectRelease(it)
        }
        return (model, medium, smart)
    }

    static let toolApps: [(String, [String])] = [
        ("Xcode", ["/Applications/Xcode.app", "/Applications/Xcode-beta.app"]),
        ("Simulator", ["/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app",
                       "/Applications/Xcode-beta.app/Contents/Developer/Applications/Simulator.app"]),
        ("Docker", ["/Applications/Docker.app"]),
        ("OrbStack", ["/Applications/OrbStack.app"]),
        ("Android Studio", ["/Applications/Android Studio.app"]),
    ]

    /// Tools present, with the version in their Info.plist. `root` replaces "/" in tests.
    public static func tools(root: String = "") -> [ToolInfo] {
        var list: [ToolInfo] = []
        for (name, paths) in toolApps {
            guard let p = paths.first(where: { FileManager.default.fileExists(atPath: root + $0) }) else { continue }
            let plist = NSDictionary(contentsOfFile: root + p + "/Contents/Info.plist")
            list.append(ToolInfo(name: name, version: plist?["CFBundleShortVersionString"] as? String, path: p))
        }
        if FileManager.default.fileExists(atPath: root + "/Library/Developer/CommandLineTools") {
            list.append(ToolInfo(name: "Command Line Tools", version: nil, path: "/Library/Developer/CommandLineTools"))
        }
        return list
    }

    public static func thermalName(_ s: ProcessInfo.ThermalState) -> String {
        switch s {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
