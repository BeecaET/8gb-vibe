import Darwin
import Foundation

/// One process at one point in time.
public struct ProcessRecord: Sendable, Hashable {
    public var pid: Int32
    public var ppid: Int32
    public var uid: UInt32
    public var name: String
    public var path: String
    public var startDate: Date
    /// Real RAM needed (`ri_phys_footprint`, including compressed and swapped parts). nil if unreadable (system processes).
    public var footprint: UInt64?
    /// Total CPU time (nanoseconds). nil if unreadable.
    public var cpuNanos: UInt64?
    /// Command line arguments. Only read for java, node, python...
    public var arguments: [String]

    public init(pid: Int32, ppid: Int32, uid: UInt32, name: String, path: String, startDate: Date,
                footprint: UInt64?, cpuNanos: UInt64?, arguments: [String] = []) {
        self.pid = pid; self.ppid = ppid; self.uid = uid; self.name = name; self.path = path
        self.startDate = startDate; self.footprint = footprint; self.cpuNanos = cpuNanos; self.arguments = arguments
    }

    /// Unique key: a pid can be reused, so the start time is added.
    public var key: String { "\(pid)@\(Int(startDate.timeIntervalSince1970))" }

    /// Display name: the first .app bundle in the path, or the executable name.
    public var appName: String {
        for part in path.split(separator: "/") where part.hasSuffix(".app") {
            return String(part.dropLast(4))
        }
        let last = (path as NSString).lastPathComponent
        return last.isEmpty ? name : last
    }
}

public enum ProcessReader {
    /// Executable names whose arguments are read for classification.
    static let needsArguments: Set<String> = ["java", "node", "python", "python3", "bun", "deno", "Python"]

    private static let timebase: (numer: UInt64, denom: UInt64) = {
        var average = mach_timebase_info_data_t()
        mach_timebase_info(&average)
        return (UInt64(average.numer), UInt64(max(1, average.denom)))
    }()

    public static func allPIDs() -> [Int32] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(n) + 64)
        let got = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard got > 0 else { return [] }
        return Array(pids.prefix(Int(got))).filter { $0 > 0 }
    }

    /// Reads one process. `cache` keeps paths and arguments already read so they are not read again.
    public static func read(pid: Int32, cache: inout [String: (String, [String])]) -> ProcessRecord? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }

        let startDate = Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec)
                          + TimeInterval(info.pbi_start_tvusec) / 1_000_000)
        let name = fixedCString(&info.pbi_name).isEmpty ? fixedCString(&info.pbi_comm) : fixedCString(&info.pbi_name)
        let key = "\(pid)@\(Int(startDate.timeIntervalSince1970))"

        var path: String
        var arguments: [String]
        if let cached = cache[key] {
            (path, arguments) = cached
        } else {
            path = readPath(pid)
            let last = (path as NSString).lastPathComponent
            arguments = needsArguments.contains(last) || needsArguments.contains(name) ? readArguments(pid) : []
            cache[key] = (path, arguments)
        }

        var footprint: UInt64?
        var cpuNanos: UInt64?
        var ri = rusage_info_v4()
        let r = withUnsafeMutablePointer(to: &ri) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        if r == 0 {
            footprint = ri.ri_phys_footprint
            let ticks = ri.ri_user_time &+ ri.ri_system_time
            cpuNanos = ticks / timebase.denom * timebase.numer
        }

        return ProcessRecord(pid: pid, ppid: Int32(info.pbi_ppid), uid: info.pbi_uid, name: name,
                         path: path, startDate: startDate, footprint: footprint, cpuNanos: cpuNanos,
                         arguments: arguments)
    }

    public static func readAll(cache: inout [String: (String, [String])]) -> [ProcessRecord] {
        let list = allPIDs().compactMap { read(pid: $0, cache: &cache) }
        // Drop cache entries of processes that have exited.
        let alive = Set(list.map(\.key))
        cache = cache.filter { alive.contains($0.key) }
        return list
    }

    /// Current working directory of a process (only readable for the same user).
    public static func workingDirectory(pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = fixedCString(&info.pvi_cdir.vip_path)
        return path.isEmpty ? nil : path
    }

    static func readPath(_ pid: Int32) -> String {
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        return n > 0 ? String(cString: buf) : ""
    }

    /// Reads arguments through `KERN_PROCARGS2`.
    static func readArguments(_ pid: Int32) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return [] }
        return parseProcArgs(Array(buf.prefix(size)))
    }

    /// Layout: argc (Int32), executable path, zero padding bytes, then argc zero-terminated strings.
    static func parseProcArgs(_ buf: [UInt8]) -> [String] {
        guard buf.count > 4 else { return [] }
        let argc = Int(buf.withUnsafeBytes { $0.load(as: Int32.self) })
        var i = 4
        while i < buf.count, buf[i] != 0 { i += 1 }
        while i < buf.count, buf[i] == 0 { i += 1 }
        var args: [String] = []
        while i < buf.count, args.count < argc {
            let start = i
            while i < buf.count, buf[i] != 0 { i += 1 }
            args.append(String(decoding: buf[start..<i], as: UTF8.self))
            i += 1
        }
        return args
    }

    /// C string inside a fixed-size tuple. It may lack a trailing zero byte, so the length must be capped.
    private static func fixedCString<T>(_ tuple: inout T) -> String {
        withUnsafeBytes(of: &tuple) { raw in
            let bytes = raw.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
    }
}
