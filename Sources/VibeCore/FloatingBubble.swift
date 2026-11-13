import CoreGraphics
import Foundation

/// When the floating status bubble shows. Off by default. Raw values are stored in UserDefaults: keep them.
public enum BubbleMode: String, CaseIterable, Sendable {
    case off, whenMinimized, always
}

/// Main window state the bubble depends on.
public struct BubbleWindowState: Equatable, Sendable {
    /// The main window is open and not minimized.
    public var mainWindowOnScreen: Bool
    /// The main window is minimized to the Dock.
    public var mainWindowMinimized: Bool
    /// The user chose "Hide" on the bubble. Cleared the next time the main window opens.
    public var hiddenByUser: Bool

    public init(mainWindowOnScreen: Bool, mainWindowMinimized: Bool, hiddenByUser: Bool) {
        self.mainWindowOnScreen = mainWindowOnScreen
        self.mainWindowMinimized = mainWindowMinimized
        self.hiddenByUser = hiddenByUser
    }
}

public enum BubbleRules {
    /// The bubble never shows next to the open main window: it stands in for it.
    /// (Full screen apps are handled by the window itself: it does not join full screen spaces.)
    public static func shouldShow(_ mode: BubbleMode, _ s: BubbleWindowState) -> Bool {
        if mode == .off || s.mainWindowOnScreen || s.hiddenByUser { return false }
        switch mode {
        case .off: return false
        case .whenMinimized: return s.mainWindowMinimized
        case .always: return true
        }
    }
}

/// What the bubble shows, already formatted. Equatable so the view is only redrawn when a shown value changes.
public struct BubbleReading: Equatable, Sendable {
    public enum Tone: Int, Sendable { case smooth, heavy, slow, overloaded }

    public var score: Int
    public var tone: Tone
    public var ram: String
    public var swap: String
    /// Swap in plus out per minute, only while the Mac is swapping enough to cost points in the health score.
    public var swapRate: String?
    /// Agent sessions, only when the user asked for them.
    public var sessions: Int?

    public init(score: Int, usedRatio: Double, swapUsed: UInt64, swapIOBytesPerSecond: Double?, sessions: Int?) {
        self.score = score
        tone = Self.tone(score)
        ram = Format.percent(usedRatio)
        swap = Format.bytes(swapUsed)
        if let io = swapIOBytesPerSecond, io >= HealthScore.swapIOStart {
            swapRate = String(localized: "\(Format.bytes(UInt64(io * 60)))/min", bundle: .main)
        } else {
            swapRate = nil
        }
        self.sessions = sessions
    }

    /// Same bands as `HealthScore.summary`.
    public static func tone(_ score: Int) -> Tone {
        switch score {
        case 85...: return .smooth
        case 65..<85: return .heavy
        case 40..<65: return .slow
        default: return .overloaded
        }
    }
}

/// Where the bubble sits. Saved as "x,y" (bottom-left origin, screen points).
public enum BubblePlacement {
    public static let margin: CGFloat = 16

    public static func encode(_ p: CGPoint) -> String { "\(Int(p.x.rounded())),\(Int(p.y.rounded()))" }

    public static func decode(_ s: String?) -> CGPoint? {
        guard let parts = s?.split(separator: ","), parts.count == 2,
              let x = Double(parts[0]), let y = Double(parts[1]) else { return nil }
        return CGPoint(x: x, y: y)
    }

    /// Top-right corner of the first screen's visible area.
    public static func defaultOrigin(size: CGSize, screen: CGRect) -> CGPoint {
        CGPoint(x: screen.maxX - size.width - margin, y: screen.maxY - size.height - margin)
    }

    /// Keeps the bubble fully on a screen: the saved spot if it is still on one (moved back inside if it hangs over
    /// an edge), otherwise the default spot. Handles screens that were unplugged or rearranged.
    public static func origin(saved: CGPoint?, size: CGSize, screens: [CGRect]) -> CGPoint {
        guard let first = screens.first else { return saved ?? .zero }
        guard let saved else { return defaultOrigin(size: size, screen: first) }
        let rect = CGRect(origin: saved, size: size)
        // The screen holding most of the bubble; none when the bubble is entirely off screen.
        var best: CGRect?
        var bestArea: CGFloat = 0
        for s in screens {
            let i = s.intersection(rect)
            let area: CGFloat = i.isNull ? 0 : i.width * i.height
            if area > bestArea { best = s; bestArea = area }
        }
        guard let s = best else { return defaultOrigin(size: size, screen: first) }
        let x: CGFloat = min(max(saved.x, s.minX), s.maxX - size.width)
        let y: CGFloat = min(max(saved.y, s.minY), s.maxY - size.height)
        return CGPoint(x: x, y: y)
    }
}
