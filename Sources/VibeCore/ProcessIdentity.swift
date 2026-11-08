import Darwin
import Foundation

/// Identity of a process: pid plus start time (to the microsecond).
/// A pid can be reused after a process exits, so the start time must also match before sending a signal.
public struct ProcessIdentity: Sendable, Hashable {
    public var pid: Int32
    public var seconds: Int64
    public var microseconds: Int64

    public init(pid: Int32, seconds: Int64, microseconds: Int64) {
        self.pid = pid; self.seconds = seconds; self.microseconds = microseconds
    }

    public init(_ t: ProcessRecord) {
        self.init(pid: t.pid, startDate: t.startDate)
    }

    public init(pid: Int32, startDate: Date) {
        let s = startDate.timeIntervalSince1970
        self.pid = pid
        seconds = Int64(s.rounded(.down))
        microseconds = Int64(((s - s.rounded(.down)) * 1_000_000).rounded())
    }

    /// Reads the current identity of a pid. nil if that process no longer exists.
    public static func read(pid: Int32) -> (ProcessIdentity, uid: UInt32)? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard pid > 0, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return (ProcessIdentity(pid: pid, seconds: Int64(info.pbi_start_tvsec), microseconds: Int64(info.pbi_start_tvusec)), info.pbi_uid)
    }

    /// Same process as when read, still alive and owned by this user. Only send a signal when this returns true.
    public func isSameProcess(uid: UInt32 = getuid()) -> Bool {
        guard pid > 1, let (current, u) = ProcessIdentity.read(pid: pid), u == uid else { return false }
        // Allow 1 microsecond of drift from floating point rounding through Date.
        return current.seconds == seconds && abs(current.microseconds - microseconds) <= 1
    }

    /// Whether this exact process may be stopped now: same process, owned by this user, not protected by `ProcessGuard`.
    public func canStop(uid: UInt32 = getuid(), selfPID: Int32 = getpid()) -> Bool {
        isSameProcess(uid: uid) && ProcessGuard.currentReason(pid: pid, selfIdentifier: selfPID) == nil
    }

    /// Sends a signal only when `canStop` holds right now. Every stop in the app goes through here.
    @discardableResult
    public func send(_ signal: Int32, uid: UInt32 = getuid(), selfPID: Int32 = getpid()) -> Bool {
        guard canStop(uid: uid, selfPID: selfPID) else { return false }
        return kill(pid, signal) == 0
    }
}
