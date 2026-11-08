import SwiftUI
import VibeCore

/// What one cleanup gave back. `bytes` is an estimate: the footprint of each item when it was quit.
/// `measured` is filled in 10 seconds later: RAM and swap in use before minus after.
struct FreedSummary: Identifiable, Equatable {
    let id = UUID()
    var bytes: UInt64
    var count: Int
    /// Items in the batch that did not quit (still running after 10 seconds).
    var failed: Int = 0
    var measured: MeasuredDrop? = nil
    var measuring = true
}

/// Short reward shown after a cleanup: a ring that closes with a check mark, the freed size counting up,
/// and this week's total from the action log. Hides itself after a few seconds.
/// Animations run only while the card is on screen and are skipped with Reduce Motion.
struct RewardCard: View {
    let summary: FreedSummary
    var close: () -> Void
    /// Opens the action log (shown when some items did not quit).
    var openLog: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var week: (bytes: UInt64, count: Int) = (0, 0)

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Palette.headroom.opacity(0.25), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: shown ? 1 : 0)
                    .stroke(Palette.headroom, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Palette.headroom)
                    .scaleEffect(shown ? 1 : 0.3)
                    .opacity(shown ? 1 : 0)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ước tính theo app").font(.callout).foregroundStyle(.secondary)
                CountUpBytes(value: shown ? Double(summary.bytes) : 0)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                // Facts only: how many closed; the measured effect comes 10 seconds later.
                Text(summary.count == 1 ? String(localized: "Đã đóng 1 mục.", bundle: .main)
                                        : String(localized: "Đã đóng \(summary.count) mục.", bundle: .main))
                    .font(.callout)
                if summary.failed > 0 {
                    HStack(spacing: 6) {
                        Label(summary.failed == 1 ? String(localized: "1 mục chưa thoát", bundle: .main)
                                                  : String(localized: "\(summary.failed) mục chưa thoát", bundle: .main),
                              systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        if let openLog {
                            Button("Xem Nhật ký") { openLog() }.buttonStyle(.link)
                        }
                    }
                    .font(.callout)
                }
                Group {
                    if let m = summary.measured {
                        Text("Thay đổi sau khi đóng: RAM giảm \(Self.signed(m.ram)), swap giảm \(Self.signed(m.swap)). Số âm là tăng; có thể lẫn hoạt động khác.")
                    } else if summary.measuring {
                        Text("Đang đo lại RAM và swap sau 10 giây...")
                    }
                }
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                if week.count > 1 {
                    Text("7 ngày qua, RAM các mục đã đóng (ước tính): \(Format.bytes(week.bytes)) qua \(week.count) mục.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button(action: close) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Đóng")
                .accessibilityLabel("Đóng")
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.headroom.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .accessibilityElement(children: .combine)
        .onAppear {
            week = Self.weekTotal()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.9)) { shown = true }
            // Stay until the measurement is in, then a few more seconds to read it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { close() }
        }
    }

    /// "1.2 GB", or "-300 MB" when usage went up (something else grew meanwhile).
    static func signed(_ v: Int64) -> String {
        v >= 0 ? Format.bytes(UInt64(v)) : "-" + Format.bytes(UInt64(-v))
    }

    /// Successful quits in the last 7 days, read from the action log (the log already stores freed size and outcome).
    static func weekTotal(now: Date = Date()) -> (bytes: UInt64, count: Int) {
        let since = now.addingTimeInterval(-7 * 24 * 3600)
        // Only quits and stops count (not MCP installs, slot releases or measurements).
        let quits: Set<String> = ["Thoát", "Dừng", "Buộc thoát", "Buộc dừng"]
        let done = ActionLog.read().filter { $0.timestamp >= since && quits.contains($0.action) && $0.outcome.hasPrefix("Đã") }
        return (done.reduce(0) { $0 + $1.freed }, done.count)
    }
}

/// A byte count that animates between values (counts up when it appears).
struct CountUpBytes: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var body: some View {
        Text(Format.bytes(UInt64(max(0, value)))).monospacedDigit()
    }
}
