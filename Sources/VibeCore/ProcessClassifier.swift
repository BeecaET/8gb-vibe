import Foundation

/// Work category used to group processes.
public enum WorkCategory: String, CaseIterable, Sendable, Codable {
    case claude, xcode, android, docker, browsers, chat, cloudSync, ide, otherDev, system, other

    public var name: String {
        switch self {
        case .claude: return "Claude"
        case .xcode: return "Xcode, Simulator"
        case .android: return "Android"
        case .docker: return "Docker"
        case .browsers: return String(localized: "Browsers", bundle: .main)
        case .chat: return String(localized: "Chat, meetings", bundle: .main)
        case .cloudSync: return String(localized: "Cloud sync", bundle: .main)
        case .ide: return String(localized: "IDEs, other AI", bundle: .main)
        case .otherDev: return "Node, Python, Java"
        case .system: return String(localized: "System", bundle: .main)
        case .other: return String(localized: "Other apps", bundle: .main)
        }
    }

    /// SF Symbol name.
    public var symbol: String {
        switch self {
        case .claude: return "sparkles"
        case .xcode: return "hammer"
        case .android: return "shippingbox"
        case .docker: return "cube.transparent"
        case .browsers: return "globe"
        case .chat: return "bubble.left.and.bubble.right"
        case .cloudSync: return "icloud"
        case .ide: return "chevron.left.forwardslash.chevron.right"
        case .otherDev: return "terminal"
        case .system: return "gearshape"
        case .other: return "square.grid.2x2"
        }
    }
}

/// Fixed item names used in several places.
public enum ItemName {
    public static let appClaude = String(localized: "Claude app", bundle: .main)
    public static let claudeVM = String(localized: "Claude VM", bundle: .main)
    public static let claudeCode = "Claude Code"
    public static let xcode = "Xcode"
    public static let simulator = "Simulator"
    public static let compile = String(localized: "Compilers", bundle: .main)
    public static let gradle = "Gradle"
    public static let emulator = "Emulator Android"
    public static let androidStudio = "Android Studio"
    public static let dockerDesktop = "Docker Desktop"
    public static let dockerVM = String(localized: "Docker VM", bundle: .main)
    public static let otherVM = String(localized: "Other VMs", bundle: .main)
    public static let system = String(localized: "System", bundle: .main)
}

public struct Classification: Hashable, Sendable {
    public var group: WorkCategory
    public var item: String
    public init(_ group: WorkCategory, _ item: String) { self.group = group; self.item = item }
}

/// Rules that group processes by path, name and arguments.
public enum ProcessClassifier {
    static let browsers: Set<String> = ["Google Chrome", "Safari", "CocCoc", "Arc", "Firefox", "Microsoft Edge", "Brave Browser", "Opera"]
    static let chat: Set<String> = ["Zalo", "WeChat", "LINE", "Telegram", "WhatsApp", "Signal", "Microsoft Teams", "zoom.us",
                                    "Messenger", "Slack", "Discord", "Skype", "App for Google Meet"]
    static let cloudSync: Set<String> = ["Google Drive", "OneDrive", "Synology Drive Client", "SynologyDrive", "Dropbox", "Box"]
    static let ide: Set<String> = ["Visual Studio Code", "Code", "Antigravity", "Antigravity IDE", "Codex", "ChatGPT", "ChatGPT Classic",
                                   "Cursor", "Gemini", "Windsurf", "Zed"]
    static let compile: Set<String> = ["xcodebuild", "swift-frontend", "swift-build", "swift-driver", "swiftc", "clang", "ld", "ld64",
                                        "SourceKitService", "XCBBuildService", "sourcekit-lsp", "ibtoold", "actool", "swift-plugin-server"]
    static let devRuntimes: Set<String> = ["node", "python", "python3", "Python", "bun", "deno", "java", "ruby", "npm", "npx", "uv", "uvx"]
    static let emulator: Set<String> = ["qemu-system-aarch64", "qemu-system-x86_64", "emulator", "emulator64-crash-service", "netsimd"]

    static let virtualMachine = "com.apple.Virtualization.VirtualMachine"

    public static func isClaudeCode(_ t: ProcessRecord) -> Bool {
        let last = (t.path as NSString).lastPathComponent
        if last == "claude" || t.name == "claude" { return true }
        if last == "node", t.arguments.contains(where: { $0.contains("claude-code") || $0.hasSuffix("/claude") }) { return true }
        return false
    }

