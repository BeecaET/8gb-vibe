import AppKit
import SwiftUI
import VibeCore

/// The agent clients found on this Mac, one row each: config state, connected agents, Install and Remove.
/// Prefers the client's own command; for file-based clients it shows the file and the exact entry first,
/// backs the file up, and touches only the "8gbvibe" key. Every install and removal is logged.
struct MCPClientsView: View {
    @EnvironmentObject var monitor: Monitor
    let server: String
    @State private var clients: [MCPClient] = []
    @State private var states: [String: MCPConfigState] = [:]
    @State private var scanned = false
    @State private var pending: Pending?
    @State private var busy: String?
    @State private var results: [String: String] = [:]
    @State private var showOthers = false

    struct Pending: Identifiable {
        var client: MCPClient
        var install: Bool
        var id: String { client.id + (install ? "+" : "-") }
    }

    var body: some View {
        SettingsSection {
            if !scanned {
                ProgressView().controlSize(.small)
            } else if clients.isEmpty {
                Text("No agent client found on this Mac.").foregroundStyle(.secondary)
            }
            ForEach(clients) { c in row(c) }
        } header: {
            Text("Agent clients on this Mac")
        } footer: {
            Text("Install adds 8GB Vibe to the client's MCP config (asks first, keeps a backup, writes to the Log). Remove only deletes the 8gbvibe entry.")
                .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await scan() }
        .confirmationDialog(pending.map(title) ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            presenting: pending) { p in
            Button(p.install ? String(localized: "Install", bundle: .main) : String(localized: "Remove", bundle: .main)) { perform(p) }
            Button("Cancel", role: .cancel) {}
        } message: { p in
            Text(detail(p))
        }
        SettingsSection {
            DisclosureGroup("Other clients: config to copy by hand", isExpanded: $showOthers) {
                VStack(alignment: .leading, spacing: 10) {
                    snippet(String(localized: "Codex: ~/.codex/config.toml", bundle: .main), MCPInstall.codexSnippet(server: server))
                    snippet(String(localized: "Cursor: ~/.cursor/mcp.json. Gemini CLI: ~/.gemini/settings.json. Antigravity: ~/.gemini/config/mcp_config.json. Claude Desktop: ~/Library/Application Support/Claude/claude_desktop_config.json", bundle: .main),
                            MCPInstall.jsonSnippet(server: server))
                }
                .padding(.top, 6)
            }
        }
    }

