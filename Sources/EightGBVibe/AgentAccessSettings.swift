import AppKit
import SwiftUI
import VibeCore

/// Settings > AI agents (MCP): permission level, connected agents, overdue slots, and the agent clients on this Mac.
/// Its own view so the Settings page only adds one line.
struct AgentAccessSettings: View {
    @EnvironmentObject var monitor: Monitor

    /// The MCP server inside the app bundle (Contents/Helpers), or next to the executable in a development build.
    static var serverPath: String {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/8gbvibe-mcp")
        if FileManager.default.isExecutableFile(atPath: helper.path) { return helper.path }
        return (Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("8gbvibe-mcp").path) ?? helper.path
    }

    var body: some View {
        SettingsSection {
            PickerRow(selection: $monitor.agentPolicy.level) {
                Text("Chỉ đọc").tag(AgentPolicy.Level.readOnly)
                Text("Đọc + phối hợp").tag(AgentPolicy.Level.coordinate)
                // Hidden until it does something; shown only if an older version saved it, so the picker stays valid.
                if monitor.agentPolicy.level == .lowRiskActions {
                    Text("Tự làm việc rủi ro thấp").tag(AgentPolicy.Level.lowRiskActions)
                }
            } label: {
                FormLabel("Quyền của agent", "Agent đọc trạng thái máy và phối hợp với nhau qua MCP. Không tool nào tắt tiến trình hay xoá tệp.")
            }
            if monitor.agentPolicy.level == .lowRiskActions {
                Text("Bản này chưa có việc tự làm nào: mức này hiện giống \"Đọc + phối hợp\".")
                    .font(.callout).foregroundStyle(.secondary)
            }
            // Not built yet: a plain "coming soon" label, not a dimmed switch that looks broken.
            LabeledRow {
                StatusPill(owner: "Sắp có", color: .secondary)
            } label: {
                FormLabel("Agent tự dừng mồ côi của chính phiên", "Chưa hỗ trợ. Bạn có thể tự chọn dừng tại trang Dev server; app sẽ hỏi xác nhận.")
            }
        } header: {
            Text("Quyền")
        }
        SettingsSection {
            LabeledRow {
                EmptyView()
            } label: {
                FormLabel("Đang kết nối", LocalizedStringKey(connectedSummary))
            }
            OverdueSlotsView()
        } header: {
            Text("Hoạt động")
        }
        MCPClientsView(server: Self.serverPath)
    }

    private var connectedSummary: String {
        let s = monitor.agentState
        let now = Date()
        let agents = s.agents.filter { now.timeIntervalSince($0.lastSeen) <= AgentHub.agentTimeout }
        guard !agents.isEmpty else { return String(localized: "Chưa có agent nào đăng ký.", bundle: .main) }
        var text = String(localized: "\(agents.count) agent", bundle: .main)
        let slots = s.slots.filter { $0.lease(now: now) == .active }
        for slot in slots {
            let who = agents.first { $0.id == slot.agentID }.map { "\($0.tool) (\($0.project))" } ?? slot.agentID
            text += String(localized: "; \(who) giữ chỗ \(slot.kind), còn \(Int(slot.expiresAt.timeIntervalSince(now) / 60)) phút", bundle: .main)
        }
        if !s.queue.isEmpty { text += String(localized: "; \(s.queue.count) đang chờ", bundle: .main) }
        return text
    }
}
