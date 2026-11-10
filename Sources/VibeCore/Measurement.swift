import Darwin
import Foundation

// MARK: VM counters and rates

/// Cumulative VM counters from `host_statistics64`. A rate needs two samples.
public struct VMCounters: Sendable, Hashable {
    public var swapIns: UInt64
    public var swapOuts: UInt64
    public var compressions: UInt64
    public var decompressions: UInt64
    public var pageouts: UInt64
    public var pageSize: UInt64

    public init(swapIns: UInt64, swapOuts: UInt64, compressions: UInt64, decompressions: UInt64, pageouts: UInt64, pageSize: UInt64) {
        self.swapIns = swapIns; self.swapOuts = swapOuts; self.compressions = compressions
        self.decompressions = decompressions; self.pageouts = pageouts; self.pageSize = pageSize
    }

    /// Reads the counters. nil if the kernel call fails.
    public static func read() -> VMCounters? {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return nil }
        return VMCounters(swapIns: UInt64(vm.swapins), swapOuts: UInt64(vm.swapouts),
                          compressions: UInt64(vm.compressions), decompressions: UInt64(vm.decompressions),
                          pageouts: UInt64(vm.pageouts), pageSize: UInt64(vm_kernel_page_size))
    }
}

/// Per-second rates between two counter samples.
public struct VMRates: Sendable, Hashable {
    public var swapInBytes: Double
    public var swapOutBytes: Double
    public var compressions: Double
    public var decompressions: Double
    public var pageoutBytes: Double

    /// Swap in plus swap out, bytes per second.
    public var swapIOBytes: Double { swapInBytes + swapOutBytes }

    /// nil when the interval is not positive or a counter went backwards (reboot, wrap).
    public static func between(_ a: VMCounters, _ b: VMCounters, seconds: TimeInterval) -> VMRates? {
        guard seconds > 0, b.swapIns >= a.swapIns, b.swapOuts >= a.swapOuts, b.compressions >= a.compressions,
              b.decompressions >= a.decompressions, b.pageouts >= a.pageouts else { return nil }
        let p = Double(b.pageSize)
        return VMRates(swapInBytes: Double(b.swapIns - a.swapIns) * p / seconds,
                       swapOutBytes: Double(b.swapOuts - a.swapOuts) * p / seconds,
                       compressions: Double(b.compressions - a.compressions) / seconds,
                       decompressions: Double(b.decompressions - a.decompressions) / seconds,
                       pageoutBytes: Double(b.pageouts - a.pageouts) * p / seconds)
    }
}

// MARK: Heavy jobs

/// A heavy job running now: a build, a test run, a bundler.
public struct HeavyJob: Sendable, Hashable {
    public var kind: String
    public var pid: Int32
}

/// Recognizes heavy jobs (builds, tests) in the process list. Several processes of one job count once.
public enum HeavyJobDetector {
    /// Compilers count only while busy, and they are grouped by parent (one Xcode build runs many of them).
    static let compilers: Set<String> = ["swift-frontend", "swiftc", "clang", "clang++", "ld", "ld64", "rustc"]
    static let busyCPU = 20.0

    /// Heavy job kind of one process, or nil.
    public static func kind(_ t: ProcessRecord, cpu: Double) -> String? {
        let file = DevProcessClassifier.fileName(t)
        let args = DevProcessClassifier.arguments(t).map { DevProcessClassifier.commandName($0) }
        let has = { (w: String) in args.contains(w) }
        switch file {
        case "xcodebuild": return "Xcode build"
        case "swift-build": return "SwiftPM build"
        case "swift-test": return "SwiftPM test"
        case "cargo": return has("build") || has("test") || has("check") ? "Cargo" : nil
        case "go": return has("build") || has("test") ? "Go build" : nil
        case "pytest": return "pytest"
        case "docker" where has("build"): return "Docker build"
        case "buildkitd": return cpu >= busyCPU ? "Docker build" : nil
        default: break
        }
        if compilers.contains(file) { return cpu >= busyCPU ? "Compilers" : nil }
        if file == "java" || t.name == "java" {
            let a = t.arguments.joined(separator: " ")
            if a.contains("GradleDaemon") || a.contains("org.gradle") { return cpu >= 50 ? "Gradle build" : nil }
            return nil
        }
        guard DevProcessClassifier.isRuntime(t) else { return nil }
        // Node and Python tools: the subcommand decides.
        if has("next") && has("build") { return "next build" }
        if has("vite") && has("build") { return "vite build" }
        if has("webpack") && !has("serve") { return "webpack" }
        if has("tsc") && !t.arguments.contains("--watch") && !t.arguments.contains("-w") { return "tsc" }
        if has("jest") { return "jest" }
        if has("vitest") && (has("run") || t.arguments.contains("--run")) { return "vitest" }
        if has("playwright") && has("test") { return "Playwright test" }
        if has("pytest") || (t.arguments.contains("-m") && has("pytest")) { return "pytest" }
        if let launcher = args.first(where: { ["npm", "pnpm", "yarn", "bun"].contains($0) }), has("build") || has("test") {
            return "\(launcher) \(has("test") ? "test" : "build")"
        }
        return nil
    }

