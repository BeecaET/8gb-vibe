import AppKit
import SwiftUI
import VibeCore

extension Level {
    var color: Color {
        switch self {
        case .ok: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    var nsColor: NSColor {
        switch self {
        case .ok: return .systemGreen
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }

    var status: String {
        switch self {
        case .ok: return String(localized: "Mac is fine", bundle: .main)
        case .warning: return String(localized: "Memory is tight", bundle: .main)
        case .critical: return String(localized: "Mac is overloaded", bundle: .main)
        }
    }
}

extension WorkCategory {
    var color: Color {
        switch self {
        case .claude: return .purple
        case .xcode: return .orange
        case .android: return .green
        case .docker: return .blue
        case .browsers: return .teal
        case .chat: return .mint
        case .cloudSync: return .cyan
        case .ide: return .indigo
        case .otherDev: return .brown
        case .system: return .gray
        case .other: return Color(nsColor: .tertiaryLabelColor)
        }
    }
}

/// Round gauge. `ratio` goes from 0 to 1.
struct GaugeRing: View {
    var ratio: Double
    var value: String
    var label: LocalizedStringKey
    var color: Color
    var size: CGFloat = 56

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.08), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: max(0.02, min(1, ratio)))
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(value)
                    .font(.system(size: size * 0.21, weight: .medium))
                    .monospacedDigit()
            }
            .frame(width: size, height: size)
            Text(label).font(.callout).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label) + Text(verbatim: ": \(value)"))
    }
}

/// Small line chart, hand drawn to stay light. Optional threshold line.
struct Sparkline: View {
    var value: [Double]
    var thresholds: Double?
    var color: Color
    var high: CGFloat = 34

    var body: some View {
        GeometryReader { geo in
            let maxV = max(value.max() ?? 1, thresholds ?? 0, 0.1) * 1.1
            let w = geo.size.width, h = geo.size.height
            ZStack {
                if let n = thresholds {
                    Path { p in
                        let y = h - CGFloat(n / maxV) * h
                        p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                }
                Path { p in
                    guard value.count > 1 else { return }
                    for (i, v) in value.enumerated() {
                        let pt = CGPoint(x: CGFloat(i) / CGFloat(value.count - 1) * w, y: h - CGFloat(v / maxV) * h)
                        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
        }
        .frame(height: high)
        .accessibilityHidden(true)
    }
}

/// Stat box: small label on top, big number below.
struct StatBox: View {
    var label: LocalizedStringKey
    var value: String
    var color: Color = .primary
    var subtitle: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.medium)).monospacedDigit().foregroundStyle(color)
            if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Group icon as a colored rounded square.
struct GroupIcon: View {
    var group: WorkCategory
    var size: CGFloat = 22
    var body: some View {
        Image(systemName: group.symbol)
            .font(.system(size: size * 0.55, weight: .medium))
            .foregroundStyle(group.color)
            .frame(width: size, height: size)
            .background(group.color.opacity(0.15), in: RoundedRectangle(cornerRadius: size * 0.27))
            .accessibilityHidden(true)
    }
}

/// RAM budget bar: colored by group, plus the system's wired memory.
struct BudgetBar: View {
    var budget: RAMBudget
    var high: CGFloat = 14

    var body: some View {
        let total = max(Double(budget.demand), Double(budget.totalRAM), 1)
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 1) {
                        Rectangle().fill(Self.wiredColor)
                            .frame(width: max(0, w * Double(budget.wired) / total - 1))
                        ForEach(budget.groups, id: \.group) { n in
                            Rectangle().fill(n.group.color)
                                .frame(width: max(0, w * Double(n.footprint) / total - 1))
                        }
                    }
                    // The Mac's RAM marker.
                    Rectangle().fill(Color.primary)
                        .frame(width: 2, height: high + 6)
                        .offset(x: min(w - 2, w * Double(budget.totalRAM) / total))
                }
            }
            .frame(height: high)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            HStack {
                Text("0").font(.callout).foregroundStyle(.secondary)
                Spacer()
                if budget.overflow > 0 {
                    Text("\(Format.bytes(budget.overflow)) over, compressed or swapped")
                        .font(.callout).foregroundStyle(.red)
                }
                Spacer()
                Text("Line: installed RAM \(Format.bytes(budget.totalRAM, digits: 0))").font(.callout).foregroundStyle(.secondary)
            }
            legend.padding(.top, 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Apps need \(Format.bytes(budget.demand)), this Mac has \(Format.bytes(budget.totalRAM))")
    }

    /// Wired uses a dark neutral color, different from the gray of the System group.
    static let wiredColor = Color.primary.opacity(0.45)

    /// Color legend: wired and the groups in bar order.
    private var legend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .leading)], alignment: .leading, spacing: 6) {
            legendItem(Self.wiredColor, String(localized: "Wired (held by system)", bundle: .main), budget.wired)
            ForEach(budget.groups.filter { $0.footprint >= 50 << 20 }, id: \.group) { n in
                legendItem(n.group.color, n.group.name, n.footprint)
            }
        }
    }

    private func legendItem(_ color: Color, _ name: String, _ byteCount: UInt64) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(name).lineLimit(1)
            Text(Format.bytes(byteCount)).monospacedDigit().foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}

/// Draws the menu bar icon: a ring colored by level.
enum MenuBarIcon {
    static func ring(ratio: Double, color: NSColor) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let img = NSImage(size: size, flipped: false) { rect in
            let r = rect.insetBy(dx: 2, dy: 2)
            let track = NSBezierPath(ovalIn: r)
            track.lineWidth = 2.2
            NSColor.labelColor.withAlphaComponent(0.25).setStroke()
            track.stroke()
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let arc = NSBezierPath()
            let ended = 90 - 360 * max(0.04, min(1, ratio))
            arc.appendArc(withCenter: center, radius: r.width / 2, startAngle: 90, endAngle: ended, clockwise: true)
            arc.lineWidth = 2.2
            arc.lineCapStyle = .round
            color.setStroke()
            arc.stroke()
            return true
        }
        img.isTemplate = false
        return img
    }
}

extension Monitor {
    /// Status to display. Returns nil when there is not enough data yet (monitoring just started), so rows do not repeat meaningless text.
    func displayStatus(cpu: Double, lastActive: Date) -> (String, Color)? {
        let statusText = status(cpu: cpu, lastActive: lastActive)
        return statusText.1 == .secondary ? nil : statusText
    }
}
