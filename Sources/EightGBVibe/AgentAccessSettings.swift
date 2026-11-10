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
                Text("Read only").tag(AgentPolicy.Level.readOnly)
                Text("Read + coordinate").tag(AgentPolicy.Level.coordinate)
                // Hidden until it does something; shown only if an older version saved it, so the picker stays valid.
                if monitor.agentPolicy.level == .lowRiskActions {
                    Text("Low-risk actions").tag(AgentPolicy.Level.lowRiskActions)
                }
            } label: {
                FormLabel("Agent permissions", "Agents read the Mac's state and coordinate through MCP. No tool quits processes or deletes files.")
            }
            if monitor.agentPolicy.level == .lowRiskActions {
                Text("This version has no automatic actions yet: this level works like \"Read + coordinate\".")
                    .font(.callout).foregroundStyle(.secondary)
            }
            // Not built yet: a plain "coming soon" label, not a dimmed switch that looks broken.
            LabeledRow {
                StatusPill(owner: "Coming soon", color: .secondary)
            } label: {
                FormLabel("Agents stop their own session's orphans", "Not supported yet. You can choose what to stop on the Dev server page; the app asks for confirmation.")
            }
        } header: {
            Text("Permissions")
        }
        SettingsSection {
            LabeledRow {
                EmptyView()
            } label: {
                FormLabel("Connected", LocalizedStringKey(connectedSummary))
            }
            OverdueSlotsView()
        } header: {
            Text("Activity")
        }
        MCPClientsView(server: Self.serverPath)
    }

    private var connectedSummary: String {
        let s = monitor.agentState
        let now = Date()
        let agents = s.agents.filter { now.timeIntervalSince($0.lastSeen) <= AgentHub.agentTimeout }
        guard !agents.isEmpty else { return String(localized: "No agent has registered yet.", bundle: .main) }
        var text = String(localized: "\(agents.count) agents", bundle: .main)
        let slots = s.slots.filter { $0.lease(now: now) == .active }
        for slot in slots {
            let who = agents.first { $0.id == slot.agentID }.map { "\($0.tool) (\($0.project))" } ?? slot.agentID
            text += String(localized: "; \(who) holds the \(slot.kind) slot, \(Int(slot.expiresAt.timeIntervalSince(now) / 60)) min left", bundle: .main)
        }
        if !s.queue.isEmpty { text += String(localized: "; \(s.queue.count) waiting", bundle: .main) }
        return text
    }
}