    /// Jobs running now. A job is the topmost heavy process of a tree; busy compilers without a heavy parent
    /// are grouped by their parent process (Xcode's build service runs many of them for one build).
    public static func jobs(_ list: [ProcessRecord], cpu: [Int32: Double]) -> [HeavyJob] {
        let byPID = Dictionary(list.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        var kinds: [Int32: String] = [:]
        for t in list { if let k = kind(t, cpu: cpu[t.pid] ?? 0) { kinds[t.pid] = k } }
        var seen: Set<String> = []
        var result: [HeavyJob] = []
        for (pid, k) in kinds.sorted(by: { $0.key < $1.key }) {
            // Skip if an ancestor is a heavy job (it is part of that job).
            var p = byPID[pid]?.ppid ?? 0
            var inside = false
            var steps = 0
            while p > 1, steps < 40, let parent = byPID[p] {
                if kinds[p] != nil { inside = true; break }
                p = parent.ppid; steps += 1
            }
            if inside { continue }
            let key = compilers.contains(byPID[pid].map(DevProcessClassifier.fileName) ?? "")
                ? "cc:\(byPID[pid]?.ppid ?? 0)" : "job:\(pid)"
            if seen.insert(key).inserted { result.append(HeavyJob(kind: k, pid: pid)) }
        }
        return result
    }
}

// MARK: One row per minute

/// One minute of measurements. Written to CSV; nothing leaves the Mac.
public struct MinuteRow: Sendable, Hashable {
    public var minute: Date
    /// Highest memory pressure seen in the minute: 0 normal, 1 warning, 2 critical.
    public var pressure: Int
    public var swapInMB: Double
    public var swapOutMB: Double
    public var compressionsPerSec: Double
    public var decompressionsPerSec: Double
    public var pageoutMB: Double
    public var swapUsedGB: Double
    public var ramUsedPercent: Double
    public var wiredGB: Double
    /// Most heavy jobs seen at once in the minute.
    public var heavyJobs: Int
    /// Kinds of those jobs, joined with "+".
    public var heavyKinds: String
    public var strained: Bool
    /// For the first minute of a strained episode: the group or session whose RAM grew most just before. Correlation only.
    public var suspect: String
    /// Longest wait of the main thread (UI) to answer a ping, milliseconds. 0 when not measured.
    public var mainLagMs: Double = 0
    /// Longest delay of the once-a-second probe timer (the whole process stalled), milliseconds.
    public var timerLagMs: Double = 0
    /// Longest gap between two system samples, seconds (expected 5, or 15 when overloaded).
    public var sampleGapS: Double = 0

    public static let header = "minute,pressure,swap_in_mb,swap_out_mb,compressions_per_s,decompressions_per_s,pageout_mb,swap_used_gb,ram_used_pct,wired_gb,heavy_jobs,heavy_kinds,strained,suspect,main_lag_ms,timer_lag_ms,sample_gap_s"

