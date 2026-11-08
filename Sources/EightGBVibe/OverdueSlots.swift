import SwiftUI
import VibeCore

/// A heavy-job slot held past its 2-hour total while the holder's job still runs. The app never stops the job
/// and never treats the slot as free; the user may release the reservation by hand.
struct OverdueSlot: Identifiable, Equatable {
    var id: String
    var holder: String
    var kind: String
    var since: Date
    var busyWith: [String]
}

/// Settings > AI agents: overdue slots with a "Release slot" button (asks first, logs it, touches no process).
struct OverdueSlotsView: View {
    @EnvironmentObject var monitor: Monitor
    @State private var confirm: OverdueSlot?

    var body: some View {
        if !monitor.overdueSlots.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(monitor.overdueSlots) { s in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "clock.badge.exclamationmark.fill").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(s.holder) giữ chỗ \(s.kind) quá 2 giờ").font(.callout.weight(.semibold))
                            Text("Từ \(Self.time.string(from: s.since)). Việc vẫn chạy: \(s.busyWith.joined(separator: ", ")). App không dừng việc này.")
                                .font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button("Nhả chỗ") { confirm = s }
                    }
                }
            }

            .confirmationDialog(String(localized: "Nhả chỗ việc nặng?", bundle: .main),
                                isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                                presenting: confirm) { s in
                Button("Nhả chỗ") { monitor.releaseOverdue(s) }
                Button("Huỷ", role: .cancel) {}
            } message: { s in
                Text("Chỉ bỏ lượt giữ chỗ của \(s.holder). Không dừng tiến trình nào; \(s.busyWith.joined(separator: ", ")) vẫn chạy. Agent khác có thể bắt đầu việc nặng sau đó.")
            }
        }
    }

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm dd/MM/yyyy"
        return f
    }()
}