    /// Classifies one process. `generic` means a catch-all rule, so the parent's category wins if it is specific.
    public static func classifyOne(_ t: ProcessRecord) -> (Classification, generic: Bool) {
        let p = t.path
        let last = p.isEmpty ? t.name : (p as NSString).lastPathComponent
        let app = t.appName

        if p.contains(virtualMachine) { return (Classification(.other, ItemName.otherVM), false) }
        if isClaudeCode(t) { return (Classification(.claude, ItemName.claudeCode), false) }
        if p.contains("/Claude.app/") || p.contains("/Application Support/Claude/") {
            return (Classification(.claude, ItemName.appClaude), false)
        }

        if p.contains("CoreSimulator") || p.contains("/Simulator.app/") { return (Classification(.xcode, ItemName.simulator), false) }
        if p.contains("/Xcode.app/") || p.contains("/Xcode-beta.app/") {
            return (Classification(.xcode, compile.contains(last) ? ItemName.compile : ItemName.xcode), false)
        }
        if compile.contains(last) { return (Classification(.xcode, ItemName.compile), false) }

        if p.contains("/Android Studio.app/") { return (Classification(.android, ItemName.androidStudio), false) }
        if last == "java" {
            let a = t.arguments.joined(separator: " ")
            if a.contains("GradleDaemon") || a.contains("org.gradle") || a.contains("KotlinCompileDaemon") || a.contains("gradle-launcher") {
                return (Classification(.android, ItemName.gradle), false)
            }
        }
        if emulator.contains(last) || p.contains("/Android/sdk/emulator/") { return (Classification(.android, ItemName.emulator), false) }
        if last == "adb" { return (Classification(.android, "adb"), false) }

        if p.contains("/Docker.app/") || p.contains("com.docker") { return (Classification(.docker, ItemName.dockerDesktop), false) }

        if browsers.contains(app) { return (Classification(.browsers, app), false) }
        if p.contains("com.apple.WebKit") { return (Classification(.browsers, "WebKit"), true) }
        if chat.contains(app) { return (Classification(.chat, app), false) }
        if cloudSync.contains(app) || p.contains("SynologyDrive") || p.contains("Google Drive") {
            return (Classification(.cloudSync, app == "SynologyDrive" ? "Synology Drive" : app), false)
        }
        if ide.contains(app) { return (Classification(.ide, app), false) }
        if last.contains("language_server") { return (Classification(.ide, "Language server"), true) }

        if devRuntimes.contains(last) { return (Classification(.otherDev, last), true) }

        if p.isEmpty || t.uid == 0 || p.hasPrefix("/System/") || p.hasPrefix("/usr/") || p.hasPrefix("/sbin/")
            || p.hasPrefix("/bin/") || p.hasPrefix("/Library/Apple/") {
            return (Classification(.system, ItemName.system), t.uid != 0)
        }
        return (Classification(.other, app), true)
    }

    /// Classifies a whole list: applies the single-process rules, lets "generic" processes inherit the parent's category, then guesses virtual machine owners.
    public static func classify(_ list: [ProcessRecord]) -> [Int32: Classification] {
        var single: [Int32: (Classification, Bool)] = [:]
        var parent: [Int32: Int32] = [:]
        for t in list {
            single[t.pid] = classifyOne(t)
            parent[t.pid] = t.ppid
        }

        var result: [Int32: Classification] = [:]
        for t in list {
            guard let (kind, generic) = single[t.pid] else { continue }
            var selection = kind
            if generic {
                var p = t.ppid
                var step = 0
                while p > 1, step < 40, let (parentKind, parentGeneric) = single[p] {
                    if !parentGeneric, parentKind.item != ItemName.otherVM {
                        selection = parentKind
                        break
                    }
                    p = parent[p] ?? 0
                    step += 1
                }
            }
            result[t.pid] = selection
        }

        // Virtual machines (Virtualization.framework) are started by launchd and have no clear parent.
        // Guess the owner: the app launched most recently before the virtual machine started.
        let claudeStart = list.filter { result[$0.pid] == Classification(.claude, ItemName.appClaude) && $0.ppid == 1 }.map(\.startDate).min()
        let dockerStart = list.filter { result[$0.pid]?.group == .docker }.map(\.startDate).min()
        for t in list where t.path.contains(virtualMachine) {
            var candidates: [(Date, Classification)] = []
            if let d = claudeStart, d <= t.startDate { candidates.append((d, Classification(.claude, ItemName.claudeVM))) }
            if let d = dockerStart, d <= t.startDate { candidates.append((d, Classification(.docker, ItemName.dockerVM))) }
            result[t.pid] = candidates.max(by: { $0.0 < $1.0 })?.1 ?? Classification(.other, ItemName.otherVM)
        }
        return result
    }
}
