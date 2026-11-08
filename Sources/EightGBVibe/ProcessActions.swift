import AppKit
import Foundation
import VibeCore

/// One action log entry.
struct LogEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var timestamp: Date
    var action: String
    var target: String
    var freed: UInt64
    var outcome: String

    /// JSON keys written to the log file by earlier versions. Keep them so old entries still load.
    enum CodingKeys: String, CodingKey {
        case id, timestamp = "thoiDiem", action = "hanhDong", target = "doiTuong", freed = "giaiPhong", outcome = "ketQua"
    }
}

/// Writes the log to ~/Library/Application Support/8GB Vibe/nhat-ky.jsonl (one JSON object per line).
enum ActionLog {
    static var file: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("8GB Vibe", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("nhat-ky.jsonl")
    }

    static func write(_ d: LogEntry) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard var data = try? enc.encode(d) else { return }
        data.append(0x0A)
        if let h = try? FileHandle(forWritingTo: file) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        } else {
            try? data.write(to: file)
        }
    }

    /// Reads at most `maxCount` of the newest lines.
    static func read(maxCount: Int = 300) -> [LogEntry] {
        guard let s = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return s.split(separator: "\n").suffix(maxCount).compactMap {
            try? dec.decode(LogEntry.self, from: Data($0.utf8))
        }.reversed()
    }
}

/// Quits candidates the user has confirmed. Never called without confirmation.
enum ProcessActions {
    /// Gentle quit. Returns immediately; check the result later with `isRunning`.
    /// Every target is re-checked right before the signal: same pid and start time, same user, not protected.
    static func quitAll(_ u: QuitCandidate) {
        guard u.blockedReason == nil else { return }
        switch u.quitMethod {
        case let .app(identity, _):
            guard identity.canStop() else { return }
            NSRunningApplication(processIdentifier: identity.pid)?.terminate()
        case let .simulator(app):
            runCommand("/usr/bin/xcrun", ["simctl", "shutdown", "all"])
            if let app, app.canStop() { NSRunningApplication(processIdentifier: app.pid)?.terminate() }
        case let .processes(items):
            for d in items { d.send(SIGTERM) }
        }
    }

    /// Force quit. Only used after a second confirmation. Unsaved data may be lost.
    static func forceQuit(_ u: QuitCandidate) {
        guard u.blockedReason == nil else { return }
        switch u.quitMethod {
        case let .app(identity, _):
            guard identity.canStop() else { return }
            NSRunningApplication(processIdentifier: identity.pid)?.forceTerminate()
        case let .simulator(app):
            if let app, app.canStop() { NSRunningApplication(processIdentifier: app.pid)?.forceTerminate() }
        case let .processes(items):
            for d in items { d.send(SIGKILL) }
        }
    }

    /// Whether it is still running. For Simulator: any device still booted or the app still open.
    static func isRunning(_ u: QuitCandidate) -> Bool {
        switch u.quitMethod {
        case let .app(identity, _):
            return identity.isSameProcess()
        case let .simulator(app):
            if let app, app.isSameProcess() { return true }
            return runCommand("/usr/bin/xcrun", ["simctl", "list", "devices", "booted"]).contains("(Booted)")
        case let .processes(items):
            return items.contains { $0.isSameProcess() }
        }
    }

    @discardableResult
    static func runCommand(_ path: String, _ arguments: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = arguments
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
