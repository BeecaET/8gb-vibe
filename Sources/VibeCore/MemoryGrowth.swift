import Foundation

/// Why a session's memory looks wrong.
public enum GrowthKind: Sendable, Hashable {
    /// Above `MemoryGrowth.largeLimit`.
    case large
    /// Grew steadily over the last 30 minutes. Value: average growth per 10 minutes.
    case growing(perTenMinutes: UInt64)
}

/// An agent session whose memory keeps growing or is very large. A known pattern of long Claude Code sessions:
/// `/clear` does not give the memory back, `/exit` and `claude -c` do. The app only suggests, never restarts anything.
public struct SessionMemoryWarning: Identifiable, Sendable, Hashable {
    public var id: String { sessionID }
    public var sessionID: String
    public var agent: String
    public var projectName: String?
    public var footprint: UInt64
    public var kind: GrowthKind
}

/// Memory trend checks on a short history of (time, bytes) samples.
public enum MemoryGrowth {
    /// A session above this is reported even without a trend.
    public static let largeLimit: UInt64 = 2 << 30
    /// Each 10-minute window must be at least this much higher than the previous one.
    public static let minStep: UInt64 = 100 << 20
    /// Window length and number of windows looked at.
    static let windowLength: TimeInterval = 10 * 60
    static let windowCount = 3

    /// Average per 10-minute window over the last 30 minutes, oldest first. nil when history is too short or a window is empty.
    static func windows(_ points: [(Date, UInt64)], now: Date) -> [UInt64]? {
        let start = now.addingTimeInterval(-windowLength * Double(windowCount))
        // Need samples from (almost) the start of the 30 minutes, not just the last few minutes.
        guard let first = points.first, first.0 <= start.addingTimeInterval(120) else { return nil }
        var sums = [UInt64](repeating: 0, count: windowCount)
        var counts = [UInt64](repeating: 0, count: windowCount)
        for (t, v) in points where t >= start.addingTimeInterval(-120) && t <= now {
            let i = min(windowCount - 1, max(0, Int(t.timeIntervalSince(start) / windowLength)))
            sums[i] += v; counts[i] += 1
        }
        guard counts.allSatisfy({ $0 > 0 }) else { return nil }
        return zip(sums, counts).map { $0 / $1 }
    }

    /// Session check: very large, or each 10-minute window at least `minStep` above the previous one.
    public static func check(_ points: [(Date, UInt64)], now: Date) -> GrowthKind? {
        guard let last = points.last else { return nil }
        if last.1 >= largeLimit { return .large }
        guard let w = windows(points, now: now) else { return nil }
        let rising = zip(w, w.dropFirst()).allSatisfy { $1 >= $0 + minStep }
        return rising ? .growing(perTenMinutes: (w[w.count - 1] - w[0]) / UInt64(w.count - 1)) : nil
    }

    /// Wired memory (kernel) check. A steady rise of `wiredStep` per 10 minutes can mean a kernel-side leak,
    /// which no process shows in its own footprint. Returns the rise over the window.
    public static let wiredStep: UInt64 = 200 << 20
    public static func wiredRise(_ points: [(Date, UInt64)], now: Date) -> UInt64? {
        guard let w = windows(points, now: now) else { return nil }
        let rising = zip(w, w.dropFirst()).allSatisfy { $1 >= $0 + wiredStep }
        return rising ? w[w.count - 1] - w[0] : nil
    }
}

/// Keeps a thinned history (at most one point per minute, 35 minutes) per key.
/// Not thread safe: used from one queue only.
public final class TrendHistory: @unchecked Sendable {
    private var points: [String: [(Date, UInt64)]] = [:]
    static let spacing: TimeInterval = 60
    static let keep: TimeInterval = 35 * 60

    public init() {}

    public func add(_ key: String, _ value: UInt64, now: Date) {
        var p = points[key] ?? []
        if let last = p.last, now.timeIntervalSince(last.0) < Self.spacing {
            // Keep the newest value inside the same minute.
            p[p.count - 1] = (last.0, value)
        } else {
            p.append((now, value))
        }
        p.removeAll { now.timeIntervalSince($0.0) > Self.keep }
        points[key] = p
    }

    public func get(_ key: String) -> [(Date, UInt64)] { points[key] ?? [] }

    /// Drops keys that are no longer alive.
    public func keep(only keys: Set<String>) { points = points.filter { keys.contains($0.key) } }
}
