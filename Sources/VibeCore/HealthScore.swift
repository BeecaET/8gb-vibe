import Foundation

/// Health score from 0 to 100. Higher is smoother.
/// Deducts points for memory pressure, swap activity, CPU load and free disk, against the user's thresholds.
public enum HealthScore {
    /// Swap I/O (in plus out) where the swap deduction starts and where it is full. Provisional, to be tuned with measurements.
    public static let swapIOStart = 0.2 * 1_048_576
    public static let swapIOFull = 5.0 * 1_048_576

    /// `swapIO`: swap in plus out, bytes per second, between the last two samples. nil when unknown (first sample).
    /// A large swap file alone costs nothing: only swapping in or out slows the Mac.
    public static func compute(_ h: SystemSnapshot, thresholds: Thresholds, swapIO: Double? = nil) -> Int {
        let gb = Format.GB
        var score = 100.0

        switch h.pressure {
        case .normal: break
        case .warning: score -= 20
        case .critical: score -= 40
        }

        // Swap activity: deducts from 0 to 25 points between `swapIOStart` and `swapIOFull`.
        if let io = swapIO {
            score -= 25 * ratio(io, from: swapIOStart, to: swapIOFull)
        }

        // 5 minute load: up to 25 points.
        score -= 25 * ratio(h.load.m5, from: thresholds.load5Yellow / 2, to: thresholds.load5Red * 1.5)

        // Free disk: up to 10 points.
        let free = Double(h.disk.free) / gb
        score -= 10 * ratio(thresholds.diskFreeYellowGB - free, from: 0, to: thresholds.diskFreeYellowGB - thresholds.diskFreeRedGB / 2)

        return Int(max(0, min(100, score)).rounded())
    }

    /// Position of x within [from, to], clamped to 0...1.
    static func ratio(_ x: Double, from: Double, to: Double) -> Double {
        guard to > from else { return x >= to ? 1 : 0 }
        return max(0, min(1, (x - from) / (to - from)))
    }

    public static func summary(_ score: Int) -> String {
        switch score {
        case 85...: return String(localized: "Máy đang mượt", bundle: .main)
        case 65..<85: return String(localized: "Máy hơi nặng", bundle: .main)
        case 40..<65: return String(localized: "Máy đang chậm", bundle: .main)
        default: return String(localized: "Máy đang quá tải", bundle: .main)
        }
    }
}