    public var csv: String {
        func f(_ x: Double, _ d: Int = 1) -> String { String(format: "%.\(d)f", x) }
        func q(_ s: String) -> String { s.isEmpty ? "" : "\"" + s.replacingOccurrences(of: "\"", with: "'") + "\"" }
        return [MinuteRow.iso.string(from: minute), "\(pressure)", f(swapInMB), f(swapOutMB), f(compressionsPerSec, 0),
                f(decompressionsPerSec, 0), f(pageoutMB), f(swapUsedGB, 2), f(ramUsedPercent, 0), f(wiredGB, 2),
                "\(heavyJobs)", q(heavyKinds), strained ? "1" : "0", q(suspect),
                f(mainLagMs, 0), f(timerLagMs, 0), f(sampleGapS)].joined(separator: ",")
    }

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Parses a line written by `csv`. nil for the header or a broken line.
    public init?(csv line: String) {
        var fields: [String] = []
        var cur = ""
        var quoted = false
        for ch in line {
            if ch == "\"" { quoted.toggle(); continue }
            if ch == ",", !quoted { fields.append(cur); cur = ""; continue }
            cur.append(ch)
        }
        fields.append(cur)
        // 14 fields: files from before the responsiveness columns were added.
        guard fields.count == 14 || fields.count == 17, let m = MinuteRow.iso.date(from: fields[0]), let p = Int(fields[1]) else { return nil }
        let d = { (i: Int) in Double(fields[i]) ?? 0 }
        self.init(minute: m, pressure: p, swapInMB: d(2), swapOutMB: d(3), compressionsPerSec: d(4), decompressionsPerSec: d(5),
                  pageoutMB: d(6), swapUsedGB: d(7), ramUsedPercent: d(8), wiredGB: d(9), heavyJobs: Int(fields[10]) ?? 0,
                  heavyKinds: fields[11], strained: fields[12] == "1", suspect: fields[13])
        if fields.count == 17 { mainLagMs = d(14); timerLagMs = d(15); sampleGapS = d(16) }
    }

    public init(minute: Date, pressure: Int, swapInMB: Double, swapOutMB: Double, compressionsPerSec: Double,
                decompressionsPerSec: Double, pageoutMB: Double, swapUsedGB: Double, ramUsedPercent: Double, wiredGB: Double,
                heavyJobs: Int, heavyKinds: String, strained: Bool, suspect: String) {
        self.minute = minute; self.pressure = pressure; self.swapInMB = swapInMB; self.swapOutMB = swapOutMB
        self.compressionsPerSec = compressionsPerSec; self.decompressionsPerSec = decompressionsPerSec; self.pageoutMB = pageoutMB
        self.swapUsedGB = swapUsedGB; self.ramUsedPercent = ramUsedPercent; self.wiredGB = wiredGB
        self.heavyJobs = heavyJobs; self.heavyKinds = heavyKinds; self.strained = strained; self.suspect = suspect
    }
}

// MARK: Recorder

/// Turns 5-second system samples and process samples into one row per minute.
/// Provisional definition of "strained": memory pressure warning or worse, or at least `strainSwapMB` of swap
/// in plus out within the minute. Thresholds must be tuned with real data.
/// Not thread safe: call from the main thread only.
public final class MeasurementRecorder: @unchecked Sendable {
    public static let strainSwapMB = 20.0
    /// RAM growth needed before a strained episode to name a suspect.
    public static let suspectMinGrowth: UInt64 = 100 << 20

    private let store: MeasurementStore?
    /// Optional: when set, each row carries the main-thread and timer lag of the minute.
    public var probe: ResponsivenessProbe?
    private var lastSystemSample: Date?
    private var sampleGap = 0.0
    private var lastCounters: (Date, VMCounters)?
    public private(set) var lastRates: VMRates?
    /// Rows of the last 24 hours, oldest first.
    public private(set) var rows: [MinuteRow] = []

    private var minute: Date?
    private var pressure = 0
    private var swapIn = 0.0, swapOut = 0.0, pageout = 0.0
    private var compressions = 0.0, decompressions = 0.0, seconds = 0.0
    private var swapUsed = 0.0, ramUsed = 0.0, wired = 0.0
    private var heavy = 0
    private var kinds: Set<String> = []
    /// Recent RAM per group and per agent session, for naming a suspect.
    private var footprints: [(Date, [String: UInt64])] = []

