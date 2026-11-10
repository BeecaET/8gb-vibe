import AppKit
import Foundation
import VibeCore

/// One action log entry.
struct LogEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var timestamp: Date
    var action: String
    var target: String
    /// Estimated: the footprint of what was closed (key "giaiPhong", kept for older versions).
    var freed: UInt64
    var outcome: String
    /// Measured: RAM and swap in use before closing minus 10 seconds after (key "doDuoc"). Nil in older entries.
    var measured: MeasuredDrop? = nil

    /// JSON keys written to the log file by earlier versions. Keep them so old entries still load.
    enum CodingKeys: String, CodingKey {
        case id, timestamp = "thoiDiem", action = "hanhDong", target = "doiTuong", freed = "giaiPhong", outcome = "ketQua"
        case measured = "doDuoc"
    }
}

/// Writes the log to ~/Library/Application Support/8GB Vibe/nhat-ky.jsonl (one JSON object per line).
enum ActionLog {
    static var file: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("8GB Vibe", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return directory.appendingPathComponent(StoredName.logFile)
    }

    /// The log names the apps the user quit: owner-only (0600), like every other file of the app.
    static func write(_ d: LogEntry) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard var data = try? enc.encode(d) else { return }
        data.append(0x0A)
        let url = file
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        } else {
            FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600])
        }
        tightenPermissions()
    }

    /// Fixes a log created by 1.1.1 or earlier with 0644. Called on write and at launch.
    static func tightenPermissions() {
        let path = file.path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let mode = attrs[.posixPermissions] as? Int, mode & 0o077 != 0 else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }

    /// Reads at most `maxCount` of the newest lines.
    static func read(maxCount: Int = 300) -> [LogEntry] {
        guard let s = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return s.split(separator: "\n").suffix(maxCount).compactMap {
            (try? dec.decode(LogEntry.self, from: Data($0.utf8))).map(normalized)
        }.reversed()
    }

    /// Outcomes that mean the target is gone or the action worked (shown in green, counted as freed RAM).
    static let successOutcomes: Set<String> = ["Closed", "Done", "Slot released; no processes stopped"]

    /// Versions before 1.2 stored the action and outcome as Vietnamese text. They are mapped to today's English
    /// values when read, so old entries display, filter and count like new ones; the file itself is never rewritten.
    /// Written as escapes so Sources/ stays free of Vietnamese text (the translations live in vi.lproj).
    static let legacyValues: [String: String] = [
        "Tho\u{E1}t": "Quit",
        "D\u{1EEB}ng": "Stop",
        "Bu\u{1ED9}c tho\u{E1}t": "Force Quit",
        "Bu\u{1ED9}c d\u{1EEB}ng": "Force stop",
        "C\u{E0}i MCP": "Install MCP",
        "G\u{1EE1} MCP": "Remove MCP",
        "Nh\u{1EA3} ch\u{1ED7} vi\u{1EC7}c n\u{1EB7}ng": "Release heavy-job slot",
        "\u{110}o sau khi d\u{1ECD}n": "Measure after cleanup",
        "\u{110}\u{E3} tho\u{E1}t": "Closed",
        "Ch\u{1B0}a tho\u{E1}t": "Still running",
        "Xong": "Done",
        "L\u{1ED7}i": "Error",
        "Kh\u{F4}ng \u{111}o \u{111}\u{1B0}\u{1EE3}c": "Could not measure",
        "\u{110}o sau 10 gi\u{E2}y": "Measured after 10 seconds",
        "Nh\u{1EA3} ch\u{1ED7} xong, kh\u{F4}ng d\u{1EEB}ng ti\u{1EBF}n tr\u{EC}nh": "Slot released; no processes stopped",
        "Ch\u{1ED7} \u{111}\u{E3} kh\u{F4}ng c\u{F2}n": "Slot no longer exists",
    ]

    static func normalized(_ e: LogEntry) -> LogEntry {
        var e = e
        e.action = legacyValues[e.action] ?? e.action
        e.outcome = legacyValues[e.outcome] ?? e.outcome
        return e
    }
}

/// Quits candidates the user has confirmed. Never called without confirmation.
enum ProcessActions {
    /// Gentle quit. Returns immediately; check the result later with `isRunning`.
    /// Every target is re-checked right before the signal: same pid and start time, same user, not protected.
    static func quitAll(_ u: QuitCandidate) {
        guard u.blockedReason == nil else { return }
        switch u.quitMethod {
        case let .app(identity, _, others):
            for i in [identity] + others where i.canStop() { NSRunningApplication(processIdentifier: i.pid)?.terminate() }
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
        case let .app(identity, _, others):
            for i in [identity] + others where i.canStop() { NSRunningApplication(processIdentifier: i.pid)?.forceTerminate() }
        case let .simulator(app):
            if let app, app.canStop() { NSRunningApplication(processIdentifier: app.pid)?.forceTerminate() }
        case let .processes(items):
            for d in items { d.send(SIGKILL) }
        }
    }

    /// Whether it is still running. For Simulator: any device still booted or the app still open.
    static func isRunning(_ u: QuitCandidate) -> Bool {
        switch u.quitMethod {
        case let .app(identity, _, others):
            return ([identity] + others).contains { $0.isSameProcess() }
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
