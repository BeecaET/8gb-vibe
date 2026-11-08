import SwiftUI
import VibeCore

/// First-run welcome: what the app found, where its icon lives, what happens in the first 30 minutes.
/// Skippable, shown once, reopened from About. Asks for nothing (no notifications, MCP or launch at login).
struct WelcomeSheet: View {
    @EnvironmentObject var monitor: Monitor
    static let seenKey = "daChao"

    var body: some View {
        let h = monitor.hardware
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chào mừng đến với 8GB Vibe").font(.title.weight(.bold))
                    Text("Theo dõi tài nguyên và gợi ý giảm tải khi chạy agent, Xcode, Docker trên Mac.").foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                item("checkmark.seal.fill", .green, "Đã nhận diện máy",
                     String(localized: "\(h.modelName), \(h.ramGB) GB RAM. Ngưỡng cảnh báo đã chỉnh theo máy này.", bundle: .main))
                item("menubar.rectangle", .blue, "Biểu tượng nằm trên thanh menu",
                     String(localized: "Vòng tròn nhỏ ở góc trên phải màn hình. Máy có tai thỏ (notch) có thể che mất: đóng bớt biểu tượng khác, hoặc giữ phím Cmd rồi kéo để đổi chỗ. Bấm vào vòng tròn, chọn \"Mở 8GB Vibe\" để mở cửa sổ này.", bundle: .main))
                item("hourglass", .orange, "Đang theo dõi",
                     String(localized: "App gợi ý những mục ít hoạt động trên \(Format.number(monitor.thresholds.idleMinutes, digits: 0)) phút và giữ từ 200 MB RAM. Có thể chưa có mục phù hợp. Xem trang Bộ nhớ để biết nhóm nào dùng nhiều RAM.", bundle: .main))
                item("hand.raised.fill", .purple, "Không bắt bật gì thêm",
                     String(localized: "Thông báo, kết nối agent (MCP) và mở cùng máy đều tuỳ chọn trong Cài đặt. App không tự thoát hay xoá gì; mọi lần đóng app đều hỏi bạn trước.", bundle: .main))
            }
            HStack {
                Button("Bỏ qua") { finish() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Xem bộ nhớ ngay") { finish(); monitor.page = .memory }
                Button("Bắt đầu") { finish() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
        .padding(26)
        .frame(width: 560)
    }

    private func item(_ symbol: String, _ tint: Color, _ title: LocalizedStringKey, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.seenKey)
        monitor.showWelcome = false
    }
}
