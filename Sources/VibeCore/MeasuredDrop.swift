import Foundation

/// RAM in use and swap in use at one moment: taken right before a cleanup and again 10 seconds after.
public struct MemoryReading: Sendable, Equatable {
    public var used: UInt64
    public var swap: UInt64
    public init(used: UInt64, swap: UInt64) { self.used = used; self.swap = swap }

    public static func now() -> MemoryReading? {
        guard let m = SystemReader.memory() else { return nil }
        return MemoryReading(used: m.used, swap: SystemReader.swap().used)
    }
}

/// What the Mac actually gave back after a cleanup, measured (not the apps' estimated footprint).
/// Positive means less in use. Other activity on the Mac in those seconds is mixed in.
public struct MeasuredDrop: Codable, Sendable, Hashable {
    public var ram: Int64
    public var swap: Int64
    public init(ram: Int64, swap: Int64) { self.ram = ram; self.swap = swap }

    public init(before: MemoryReading, after: MemoryReading) {
        ram = Int64(clamping: before.used) - Int64(clamping: after.used)
        swap = Int64(clamping: before.swap) - Int64(clamping: after.swap)
    }

    /// Seconds to wait after the apps closed before measuring again.
    public static let delay: TimeInterval = 10
}
