import Darwin
import Foundation

/// RAM computed the way Activity Monitor does.
public struct Memory: Equatable, Sendable {
    public var total: UInt64
    /// App memory (anonymous, minus purgeable).
    public var app: UInt64
    public var wired: UInt64
    /// Real RAM holding compressed data.
    public var compressed: UInt64
    /// File cache, can be freed right away.
    public var cache: UInt64
    public var free: UInt64

    public init(total: UInt64, app: UInt64, wired: UInt64, compressed: UInt64, cache: UInt64, free: UInt64) {
        self.total = total; self.app = app; self.wired = wired
        self.compressed = compressed; self.cache = cache; self.free = free
    }

    public var used: UInt64 { app + wired + compressed }
    public var usedRatio: Double { total == 0 ? 0 : min(1, Double(used) / Double(total)) }

    /// Computed from `host_statistics64` page counts.
    public static func fromPageCounts(
        internalPages: UInt64, purgeable: UInt64, wired: UInt64, compressor: UInt64,
        external: UInt64, free: UInt64, pageSize: UInt64, total: UInt64
    ) -> Memory {
        let appPages = internalPages > purgeable ? internalPages - purgeable : 0
        return Memory(
            total: total,
            app: appPages * pageSize,
            wired: wired * pageSize,
            compressed: compressor * pageSize,
            cache: (external + purgeable) * pageSize,
            free: free * pageSize
        )
    }
}

public enum MemoryPressure: Int, Comparable, Sendable {
    case normal = 1
    case warning = 2
    case critical = 4

    public static func < (a: MemoryPressure, b: MemoryPressure) -> Bool { a.rawValue < b.rawValue }

    public var name: String {
        switch self {
        case .normal: return String(localized: "Normal", bundle: .main)
        case .warning: return String(localized: "Warning", bundle: .main)
        case .critical: return String(localized: "Critical", bundle: .main)
        }
    }
}

public struct Swap: Equatable, Sendable {
    public var total: UInt64
    public var used: UInt64
    public init(total: UInt64, used: UInt64) { self.total = total; self.used = used }
}

public struct Disk: Equatable, Sendable {
    public var total: UInt64
    /// Free space macOS can use (including purgeable space).
    public var free: UInt64
    public init(total: UInt64, free: UInt64) { self.total = total; self.free = free }
    public var fullRatio: Double { total == 0 ? 0 : 1 - Double(free) / Double(total) }
}

public struct LoadAverage: Equatable, Sendable {
    public var m1: Double, m5: Double, m15: Double
    public init(m1: Double, m5: Double, m15: Double) { self.m1 = m1; self.m5 = m5; self.m15 = m15 }
}

public struct SystemSnapshot: Sendable {
    public var timestamp: Date
    public var memory: Memory
    public var pressure: MemoryPressure
    public var swap: Swap
    public var disk: Disk
    public var load: LoadAverage
    public var coreCount: Int
}

/// Reads system metrics. No root needed.
public enum SystemReader {
    public static func memory() -> Memory? {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kernResult = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kernResult == KERN_SUCCESS else { return nil }
        return Memory.fromPageCounts(
            internalPages: UInt64(vm.internal_page_count),
            purgeable: UInt64(vm.purgeable_count),
            wired: UInt64(vm.wire_count),
            compressor: UInt64(vm.compressor_page_count),
            external: UInt64(vm.external_page_count),
            free: UInt64(vm.free_count),
            pageSize: UInt64(vm_kernel_page_size),
            total: totalRAM()
        )
    }

    public static func totalRAM() -> UInt64 {
        var v: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &v, &size, nil, 0)
        return v
    }

    public static func coreCount() -> Int {
        var v: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("hw.ncpu", &v, &size, nil, 0)
        return Int(max(1, v))
    }

    public static func pressure() -> MemoryPressure {
        var v: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &v, &size, nil, 0) == 0 else {
            return .normal
        }
        return MemoryPressure(rawValue: Int(v)) ?? .normal
    }

    public static func swap() -> Swap {
        var sw = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &sw, &size, nil, 0) == 0 else { return Swap(total: 0, used: 0) }
        return Swap(total: sw.xsu_total, used: sw.xsu_used)
    }

    public static func disk(path: String = "/") -> Disk {
        let url = URL(fileURLWithPath: path)
        if let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
           let total = v.volumeTotalCapacity, let free = v.volumeAvailableCapacityForImportantUsage {
            return Disk(total: UInt64(total), free: UInt64(max(0, free)))
        }
        var s = statfs()
        guard statfs(path, &s) == 0 else { return Disk(total: 0, free: 0) }
        let blockSize = UInt64(s.f_bsize)
        return Disk(total: UInt64(s.f_blocks) * blockSize, free: UInt64(s.f_bavail) * blockSize)
    }

    public static func load() -> LoadAverage {
        var l = [Double](repeating: 0, count: 3)
        guard getloadavg(&l, 3) == 3 else { return LoadAverage(m1: 0, m5: 0, m15: 0) }
        return LoadAverage(m1: l[0], m5: l[1], m15: l[2])
    }

    /// `disk`: pass a value read earlier to avoid reading again. Reading disk capacity is fairly slow (macOS asks the cache cleaning service),
    /// so the app reads it only every 60 seconds on a background thread.
    public static func snapshot(disk readCount: Disk? = nil) -> SystemSnapshot? {
        guard let memoryInfo = memory() else { return nil }
        return SystemSnapshot(
            timestamp: Date(), memory: memoryInfo, pressure: pressure(), swap: swap(),
            disk: readCount ?? disk(), load: load(), coreCount: coreCount()
        )
    }
}
