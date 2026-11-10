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
                            Text("\(s.holder) has held the \(s.kind) slot for over 2 hours").font(.callout.weight(.semibold))
                            Text("Since \(Self.time.string(from: s.since)). Still running: \(s.busyWith.joined(separator: ", ")). The app does not stop it.")
                                .font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button("Release slot") { confirm = s }
                    }
                }
            }

            .confirmationDialog(String(localized: "Release the heavy-job slot?", bundle: .main),
                                isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                                presenting: confirm) { s in
                Button("Release slot") { monitor.releaseOverdue(s) }
                Button("Cancel", role: .cancel) {}
            } message: { s in
                Text("Only drops the reservation of \(s.holder). No process is stopped; \(s.busyWith.joined(separator: ", ")) keeps running. Another agent may start a heavy job after this.")
            }
        }
    }

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm dd/MM/yyyy"
        return f
    }()
}
