import AppKit
import SwiftUI
import VibeCore

// Shared UI components: card, health ring, area chart, app icon, primary button.

enum Palette {
    /// Accent gradient for primary buttons and highlights: the color chosen in Settings (emerald by default, like the icon).
    static var accent: LinearGradient { AccentChoice.current.gradient }
    /// Solid accent color (the color chosen in Settings). Used instead of the system accent so every highlight follows the choice.
    static var tint: Color { AccentChoice.current.color }

    /// "What you gain" (reclaimed RAM), the lime highlight of the icon. Darker green in light mode so it stays readable.
    static let headroom = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.80, green: 0.97, blue: 0.50, alpha: 1)
            : NSColor(red: 0.13, green: 0.55, blue: 0.27, alpha: 1)
    })

    static func forScore(_ d: Int) -> Color {
        switch d {
        case 85...: return .green
        case 65..<85: return .yellow
        case 40..<65: return .orange
        default: return .red
        }
    }

    static func scoreGradient(_ d: Int) -> [Color] {
        switch d {
        case 85...: return [.mint, .green]
        case 65..<85: return [.green, .yellow]
        case 40..<65: return [.yellow, .orange]
        default: return [.orange, .red]
        }
    }
}

/// Card background: 12 pt corners, slightly raised fill, thin border.
struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.07), lineWidth: 1))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardStyle(padding: padding)) }

    /// Numbers animate smoothly when they change (macOS 14 and later).
    @ViewBuilder func motionCount() -> some View {
        if #available(macOS 14.0, *) { self.contentTransition(.numericText()) } else { self }
    }
}

extension View {
    /// Right after launch the history has few points: fade the chart and say it is still collecting, instead of a flat line.
    func collecting(_ isCollecting: Bool) -> some View {
        opacity(isCollecting ? 0.35 : 1)
            .overlay {
                if isCollecting { Text("Collecting").font(.callout).foregroundStyle(.secondary) }
            }
    }
}

/// Health score ring, colored by score.
struct HealthRing: View {
    var score: Int
    var size: CGFloat = 140
    var label: LocalizedStringKey? = "Health score"

    var body: some View {
        let color = Palette.scoreGradient(score)
        let net = max(6, size * 0.085)
        ZStack {
            Circle().stroke(Color.primary.opacity(0.07), lineWidth: net)
            Circle()
                .trim(from: 0, to: max(0.02, Double(score) / 100))
                .stroke(AngularGradient(colors: color + [color[0]], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360)),
                        style: StrokeStyle(lineWidth: net, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .motionCount()
                if let label, size >= 100 {
                    Text(label).font(.system(size: max(11, size * 0.075))).foregroundStyle(.secondary)
                }
            }
        }
        .help("An estimate, not a speed test. The score uses memory pressure, swap I/O, CPU load and free disk space.")
        .frame(width: size, height: size)
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: score)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Health score \(score) out of 100")
    }
}

/// Area chart: smooth line, fading fill, dot on the last point, optional threshold line.
struct AreaChart: View {
    var value: [Double]
    var thresholds: Double?
    var color: Color
    var high: CGFloat = 60
    var ceiling: Double?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let maxV = ceiling ?? max(value.max() ?? 1, thresholds ?? 0, 0.1) * 1.15
            let score: [CGPoint] = value.enumerated().map { i, v in
                CGPoint(x: value.count > 1 ? CGFloat(i) / CGFloat(value.count - 1) * w : w,
                        y: h - CGFloat(min(v, maxV) / maxV) * h)
            }
            ZStack(alignment: .topLeading) {
                if let n = thresholds, n < maxV {
                    Path { p in
                        let y = h - CGFloat(n / maxV) * h
                        p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                if score.count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: score[0].x, y: h))
                        score.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: score.last!.x, y: h))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    Path { p in
                        p.move(to: score[0])
                        score.dropFirst().forEach { p.addLine(to: $0) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                }
                if let last = score.last {
                    Circle().fill(color).frame(width: 7, height: 7)
                        .overlay(Circle().stroke(Color(nsColor: .controlBackgroundColor), lineWidth: 2))
                        .position(last)
                }
            }
        }
        .frame(height: high)
        .accessibilityHidden(true)
    }
}

/// The app's real icon (from Finder), cached.
struct IconApp: View {
    var path: String
    var size: CGFloat = 32

    private static let padding = NSCache<NSString, NSImage>()

    var body: some View {
        Image(nsImage: Self.icon(path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    static func icon(_ path: String) -> NSImage {
        if let i = padding.object(forKey: path as NSString) { return i }
        let i = NSWorkspace.shared.icon(forFile: path)
        i.size = NSSize(width: 64, height: 64)
        padding.setObject(i, forKey: path as NSString)
        return i
    }
}

/// Icon for a quit candidate: the real app icon if any, otherwise the group symbol.
struct CandidateIcon: View {
    var u: QuitCandidate
    var size: CGFloat = 32

    static let simulatorPath = "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app"

    var body: some View {
        if u.id.hasPrefix("app:") {
            IconApp(path: String(u.id.dropFirst(4)), size: size)
        } else if u.id == "simulator", FileManager.default.fileExists(atPath: Self.simulatorPath) {
            IconApp(path: Self.simulatorPath, size: size)
        } else {
            GroupIcon(group: u.group, size: size * 0.85).frame(width: size, height: size)
        }
    }
}

/// Colored pill-shaped status label.
struct StatusPill: View {
    var owner: LocalizedStringKey
    var color: Color
    var body: some View {
        Text(owner)
            .font(.callout.weight(.medium))
            .lineLimit(1).fixedSize()
            .foregroundStyle(color == .secondary ? Color.secondary : color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill((color == .secondary ? Color.primary : color).opacity(0.12)))
    }
}

/// Metric card with a small chart.
struct MetricCard: View {
    var label: LocalizedStringKey
    var symbol: String
    var value: String
    var subtitle: LocalizedStringKey
    var color: Color
    var data: [Double]
    var thresholds: Double?
    var ceiling: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(color)
                Text(label).foregroundStyle(.secondary)
            }
            .font(.callout)
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .motionCount()
            Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            // Just launched, history has few points: say it is collecting instead of drawing a flat line.
            AreaChart(value: data, thresholds: thresholds, color: color, high: 34, ceiling: ceiling)
                .collecting(data.count < 6)
        }
        .card(padding: 14)
    }
}
