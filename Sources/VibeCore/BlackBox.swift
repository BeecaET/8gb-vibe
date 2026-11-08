import Foundation

/// One fine-grained sample for the black box (every system sample, about 5 seconds).
public struct BlackBoxSample: Sendable, Hashable {
    public var time: Date
    /// 0 normal, 1 warning, 2 critical.
    public var pressure: Int
    /// Swap in plus out, MB per minute, from the last two samples.
    public var swapMBPerMin: Double
    public var swapUsedGB: Double
    /// The group or session whose RAM grew most recently ("may be related"). Empty if none.
    public var suspect: String
    /// Monotonic clock that stops while the Mac sleeps (`ProcessInfo.systemUptime`). nil in old files.
    public var uptime: TimeInterval?

    public init(time: Date, pressure: Int, swapMBPerMin: Double, swapUsedGB: Double, suspect: String, uptime: TimeInterval? = nil) {
        self.time = time; self.pressure = pressure; self.swapMBPerMin = swapMBPerMin; self.swapUsedGB = swapUsedGB; self.suspect = suspect
        self.uptime = uptime
    }

    var line: String {
        let s = suspect.replacingOccurrences(of: "\t", with: " ")
        return [MinuteRow.iso.string(from: time), "\(pressure)", String(format: "%.0f", swapMBPerMin), String(format: "%.2f", swapUsedGB), s]
            .joined(separator: "\t")
    }

    init?(line: String) {
        let f = line.components(separatedBy: "\t")
        guard f.count == 5, let t = MinuteRow.iso.date(from: f[0]), let p = Int(f[1]), let r = Double(f[2]), let u = Double(f[3]) else { return nil }
        self.init(time: t, pressure: p, swapMBPerMin: r, swapUsedGB: u, suspect: f[4])
    }

    /// Strained enough to keep on disk: pressure warning or worse, or heavy swapping.
    public var strained: Bool { pressure >= 1 || swapMBPerMin >= BlackBox.strainSwapMBPerMin }
}

/// A moment when the Mac (or this app) stopped responding.
public struct Incident: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Codable {
        /// No sample for much longer than expected: the app could not run (the Mac froze or slept).
        case gap
        /// The app's main thread did not answer for a long time.
        case uiStall
        /// The previous run ended while the Mac was strained, without quitting normally (force restart, crash, kill).
        case endedWhileStrained
        /// The gap was the Mac sleeping (not an incident; kept for the record, never notified).
        case sleep
    }
    public var kind: Kind
    public var start: Date
    /// nil when unknown (the app was not running to see the end).
    public var duration: TimeInterval?
    public var peakSwapMBPerMin: Double
    public var suspect: String
    /// For `endedWhileStrained`: the Mac booted after the last sample (it was restarted).
    public var rebooted: Bool? = nil

    /// Strong evidence the whole Mac froze: a long gap with very heavy swapping (10 GB per minute or more).
    public var likelyFrozen: Bool { kind == .gap && (duration ?? 0) >= 60 && peakSwapMBPerMin >= 10_240 }
}

/// Keeps the last minutes of samples in RAM and writes them to disk only while the Mac is strained,
/// so that after a freeze the app can tell when it happened and what grew before it.
/// Files: one tab-separated file per day, 0600, at most 7 days and 2 MB in total. Not thread safe: main thread only.
public final class BlackBox: @unchecked Sendable {
    public static let capacity = 240                      // 20 minutes at 5 seconds
    public static let strainSwapMBPerMin = 300.0
    public static let flushInterval: TimeInterval = 30
    public static let stallGap: TimeInterval = 30         // expected gap is 5 (15 when overloaded)
    public static let uiStallSeconds: TimeInterval = 10
    public static let maxDays = 7
    public static let maxBytes: UInt64 = 2 << 20

    public let directory: URL?
    public private(set) var ring: [BlackBoxSample] = []
    private var flushed: Date = .distantPast
    private var lastFlush: Date = .distantPast
    /// Incidents found while running, newest last.
    public private(set) var incidents: [Incident] = []

    public init(directory: URL?) {
        self.directory = directory
        incidents = loadIncidents()
    }

    public static var defaultDirectory: URL {
        MeasurementStore.defaultDirectory.deletingLastPathComponent().appendingPathComponent("blackbox", isDirectory: true)
    }