    public init(store: MeasurementStore?, now: Date = Date()) {
        self.store = store
        if let store { rows = store.rows(since: now.addingTimeInterval(-86_400)) }
    }

    /// Every system sample (about every 5 seconds).
    public func addSystem(_ h: SystemSnapshot, counters: VMCounters?) {
        let now = h.timestamp
        roll(to: now)
        if let last = lastSystemSample { sampleGap = max(sampleGap, now.timeIntervalSince(last)) }
        lastSystemSample = now
        if let c = counters {
            if let (t, prev) = lastCounters, let r = VMRates.between(prev, c, seconds: now.timeIntervalSince(t)) {
                lastRates = r
                let dt = now.timeIntervalSince(t)
                swapIn += r.swapInBytes * dt / 1_048_576
                swapOut += r.swapOutBytes * dt / 1_048_576
                pageout += r.pageoutBytes * dt / 1_048_576
                compressions += r.compressions * dt
                decompressions += r.decompressions * dt
                seconds += dt
            }
            lastCounters = (now, c)
        }
        pressure = max(pressure, h.pressure == .critical ? 2 : (h.pressure == .warning ? 1 : 0))
        swapUsed = Double(h.swap.used) / Format.GB
        ramUsed = h.memory.usedRatio * 100
        wired = Double(h.memory.wired) / Format.GB
    }

    /// Every process sample (5 seconds with a window open, 60 seconds in the background).
    public func addProcesses(_ r: ProcessSnapshot) {
        roll(to: r.timestamp)
        heavy = max(heavy, r.heavyJobs.count)
        kinds.formUnion(r.heavyJobs.map(\.kind))
        var f: [String: UInt64] = [:]
        for g in r.groups { f[g.group.name] = g.footprint }
        for s in r.sessions { f["Claude Code (\(s.projectName))"] = s.footprint }
        for s in r.agentSessions { f["\(s.tool) (\(s.projectName ?? "?"))"] = s.footprint }
        footprints.append((r.timestamp, f))
        footprints.removeAll { r.timestamp.timeIntervalSince($0.0) > 10 * 60 }
    }

    /// Closes the current minute when time moves into the next one.
    private func roll(to now: Date) {
        let m = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 60).rounded(.down) * 60)
        guard let current = minute else { minute = m; return }
        guard m > current else { return }
        finish(current)
        minute = m
    }

    private func finish(_ m: Date) {
        let strained = pressure >= 1 || swapIn + swapOut >= Self.strainSwapMB
        let wasStrained = rows.last.map { $0.strained && m.timeIntervalSince($0.minute) <= 120 } ?? false
        var row = MinuteRow(minute: m, pressure: pressure, swapInMB: swapIn, swapOutMB: swapOut,
                            compressionsPerSec: seconds > 0 ? compressions / seconds : 0,
                            decompressionsPerSec: seconds > 0 ? decompressions / seconds : 0,
                            pageoutMB: pageout, swapUsedGB: swapUsed, ramUsedPercent: ramUsed, wiredGB: wired,
                            heavyJobs: heavy, heavyKinds: kinds.sorted().joined(separator: "+"), strained: strained,
                            suspect: strained && !wasStrained ? suspect(at: m.addingTimeInterval(60)) : "")
        if let lags = probe?.takeMinute() { row.mainLagMs = lags.mainLag * 1000; row.timerLagMs = lags.timerLag * 1000 }
        row.sampleGapS = sampleGap
        rows.append(row)
        rows.removeAll { m.timeIntervalSince($0.minute) > 86_400 }
        store?.append(row)
        pressure = 0; swapIn = 0; swapOut = 0; pageout = 0; compressions = 0; decompressions = 0; seconds = 0
        heavy = 0; kinds = []; sampleGap = 0
    }

    /// The group or session whose RAM grew most over the last 2 to 10 minutes. Correlation, not proof.
    public func currentSuspect(now: Date = Date()) -> String { suspect(at: now) }

    func suspect(at end: Date) -> String {
        guard let latest = footprints.last(where: { $0.0 <= end }) else { return "" }
        guard let earlier = footprints.first(where: { latest.0.timeIntervalSince($0.0) >= 120 }) else { return "" }
        var best: (String, UInt64)?
        for (name, now) in latest.1 {
            let before = earlier.1[name] ?? 0
            guard now > before else { continue }
            let grow = now - before
            if grow >= Self.suspectMinGrowth, grow > (best?.1 ?? 0) { best = (name, grow) }
        }
        return best.map { "\($0.0) +\($0.1 >> 20) MB" } ?? ""
    }
}

