import Foundation

/// Compares the RAM the groups need with the Mac's RAM.
public struct RAMBudget: Sendable {
    public var totalRAM: UInt64
    public var wired: UInt64
    public var groups: [(group: WorkCategory, footprint: UInt64)]

    /// Estimate: total readable footprint plus wired. System processes running as root cannot be read, so they are not counted.
    public var demand: UInt64 { groups.reduce(wired) { $0 + $1.footprint } }
    public var overflow: UInt64 { demand > totalRAM ? demand - totalRAM : 0 }

    public init(memory: Memory, snapshot: ProcessSnapshot) {
        totalRAM = memory.total
        wired = memory.wired
        groups = snapshot.groups.filter { $0.footprint > 0 }.map { ($0.group, $0.footprint) }
    }
}
