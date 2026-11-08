import AppKit
import SwiftUI
import VibeCore

/// Small window shown when clicking the menu bar icon.
/// macOS keeps this window alive even when closed, so content is only drawn while visible to save CPU.
struct PopoverView: View {
    @EnvironmentObject var monitor: Monitor
    @State private var show = false

    var body: some View {
        Group {
            if show { PopoverContent() } else { Color.clear.frame(width: 320, height: 520) }
        }
        .background(VisibilityTracker { v in
            show = v
            monitor.reportVisibility("popover", v)
        })
    }
}

struct PopoverContent: View {
    @EnvironmentObject var monitor: Monitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            if let h = monitor.system {
                metric(h).padding(.top, 14)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Swap · 1 giờ").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Spacer()
                        Text(Format.bytes(h.swap.used)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                    AreaChart(value: monitor.history.map(\.swapGB), thresholds: monitor.thresholds.swapYellowGB,
                               color: (monitor.levels[.swap] ?? .ok) == .ok ? .teal : (monitor.levels[.swap] ?? .ok).color, high: 40)
                        .collecting(monitor.history.count < 6)
                }
                .padding(.top, 14)
                topApp.padding(.top, 14)
                action.padding(.top, 14)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(30)
            }
            Divider().padding(.vertical, 10)
            footer
        }
        .padding(16)
        .frame(width: 320)
    }

    private var head: some View {
        HStack(spacing: 14) {
            HealthRing(score: monitor.score, size: 58, label: nil)
            VStack(alignment: .leading, spacing: 3) {
                Text(HealthScore.summary(monitor.score)).font(.system(size: 17, weight: .bold, design: .rounded))
                Text(monitor.explanation).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func metric(_ h: SystemSnapshot) -> some View {
        HStack(spacing: 8) {
            o("RAM", Format.percent(h.memory.usedRatio), h.memory.usedRatio, color(.pressure, .blue))
            o("Swap", Format.bytes(h.swap.used),
              Double(h.swap.used) / Format.GB / max(1, monitor.thresholds.swapRedGB), color(.swap, .teal))
            o("Ổ trống", Format.bytes(h.disk.free, digits: 0), h.disk.fullRatio, color(.disk, .purple))
        }
    }

    private func o(_ label: LocalizedStringKey, _ value: String, _ ratio: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit().motionCount()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(color.gradient).frame(width: geo.size.width * max(0.03, min(1, ratio)))
                }
            }
            .frame(height: 4)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    private var topApp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dùng nhiều RAM nhất").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            ForEach(monitor.candidates.prefix(4)) { u in
                HStack(spacing: 10) {
                    CandidateIcon(u: u, size: 22)
                    Text(u.name).lineLimit(1)
                    Spacer()
                    Text(Format.bytes(u.footprint)).monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            if !monitor.processes.sessions.isEmpty {
                HStack(spacing: 10) {
                    GroupIcon(group: .claude, size: 22)
                    Text("\(monitor.processes.sessions.count) phiên Claude Code").lineLimit(1)
                    Spacer()
                    Text(Format.bytes(monitor.processes.sessions.reduce(0) { $0 + $1.footprint }))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
    }

    @ViewBuilder private var action: some View {
        let isSlow = (monitor.levels[.slowMac] ?? .ok) != .ok
        if monitor.freeableFromCandidates > 0 || isSlow {
            Button { open(.freeRAM) } label: {
                HStack {
                    Image(systemName: isSlow ? "exclamationmark.triangle.fill" : "wand.and.stars")
                    Text(monitor.freeableFromCandidates > 0 ? String(localized: "Dọn RAM · giải phóng \(Format.bytes(monitor.freeableFromCandidates))", bundle: .main)
                                                   : String(localized: "Máy đang chậm · Dọn RAM", bundle: .main))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle(large: true))
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button { open(monitor.page) } label: { Label("Mở \(Product.name)", systemImage: "macwindow") }
                .keyboardShortcut("1")
            Spacer()
            Button { open(.about) } label: { Image(systemName: "info.circle") }
                .help("Giới thiệu \(Product.name)").accessibilityLabel("Giới thiệu \(Product.name)")
            Button { open(.settings) } label: { Image(systemName: "gearshape") }
                .help("Cài đặt").accessibilityLabel("Cài đặt")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .keyboardShortcut("q")
                .help("Thoát \(Product.name)").accessibilityLabel("Thoát \(Product.name)")
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private func color(_ c: Metric, _ defaultValue: Color) -> Color {
        let m = monitor.levels[c] ?? .ok
        return m == .ok ? defaultValue : m.color
    }

    private func open(_ page: Page) {
        monitor.page = page
        openWindow(id: "chinh")
        NSApp.activate(ignoringOtherApps: true)
    }
}