// MARK: Storage

/// One CSV file per day in Application Support. Files are private to the user (0600), kept at most 14 days and 5 MB in total.
public final class MeasurementStore: @unchecked Sendable {
    public let directory: URL
    public static let maxDays = 14
    public static let maxBytes: UInt64 = 5 << 20

    public init(directory: URL) {
        self.directory = directory
    }

    /// Only one running copy of the app writes measurements (test copies started with `open -n` share the folder).
    /// The first copy to take the lock writes; others keep trying each minute.
    private var lockFD: Int32 = -1

    public func acquireLock() -> Bool {
        if lockFD >= 0 { return true }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(directory.appendingPathComponent(".lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return false }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 { lockFD = fd; return true }
        close(fd)
        return false
    }

    deinit { if lockFD >= 0 { close(lockFD) } }

    /// Default folder: ~/Library/Application Support/8GB Vibe/measurements
    /// (`VIBE_MEASUREMENTS_DIR` overrides it, so test copies do not mix with real data).
    public static var defaultDirectory: URL {
        if let d = ProcessInfo.processInfo.environment["VIBE_MEASUREMENTS_DIR"], !d.isEmpty { return URL(fileURLWithPath: d, isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("8GB Vibe", isDirectory: true).appendingPathComponent("measurements", isDirectory: true)
    }

    static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    func file(for date: Date) -> URL { directory.appendingPathComponent(Self.dayFormat.string(from: date) + ".csv") }

    public func append(_ row: MinuteRow) {
        guard acquireLock() else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = file(for: row.minute)
        let isNew = !fm.fileExists(atPath: url.path)
        let line = (isNew ? MinuteRow.header + "\n" : "") + row.csv + "\n"
        if isNew {
            fm.createFile(atPath: url.path, contents: Data(line.utf8), attributes: [.posixPermissions: 0o600])
            prune()
        } else {
            // Before opening the handle: the upgrade replaces the file, and a handle opened earlier
            // would keep writing to the old, unlinked copy.
            Self.upgradeHeader(at: url)
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(Data(line.utf8))
                try? h.close()
            }
        }
    }

    /// A file started by an older version keeps its old header while new rows carry more columns.
    /// Rewrites only the first line to the current header so external tools (Excel, pandas) name every column.
    /// Old rows keep their fewer fields; the parser accepts both widths.
    static func upgradeHeader(at url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let firstBreak = text.firstIndex(of: "\n") else { return }
        let first = text[..<firstBreak]
        guard first.hasPrefix("minute,"), first != MinuteRow.header else { return }
        let fixed = MinuteRow.header + text[firstBreak...]
        let tmp = url.appendingPathExtension("tmp")
        guard FileManager.default.createFile(atPath: tmp.path, contents: Data(fixed.utf8), attributes: [.posixPermissions: 0o600]) else { return }
        _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }

    /// CSV files, oldest first.
    public func files() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return items.filter { $0.pathExtension == "csv" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Keeps at most `maxDays` files and `maxBytes` in total, deleting the oldest first.
    public func prune() {
        var list = files()
        func size(_ u: URL) -> UInt64 { UInt64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        while list.count > Self.maxDays || (list.count > 1 && list.reduce(0) { $0 + size($1) } > Self.maxBytes) {
            try? FileManager.default.removeItem(at: list.removeFirst())
        }
    }

    public func rows(since: Date) -> [MinuteRow] {
        // Only files from the day before `since` onward (file names are dates), so startup stays cheap.
        let firstDay = Self.dayFormat.string(from: since.addingTimeInterval(-86_400))
        return files().filter { $0.deletingPathExtension().lastPathComponent >= firstDay }.flatMap { u -> [MinuteRow] in
            guard let s = try? String(contentsOf: u, encoding: .utf8) else { return [] }
            return s.split(separator: "\n").compactMap { MinuteRow(csv: String($0)) }
        }.filter { $0.minute >= since }.sorted { $0.minute < $1.minute }
    }
}

// MARK: Summary

/// One work session: minutes with measurements, split where the gap exceeds 30 minutes (app closed or Mac asleep).
public struct WorkSessionSummary: Sendable, Hashable {
    public var start: Date
    public var end: Date
    public var minutes: Int
    public var strainedMinutes: Int
    /// Strained minutes with at least one heavy job running: likely caused by heavy work.
    public var strainedWithHeavy: Int
    /// Strained minutes with no heavy job: likely the resident load (agents, apps, VMs).
    public var strainedResident: Int
    /// How many times two or more heavy jobs started overlapping.
    public var overlapEpisodes: Int
    public var maxHeavyJobs: Int
    public var swapIOMB: Double
    /// Most frequent suspects at the start of strained episodes.
    public var suspects: [String]
}

public enum MeasurementSummary {
    public static func sessions(_ rows: [MinuteRow], gap: TimeInterval = 30 * 60) -> [WorkSessionSummary] {
        var result: [WorkSessionSummary] = []
        var group: [MinuteRow] = []
        func flush() {
            guard let first = group.first, let last = group.last else { return }
            var overlaps = 0
            var prev = 0
            for r in group { if r.heavyJobs >= 2 && prev < 2 { overlaps += 1 }; prev = r.heavyJobs }
            let names = group.compactMap { r -> String? in
                guard !r.suspect.isEmpty else { return nil }
                return r.suspect.components(separatedBy: " +").first
            }
            let counted = Dictionary(grouping: names, by: { $0 }).mapValues(\.count).sorted { $0.value > $1.value }
            result.append(WorkSessionSummary(start: first.minute, end: last.minute.addingTimeInterval(60), minutes: group.count,
                                             strainedMinutes: group.filter(\.strained).count,
                                             strainedWithHeavy: group.filter { $0.strained && $0.heavyJobs > 0 }.count,
                                             strainedResident: group.filter { $0.strained && $0.heavyJobs == 0 }.count,
                                             overlapEpisodes: overlaps, maxHeavyJobs: group.map(\.heavyJobs).max() ?? 0,
                                             swapIOMB: group.reduce(0) { $0 + $1.swapInMB + $1.swapOutMB },
                                             suspects: counted.prefix(3).map { "\($0.key) (\($0.value))" }))
            group = []
        }
        for r in rows.sorted(by: { $0.minute < $1.minute }) {
            if let last = group.last, r.minute.timeIntervalSince(last.minute) > gap { flush() }
            group.append(r)
        }
        flush()
        return result
    }

    /// Plain text report for the command line (English), one block per work session. Dates are DD/MM/YYYY, 24-hour.
    public static func report(_ rows: [MinuteRow], folder: URL) -> String {
        let s = sessions(rows)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "dd/MM/yyyy HH:mm"
        var out = ["8GB Vibe: measurement summary (\(rows.count) minutes, \(s.count) sessions). Data: \(folder.path)", ""]
        for x in s {
            out.append("Session \(f.string(from: x.start)) to \(f.string(from: x.end)): \(x.minutes) minutes measured")
            out.append("  Strained: \(x.strainedMinutes) min (with heavy jobs: \(x.strainedWithHeavy), resident: \(x.strainedResident))")
            out.append("  Overlapping heavy jobs: \(x.overlapEpisodes) times, at most \(x.maxHeavyJobs) at once")
            out.append("  Swap in and out: \(Int(x.swapIOMB)) MB")
            if !x.suspects.isEmpty { out.append("  Possibly related: \(x.suspects.joined(separator: ", "))") }
            out.append("")
        }
        out.append("\"Strained\" (working definition): memory pressure at warning level or above, or swap in and out of \(Int(MeasurementRecorder.strainSwapMB)) MB or more in one minute.")
        out.append("\"Possibly related\" is correlation only, not proof of cause.")
        return out.joined(separator: "\n")
    }
}
