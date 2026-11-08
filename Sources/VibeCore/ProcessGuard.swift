import Darwin
import Foundation

/// Processes that may not be quit from the app: parts of macOS, the Claude app, Claude Code sessions, this app.
/// Used both in the UI (to lock items) and right before sending a signal (last line of defense).
public enum ProcessGuard {
    /// Names of system processes running as the logged-in user. Used when the path cannot be read.
    static let systemNames: Set<String> = [
        "loginwindow", "launchd", "WindowServer", "kernel_task", "Dock", "Finder",
        "SystemUIServer", "ControlCenter", "NotificationCenter"
    ]

    /// macOS folders. Except `/System/Applications/` (Mail, Notes...), which the user may quit.
    static let systemDirectories = ["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/", "/Library/Apple/"]

    static var claudeReason: String { String(localized: "Đóng app Claude sẽ ngắt mọi phiên Claude Code. Hãy lưu trữ phiên trong app Claude.", bundle: .main) }

    /// Why it may not be quit. nil means it may be quit.
    public static func reason(pid: Int32, name: String, path: String, isClaudeCode: Bool = false,
                            selfIdentifier: Int32 = getpid()) -> String? {
        if pid <= 1 { return String(localized: "Tiến trình gốc của macOS.", bundle: .main) }
        if pid == selfIdentifier { return String(localized: "Chính app này.", bundle: .main) }
        let fileName = path.isEmpty ? name : (path as NSString).lastPathComponent
        if fileName == "loginwindow" || name == "loginwindow" {
            return String(localized: "Dừng loginwindow sẽ đăng xuất. Mọi app mất việc chưa lưu.", bundle: .main)
        }
        let isSystem = systemDirectories.contains { path.hasPrefix($0) } && !path.contains("/System/Applications/")
        if isSystem || systemNames.contains(fileName) || systemNames.contains(name) {
            return String(localized: "Một phần của macOS. Dừng có thể làm máy lỗi.", bundle: .main)
        }
        if path.contains("/Claude.app/") { return claudeReason }
        if isClaudeCode { return String(localized: "Phiên Claude Code đang chạy. Hãy lưu trữ phiên trong app Claude.", bundle: .main) }
        return nil
    }

    public static func reason(_ t: ProcessRecord, selfIdentifier: Int32 = getpid()) -> String? {
        reason(pid: t.pid, name: t.name, path: t.path, isClaudeCode: ProcessClassifier.isClaudeCode(t), selfIdentifier: selfIdentifier)
    }

    public static func reason(_ t: ProcessRow, selfIdentifier: Int32 = getpid()) -> String? {
        reason(pid: t.pid, name: t.name, path: t.path,
             isClaudeCode: t.kind == Classification(.claude, ItemName.claudeCode), selfIdentifier: selfIdentifier)
    }

    /// Re-reads the process right now and checks it. Returns nil if the process has exited (a signal would hit nothing).
    public static func currentReason(pid: Int32, selfIdentifier: Int32 = getpid()) -> String? {
        var cache: [String: (String, [String])] = [:]
        guard let t = ProcessReader.read(pid: pid, cache: &cache) else { return nil }
        return reason(t, selfIdentifier: selfIdentifier)
    }
}
