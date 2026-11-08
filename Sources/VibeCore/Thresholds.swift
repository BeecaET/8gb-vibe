import Foundation

public enum Level: Int, Comparable, Sendable, Codable {
    case ok = 0, warning = 1, critical = 2
    public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
}

public enum Metric: String, CaseIterable, Sendable, Codable {
    case pressure, swap, disk, load, claudeSessions, slowMac

    public var name: String {
        switch self {
        case .pressure: return String(localized: "Áp lực bộ nhớ", bundle: .main)
        case .swap: return "Swap"
        case .disk: return String(localized: "Ổ đĩa", bundle: .main)
        case .load: return String(localized: "Tải CPU", bundle: .main)
        case .claudeSessions: return String(localized: "Phiên Claude Code", bundle: .main)
        case .slowMac: return String(localized: "Máy chậm", bundle: .main)
        }
    }
}

/// Alert thresholds. Defaults suit an 8 GB Mac.
public struct Thresholds: Codable, Equatable, Sendable {
    public var swapYellowGB: Double = 3
    public var swapRedGB: Double = 6
    public var diskFreeYellowGB: Double = 40
    public var diskFreeRedGB: Double = 20
    public var load5Yellow: Double = 16
    public var load5Red: Double = 32
    public var sessionsYellow: Int = 6
    public var sessionsRed: Int = 10
    public var idleMinutes: Double = 30

    public init() {}

    /// Keys stored in UserDefaults by earlier versions. Keep them so saved thresholds still load.
    enum CodingKeys: String, CodingKey {
        case swapYellowGB = "swapVangGB", swapRedGB = "swapDoGB"
        case diskFreeYellowGB = "oTrongVangGB", diskFreeRedGB = "oTrongDoGB"
        case load5Yellow = "tai5Vang", load5Red = "tai5Do"
        case sessionsYellow = "phienVang", sessionsRed = "phienDo"
        case idleMinutes = "phutRanh"
    }

    public func evaluate(_ h: SystemSnapshot, sessionCount: Int) -> [Metric: Level] {
        let gb = Format.GB
        func high(_ x: Double, _ yellow: Double, _ red: Double) -> Level { x >= red ? .critical : (x >= yellow ? .warning : .ok) }
        func low(_ x: Double, _ yellow: Double, _ red: Double) -> Level { x <= red ? .critical : (x <= yellow ? .warning : .ok) }
        let pressure: Level = h.pressure == .critical ? .critical : (h.pressure == .warning ? .warning : .ok)
        // Slow Mac: so short of RAM that it swaps a lot while the CPU is also heavily loaded.
        let swapGB = Double(h.swap.used) / gb
        let slowMac: Level
        if h.pressure == .critical || (swapGB >= swapRedGB && h.load.m5 >= load5Yellow) || h.load.m5 >= load5Red {
            slowMac = .critical
        } else if h.pressure == .warning && swapGB >= swapYellowGB && h.load.m5 >= load5Yellow {
            slowMac = .warning
        } else {
            slowMac = .ok
        }
        return [
            .slowMac: slowMac,
            .pressure: pressure,
            .swap: high(Double(h.swap.used) / gb, swapYellowGB, swapRedGB),
            .disk: low(Double(h.disk.free) / gb, diskFreeYellowGB, diskFreeRedGB),
            .load: high(h.load.m5, load5Yellow, load5Red),
            .claudeSessions: high(Double(sessionCount), Double(sessionsYellow), Double(sessionsRed))
        ]
    }
}

/// Decides when to send a notification: only when the level rises, and at least `interval` apart per metric.
public struct AlertThrottle: Sendable {
    public var interval: TimeInterval = 30 * 60
    private var previousLevel: [Metric: Level] = [:]
    private var lastSent: [Metric: Date] = [:]

    public init(interval: TimeInterval = 30 * 60) { self.interval = interval }

    public mutating func check(_ item: [Metric: Level], now: Date) -> [(Metric, Level)] {
        var gui: [(Metric, Level)] = []
        for metric in Metric.allCases {
            let m = item[metric] ?? .ok
            let before = previousLevel[metric] ?? .ok
            if m > before, m != .ok {
                if let last = lastSent[metric], now.timeIntervalSince(last) < interval {
                    // Too soon. Do not send.
                } else {
                    gui.append((metric, m))
                    lastSent[metric] = now
                }
            }
            previousLevel[metric] = m
        }
        return gui
    }
}
