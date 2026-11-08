import SwiftUI
import VibeCore

/// What one cleanup gave back. The size is an estimate: the footprint of each item when it was quit.
struct FreedSummary: Identifiable, Equatable {
    let id = UUID()
    var bytes: UInt64
    var count: Int
}

/// Short reward shown after a cleanup: a ring that closes with a check mark, the freed size counting up,
/// and this week's total from the action log. Hides itself after a few seconds.
/// Animations run only while the card is on screen and are skipped with Reduce Motion.
struct RewardCard: View {
    let summary: FreedSummary
    var close: () -> Void
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
                Text("Đã giải phóng khoảng").font(.caption).foregroundStyle(.secondary)
                CountUpBytes(value: shown ? Double(summary.bytes) : 0)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(summary.count == 1 ? String(localized: "1 mục đã đóng. Máy nhẹ hơn rồi.", bundle: .main)
                                        : String(localized: "\(summary.count) mục đã đóng. Máy nhẹ hơn rồi.", bundle: .main))
                    .font(.callout)
                if week.count > 1 {
                    Text("Tuần này: \(Format.bytes(week.bytes)) qua \(week.count) lần dọn")
                        .font(.caption).foregroundStyle(.secondary)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 7) { close() }
        }
    }

    /// Successful quits in the last 7 days, read from the action log (the log already stores freed size and outcome).
    static func weekTotal(now: Date = Date()) -> (bytes: UInt64, count: Int) {
        let since = now.addingTimeInterval(-7 * 24 * 3600)
        let done = ActionLog.read().filter { $0.timestamp >= since && $0.outcome.hasPrefix("Đã") }
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
