import Foundation

/// A known cache or large data folder. Measured only, never deleted.
public struct DiskItem: Identifiable, Sendable, Hashable {
    public enum Kind: String, Sendable {
        /// Recreated automatically. MVP 2 will allow cleaning it.
        case safe
        /// The user should review it before cleaning.
        case review
        /// Another app's data. Clean it inside that app.
        case inApp
    }

    public var id: String { path }
    public var name: String
    public var path: String
    public var kind: Kind
    public var note: String
    public var bytes: UInt64?

    public init(_ name: String, _ path: String, _ kind: Kind, _ note: String) {
        self.name = name
        self.path = (path as NSString).expandingTildeInPath
        self.kind = kind
        self.note = note
    }
}

public enum DiskScanner {
    public static let catalog: [DiskItem] = [
        DiskItem("Xcode DerivedData", "~/Library/Developer/Xcode/DerivedData", .safe, String(localized: "Xcode tự tạo lại khi build.", bundle: .main)),
        DiskItem("Cache npm", "~/.npm/_cacache", .safe, String(localized: "Cache gói npm; có thể cần tải lại khi cài gói.", bundle: .main)),
        DiskItem("Cache pip", "~/Library/Caches/pip", .safe, String(localized: "Dọn bằng pip cache purge.", bundle: .main)),
        DiskItem("Cache uv", "~/.cache/uv", .safe, String(localized: "Dọn bằng uv cache clean.", bundle: .main)),
        DiskItem("Cache Homebrew", "~/Library/Caches/Homebrew", .safe, String(localized: "Dọn bằng brew cleanup.", bundle: .main)),
        DiskItem("Cache Gradle", "~/.gradle/caches", .safe, String(localized: "Gradle tải lại khi build.", bundle: .main)),
        DiskItem("Cache Codex", "~/Library/Caches/com.openai.codex", .safe, String(localized: "Tạo lại khi dùng Codex.", bundle: .main)),
        DiskItem("Cache Codex (2)", "~/Library/Caches/Codex", .safe, String(localized: "Tạo lại khi dùng Codex.", bundle: .main)),
        DiskItem("Runtime Codex", "~/.cache/codex-runtimes", .safe, String(localized: "Tải lại khi dùng Codex.", bundle: .main)),
        DiskItem(String(localized: "Trình duyệt Playwright", bundle: .main), "~/Library/Caches/ms-playwright", .safe, String(localized: "Tải lại bằng playwright install.", bundle: .main)),
        DiskItem(String(localized: "Trình duyệt Puppeteer", bundle: .main), "~/.cache/puppeteer", .safe, String(localized: "Tải lại khi chạy Puppeteer.", bundle: .main)),
        DiskItem("Cache Electron", "~/Library/Caches/electron", .safe, String(localized: "Tải lại khi build app Electron.", bundle: .main)),

        DiskItem(String(localized: "Dữ liệu Docker", bundle: .main), "~/Library/Containers/com.docker.docker", .review, String(localized: "Có thể chứa database, volume. Xem bằng docker system df.", bundle: .main)),
        DiskItem(String(localized: "Thiết bị Simulator", bundle: .main), "~/Library/Developer/CoreSimulator/Devices", .review, String(localized: "Có thể chứa dữ liệu test.", bundle: .main)),
        DiskItem("Runtime Simulator", "/Library/Developer/CoreSimulator", .review, String(localized: "Gồm runtime và dữ liệu Simulator dùng chung. Quản lý trong Xcode.", bundle: .main)),
        DiskItem("iOS DeviceSupport", "~/Library/Developer/Xcode/iOS DeviceSupport", .review, String(localized: "Cần khi cắm iPhone thật để debug.", bundle: .main)),
        DiskItem("Xcode Archives", "~/Library/Developer/Xcode/Archives", .review, String(localized: "Cần khi gửi bản lên App Store.", bundle: .main)),
        DiskItem("HuggingFace", "~/.cache/huggingface", .review, String(localized: "Model AI. Tải lại lâu.", bundle: .main)),
        DiskItem("Android SDK", "~/Library/Android/sdk", .review, String(localized: "Có thể còn dùng để build.", bundle: .main)),
        DiskItem(String(localized: "Android (emulator, cấu hình)", bundle: .main), "~/.android", .review, String(localized: "Chứa máy ảo emulator.", bundle: .main)),
        DiskItem(String(localized: "App Claude: máy ảo", bundle: .main), "~/Library/Application Support/Claude/vm_bundles", .review, String(localized: "Của app Claude. Không xoá từ ngoài.", bundle: .main)),

        DiskItem(String(localized: "Dữ liệu Zalo", bundle: .main), "~/Library/Application Support/ZaloData", .inApp, String(localized: "Dọn trong app Zalo.", bundle: .main)),
        DiskItem(String(localized: "Dữ liệu WeChat", bundle: .main), "~/Library/Containers/com.tencent.xinWeChat", .inApp, String(localized: "Dọn trong app WeChat.", bundle: .main)),
        DiskItem(String(localized: "Tải về", bundle: .main), "~/Downloads", .inApp, String(localized: "Xem và xoá bằng Finder.", bundle: .main))
    ]