    /// Adds a sample. Returns an incident when the time since the previous sample shows the app could not run.
    /// Sleep periods reported by the system (willSleep / didWake). A gap that contains one is the Mac sleeping.
    private var sleeps: [(start: Date, end: Date?)] = []

    public func noteSleep(at t: Date) { sleeps.append((t, nil)); if sleeps.count > 20 { sleeps.removeFirst() } }
    public func noteWake(at t: Date) {
        if let i = sleeps.lastIndex(where: { $0.end == nil }) { sleeps[i].end = t } else { sleeps.append((t, t)) }
    }

    /// Whether the time between two samples was (mostly) the Mac sleeping: the sleep-stopping clock moved
    /// much less than the wall clock, or a reported sleep falls inside the gap.
    func slept(_ a: BlackBoxSample, _ b: BlackBoxSample) -> Bool {
        let wall = b.time.timeIntervalSince(a.time)
        if let u0 = a.uptime, let u1 = b.uptime, wall - (u1 - u0) > 20 { return true }
        return sleeps.contains { s in s.start >= a.time.addingTimeInterval(-5) && s.start <= b.time }
    }

    @discardableResult
    public func add(_ s: BlackBoxSample) -> Incident? {
        var found: Incident?
        if let prev = ring.last, s.time.timeIntervalSince(prev.time) >= Self.stallGap, slept(prev, s) {
            // Not an incident: record the sleep and move on.
            remember(Incident(kind: .sleep, start: prev.time, duration: s.time.timeIntervalSince(prev.time),
                              peakSwapMBPerMin: 0, suspect: ""))
        } else if let prev = ring.last, s.time.timeIntervalSince(prev.time) >= Self.stallGap, prev.strained || s.strained {
            let window = ring.suffix(24)
            found = Incident(kind: .gap, start: prev.time, duration: s.time.timeIntervalSince(prev.time),
                             peakSwapMBPerMin: max(window.map(\.swapMBPerMin).max() ?? 0, s.swapMBPerMin),
                             suspect: window.reversed().first { !$0.suspect.isEmpty }?.suspect ?? "")
        }
        ring.append(s)
        if ring.count > Self.capacity { ring.removeFirst(ring.count - Self.capacity) }
        // While strained, flush the new samples at most every 30 seconds (and right after a gap).
        if s.strained, s.time.timeIntervalSince(lastFlush) >= Self.flushInterval || found != nil { flush(now: s.time) }
        if let f = found { remember(f) }
        return found
    }

    /// The main thread answered after `seconds`: report it once it is long enough.
    @discardableResult
    public func uiLag(_ seconds: TimeInterval, at time: Date) -> Incident? {
        guard seconds >= Self.uiStallSeconds else { return nil }
        let window = ring.suffix(24)
        let i = Incident(kind: .uiStall, start: time.addingTimeInterval(-seconds), duration: seconds,
                         peakSwapMBPerMin: window.map(\.swapMBPerMin).max() ?? 0,
                         suspect: window.reversed().first { !$0.suspect.isEmpty }?.suspect ?? "")
        remember(i)
        flush(now: time)
        return i
    }

    /// At launch: if the previous run did not quit normally and its last samples were strained, report it.
    /// `previousRunWasClean` comes from the marker file the app removes when it quits normally.
    /// `bootTime`: when the Mac last booted (`kern.boottime`); later than the last sample means it was restarted.
    public func checkPreviousRun(previousRunWasClean: Bool, now: Date, bootTime: Date? = BlackBox.bootTime()) -> Incident? {
        guard !previousRunWasClean else { return nil }
        let tail = readAll().suffix(12)
        guard let last = tail.last, last.strained, now.timeIntervalSince(last.time) < 7 * 86_400 else { return nil }
        var i = Incident(kind: .endedWhileStrained, start: last.time, duration: nil,
                         peakSwapMBPerMin: tail.map(\.swapMBPerMin).max() ?? 0,
                         suspect: tail.reversed().first { !$0.suspect.isEmpty }?.suspect ?? "")
        if let b = bootTime { i.rebooted = b > last.time }
        if !incidents.contains(where: { $0.kind == i.kind && $0.start == i.start }) { remember(i) }
        return i
    }

