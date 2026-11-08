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
                Text("Chưa thấy client agent nào trên máy này.").foregroundStyle(.secondary)
            }
            ForEach(clients) { c in row(c) }
        } header: {
            Text("Client agent trên máy này")
        } footer: {
            Text("Cài: thêm 8GB Vibe vào cấu hình MCP của client (hỏi trước, có sao lưu, ghi Nhật ký). Gỡ: chỉ xoá mục 8gbvibe.")
                .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await scan() }
        .confirmationDialog(pending.map(title) ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            presenting: pending) { p in
            Button(p.install ? String(localized: "Cài", bundle: .main) : String(localized: "Gỡ", bundle: .main)) { perform(p) }
            Button("Huỷ", role: .cancel) {}
        } message: { p in
            Text(detail(p))
        }
        SettingsSection {
            DisclosureGroup("Client khác: đoạn cấu hình để chép tay", isExpanded: $showOthers) {
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
                    Button("Cài") { pending = Pending(client: c, install: true) }.disabled(busy != nil)
                case .installed:
                    Button("Gỡ") { pending = Pending(client: c, install: false) }.disabled(busy != nil)
                case .unreadable:
                    EmptyView()
                }
            }
            if case .unreadable = state {
                Text("Không đọc được cấu hình. App không ghi vào tệp này.").font(.callout).foregroundStyle(.secondary)
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
        case .notInstalled: StatusPill(owner: "Chưa cài", color: .secondary)
        case .installed:
            if connected > 0 { StatusPill(owner: "Đã kết nối · \(connected)", color: .green) }
            else { StatusPill(owner: "Đã cài", color: .blue) }
        case .unreadable: StatusPill(owner: "Lỗi", color: .orange)
        }
    }

    private func title(_ p: Pending) -> String {
        p.install ? String(localized: "Cài 8GB Vibe vào \(p.client.kind.displayName)?", bundle: .main)
                  : String(localized: "Gỡ 8GB Vibe khỏi \(p.client.kind.displayName)?", bundle: .main)
    }

    /// Exactly what will happen: the command, or the file, the entry and the backup.
    private func detail(_ p: Pending) -> String {
        switch p.client.method {
        case let .command(add, remove):
            return String(localized: "8GB Vibe sẽ chạy lệnh chính thức của client:\n\(MCPInstall.display(p.install ? add : remove))", bundle: .main)
        case let .json(url), let .toml(url):
            let backup = String(localized: "Tệp cũ được sao lưu thành \(url.lastPathComponent).bak-8gbvibe-<giờ> trong cùng thư mục. Phần khác của tệp giữ nguyên.", bundle: .main)
            return p.install
                ? String(localized: "Thêm vào \(url.path):\n\(MCPFileInstaller.preview(p.client, server: server))\n\(backup)", bundle: .main)
                : String(localized: "Chỉ xoá mục \"8gbvibe\" trong \(url.path).\n\(backup)", bundle: .main)
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
                        return (true, backup.map { String(localized: "Sao lưu: \($0.path)", bundle: .main) } ?? "", url.path)
                    } catch {
                        return (false, Self.describe(error), url.path)
                    }
                }
            }.value
            let name = p.client.kind.displayName
            ActionLog.write(LogEntry(timestamp: Date(), action: p.install ? "Cài MCP" : "Gỡ MCP", target: "\(name): \(target)",
                                     freed: 0, outcome: ok ? "Xong" : "Lỗi"))
            var message = ok ? String(localized: "Xong.", bundle: .main) : String(localized: "Lỗi:", bundle: .main)
            if !text.isEmpty { message += " " + text }
            if ok && p.client.reopenHint { message += " " + String(localized: "Cần mở lại \(name) để nhận thay đổi.", bundle: .main) }
            results[p.client.id] = message
            states[p.client.id] = MCPClients.state(p.client)
            busy = nil
        }
    }

    private nonisolated static func describe(_ error: Error) -> String {
        switch error as? MCPConfigError {
        case .corrupt?, .notAnObject?: return String(localized: "Tệp cấu hình hỏng hoặc không phải JSON thường. Không ghi gì.", bundle: .main)
        case .serversNotAnObject?: return String(localized: "Mục mcpServers trong tệp có dạng lạ. Không ghi gì.", bundle: .main)
        case .alreadyPresent?: return String(localized: "Đã có mục 8gbvibe. Không ghi gì.", bundle: .main)
        case .notPresent?: return String(localized: "Không thấy mục 8gbvibe. Không ghi gì.", bundle: .main)
        case .verifyFailed?: return String(localized: "Kiểm lại sau khi sửa không khớp. Không ghi gì.", bundle: .main)
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
                Button("Chép") {
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