    /// Measures the real size on disk (counts sparse files such as Docker.raw correctly). Slow on large folders: call on a background thread.
    public static func measureSize(_ path: String, shouldStop: () -> Bool = { false }) -> UInt64? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return nil }
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        let url = URL(fileURLWithPath: path)
        if !isDir.boolValue {
            let v = try? url.resourceValues(forKeys: Set(keys))
            return UInt64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else {
            return nil
        }
        var total: UInt64 = 0
        var padding = 0
        for case let f as URL in e {
            padding += 1
            if padding % 2000 == 0, shouldStop() { return nil }
            guard let v = try? f.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            total += UInt64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }
}

/// Services started at login or boot (LaunchAgents, LaunchDaemons). Read only.
public struct BackgroundItem: Identifiable, Sendable, Hashable {
    public enum Scope: String, Sendable {
        case currentUser = "Của bạn"
        case allUsers = "Mọi người dùng"
        case system = "Dịch vụ hệ thống (root)"
    }
    public var id: String { file }
    public var label: String
    public var program: String
    public var scope: Scope
    public var runAtLoad: Bool
    public var keepAlive: Bool
    public var file: String
}

public enum BackgroundItemReader {
    public static func readAll() -> [BackgroundItem] {
        let items: [(String, BackgroundItem.Scope)] = [
            (("~/Library/LaunchAgents" as NSString).expandingTildeInPath, .currentUser),
            ("/Library/LaunchAgents", .allUsers),
            ("/Library/LaunchDaemons", .system)
        ]
        var result: [BackgroundItem] = []
        for (directory, scope) in items {
            guard let file = try? FileManager.default.contentsOfDirectory(atPath: directory) else { continue }
            for t in file.sorted() where t.hasSuffix(".plist") {
                let path = (directory as NSString).appendingPathComponent(t)
                if let m = readFile(path, scope: scope) { result.append(m) }
            }
        }
        return result
    }

    static func readFile(_ path: String, scope: BackgroundItem.Scope) -> BackgroundItem? {
        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        return analyze(plist, file: path, scope: scope)
    }

    static func analyze(_ plist: [String: Any], file: String, scope: BackgroundItem.Scope) -> BackgroundItem {
        let label = plist["Label"] as? String ?? ((file as NSString).lastPathComponent as NSString).deletingPathExtension
        let programPath = plist["Program"] as? String ?? (plist["ProgramArguments"] as? [String])?.first ?? ""
        let keepAlive: Bool
        if let b = plist["KeepAlive"] as? Bool { keepAlive = b } else { keepAlive = plist["KeepAlive"] is [String: Any] }
        return BackgroundItem(label: label, program: programPath, scope: scope,
                          runAtLoad: plist["RunAtLoad"] as? Bool ?? false,
                          keepAlive: keepAlive, file: file)
    }
}