    /// When the Mac last booted.
    public static func bootTime() -> Date? {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0, tv.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(tv.tv_sec) + TimeInterval(tv.tv_usec) / 1_000_000)
    }

    // MARK: Files

    private func flush(now: Date) {
        lastFlush = now
        guard let dir = directory else { flushed = ring.last?.time ?? flushed; return }
        let new = ring.filter { $0.time > flushed }
        guard !new.isEmpty else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = dir.appendingPathComponent(MeasurementStore.dayFormat.string(from: now) + ".tsv")
        let text = new.map(\.line).joined(separator: "\n") + "\n"
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: Data(text.utf8), attributes: [.posixPermissions: 0o600])
            prune()
        } else if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close()
        }
        flushed = new.last!.time
    }

    func files() -> [URL] {
        guard let dir = directory else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "tsv" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func prune() {
        var list = files()
        func size(_ u: URL) -> UInt64 { UInt64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        while list.count > Self.maxDays || (list.count > 1 && list.reduce(0) { $0 + size($1) } > Self.maxBytes) {
            try? FileManager.default.removeItem(at: list.removeFirst())
        }
    }

    /// Every sample on disk, oldest first.
    public func readAll() -> [BlackBoxSample] {
        files().suffix(2).flatMap { u -> [BlackBoxSample] in
            ((try? String(contentsOf: u, encoding: .utf8)) ?? "").split(separator: "\n").compactMap { BlackBoxSample(line: String($0)) }
        }.sorted { $0.time < $1.time }
    }

    private var incidentFile: URL? { directory?.appendingPathComponent("incidents.json") }

    private func remember(_ i: Incident) {
        incidents.append(i)
        if incidents.count > 50 { incidents.removeFirst(incidents.count - 50) }
        guard let url = incidentFile else { return }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(incidents) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? data.write(to: url)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func loadIncidents() -> [Incident] {
        guard let url = incidentFile, let data = try? Data(contentsOf: url) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([Incident].self, from: data)) ?? []
    }
}

/// Warns before a freeze from the trend of the swap rate. Provisional thresholds, to tune with measurements.
/// Warns when swapping is very heavy, or heavy and climbing fast; at most once per `cooldown`.
public struct FreezeForecast: Sendable {
    /// Swap in plus out that alone triggers a warning (MB per minute). Real freezes on the owner's 8 GB Mac reached 10 to 25 GB per minute.
    public static let severeMBPerMin = 3000.0
    /// Lower level that warns when it doubled within the last two minutes.
    public static let risingMBPerMin = 1000.0
    public static let cooldown: TimeInterval = 15 * 60

    public private(set) var lastWarning: Date?
    /// Thresholds in use (from the Mac's optimization profile).
    public var severe: Double
    public var rising: Double

    public init(severe: Double = FreezeForecast.severeMBPerMin, rising: Double = FreezeForecast.risingMBPerMin) {
        self.severe = severe; self.rising = rising
    }

    /// Average swap rate over the last minute, and over the minute two minutes before.
    static func averages(_ ring: [BlackBoxSample], now: Date) -> (recent: Double, earlier: Double)? {
        let recent = ring.filter { now.timeIntervalSince($0.time) <= 60 }
        let earlier = ring.filter { (120...180).contains(now.timeIntervalSince($0.time)) }
        guard recent.count >= 3 else { return nil }
        let avg = { (s: [BlackBoxSample]) in s.isEmpty ? 0 : s.reduce(0) { $0 + $1.swapMBPerMin } / Double(s.count) }
        return (avg(recent), avg(earlier))
    }

    /// Returns the current swap rate when a warning should be sent now.
    public mutating func check(_ ring: [BlackBoxSample], now: Date) -> Double? {
        if let l = lastWarning, now.timeIntervalSince(l) < Self.cooldown { return nil }
        guard let a = Self.averages(ring, now: now) else { return nil }
        let pressured = ring.last.map { $0.pressure >= 1 } ?? false
        let isSevere = a.recent >= severe
        let isRising = a.recent >= rising && a.recent >= 2 * max(a.earlier, 1) && pressured
        guard isSevere || isRising else { return nil }
        lastWarning = now
        return a.recent
    }
}