    /// One client: its real app icon, name, a colored status and the one button that applies (Install or Remove).
    private func row(_ c: MCPClient) -> some View {
        let state = states[c.id] ?? .notInstalled
        let agents = MCPClients.connected(c.kind, in: monitor.agentState)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                ClientIcon(kind: c.kind)
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.kind.displayName)
                    status(state, connected: agents.count)
                }
                Spacer()
                if busy == c.id { ProgressView().controlSize(.small) }
                switch state {
                case .notInstalled:
                    Button("Install") { pending = Pending(client: c, install: true) }.disabled(busy != nil)
                case .installed:
                    Button("Remove") { pending = Pending(client: c, install: false) }.disabled(busy != nil)
                case .unreadable:
                    EmptyView()
                }
            }
            if case .unreadable = state {
                Text("Config could not be read. The app will not write to this file.").font(.callout).foregroundStyle(.secondary)
            }
            if let r = results[c.id] {
                Text(r).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    /// Not installed, Installed, Connected (n agents) or Error.
    @ViewBuilder private func status(_ s: MCPConfigState, connected: Int) -> some View {
        switch s {
        case .notInstalled: StatusPill(owner: "Not installed", color: .secondary)
        case .installed:
            if connected > 0 { StatusPill(owner: "Connected · \(connected)", color: .green) }
            else { StatusPill(owner: "Installed", color: .blue) }
        case .unreadable: StatusPill(owner: "Error", color: .orange)
        }
    }

    private func title(_ p: Pending) -> String {
        p.install ? String(localized: "Install 8GB Vibe in \(p.client.kind.displayName)?", bundle: .main)
                  : String(localized: "Remove 8GB Vibe from \(p.client.kind.displayName)?", bundle: .main)
    }

    /// Exactly what will happen: the command, or the file, the entry and the backup.
    private func detail(_ p: Pending) -> String {
        switch p.client.method {
        case let .command(add, remove):
            return String(localized: "8GB Vibe will run the client's official command:\n\(MCPInstall.display(p.install ? add : remove))", bundle: .main)
        case let .json(url), let .toml(url):
            let backup = String(localized: "The old file is backed up as \(url.lastPathComponent).bak-8gbvibe-<time> in the same folder. The rest of the file stays as it is.", bundle: .main)
            return p.install
                ? String(localized: "Add to \(url.path):\n\(MCPFileInstaller.preview(p.client, server: server))\n\(backup)", bundle: .main)
                : String(localized: "Only removes the \"8gbvibe\" entry in \(url.path).\n\(backup)", bundle: .main)
        }
    }

    private func scan() async {
        let server = server
        let found = await Task.detached(priority: .utility) { () -> ([MCPClient], [String: MCPConfigState]) in
            let list = MCPClients.detect(server: server)
            return (list, Dictionary(uniqueKeysWithValues: list.map { ($0.id, MCPClients.state($0)) }))
        }.value
        clients = found.0
        states = found.1
        scanned = true
    }

    /// Runs only from the confirmation dialog.
    private func perform(_ p: Pending) {
        busy = p.client.id
        let server = server
        Task {
            let (ok, text, target) = await Task.detached(priority: .userInitiated) { () -> (Bool, String, String) in
                switch p.client.method {
                case let .command(add, remove):
                    let args = p.install ? add : remove
                    let (status, out) = Self.run(args)
                    return (status == 0, out, MCPInstall.display(args))
                case let .json(url), let .toml(url):
                    do {
                        let outcome = try MCPFileInstaller.apply(p.client, install: p.install, server: server)
                        guard case let .done(backup) = outcome else { return (true, "", url.path) }
                        return (true, backup.map { String(localized: "Backup: \($0.path)", bundle: .main) } ?? "", url.path)
                    } catch {
                        return (false, Self.describe(error), url.path)
                    }
                }
            }.value
            let name = p.client.kind.displayName
            ActionLog.write(LogEntry(timestamp: Date(), action: p.install ? "Install MCP" : "Remove MCP", target: "\(name): \(target)",
                                     freed: 0, outcome: ok ? "Done" : "Error"))
            var message = ok ? String(localized: "Done.", bundle: .main) : String(localized: "Error:", bundle: .main)
            if !text.isEmpty { message += " " + text }
            if ok && p.client.reopenHint { message += " " + String(localized: "Reopen \(name) to pick up the change.", bundle: .main) }
            results[p.client.id] = message
            states[p.client.id] = MCPClients.state(p.client)
            busy = nil
        }
    }

    private nonisolated static func describe(_ error: Error) -> String {
        switch error as? MCPConfigError {
        case .corrupt?, .notAnObject?: return String(localized: "The config file is damaged or not plain JSON. Nothing was written.", bundle: .main)
        case .serversNotAnObject?: return String(localized: "mcpServers in the file has an unexpected shape. Nothing was written.", bundle: .main)
        case .alreadyPresent?: return String(localized: "The 8gbvibe entry is already there. Nothing was written.", bundle: .main)
        case .notPresent?: return String(localized: "No 8gbvibe entry found. Nothing was written.", bundle: .main)
        case .verifyFailed?: return String(localized: "The check after editing did not match. Nothing was written.", bundle: .main)
        case nil: return error.localizedDescription
        }
    }

    /// Runs a client's own command and returns its exit status and output.
    private nonisolated static func run(_ args: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: args[0])
        p.arguments = Array(args.dropFirst())
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        do {
            try p.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return (p.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return (-1, error.localizedDescription)
        }
    }

    private func snippet(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
            Text(text).font(.callout.monospaced()).textSelection(.enabled)
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

/// The client's real app icon when its app is installed; otherwise a symbol for command line tools.
struct ClientIcon: View {
    let kind: MCPClientKind

    private static let apps: [MCPClientKind: [String]] = [
        .claudeCode: ["/Applications/Claude.app"],
        .claudeDesktop: ["/Applications/Claude.app"],
        .codex: ["/Applications/Codex.app", "/Applications/ChatGPT.app"],
        .cursor: ["/Applications/Cursor.app"],
        .antigravity: ["/Applications/Antigravity.app"],
        .geminiCLI: [],
    ]

    var body: some View {
        if let path = Self.apps[kind]?.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            IconApp(path: path, size: 28)
        } else {
            Image(systemName: "terminal")
                .font(.body).foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                .accessibilityHidden(true)
        }
    }
}
