import Dispatch
import Foundation

/// Measures how late the app gets when the Mac is strained. Once a second, a timer on its own queue records
/// how late it fired (the whole process stalled: paging, CPU starvation) and posts to the main queue to measure
/// how long the main thread takes to answer (the UI stalled). Values are kept as per-minute maxima.
/// Cost: one wake-up per second, a few microseconds.
public final class ResponsivenessProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var timerLagMax: TimeInterval = 0
    private var mainLagMax: TimeInterval = 0
    private var lastMain: TimeInterval = 0
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "vn.beeca.8gbvibe.probe", qos: .userInteractive)
    private var expected: DispatchTime?
    public static let interval: TimeInterval = 1

    public init() {}

    public func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + Self.interval, repeating: Self.interval, leeway: .milliseconds(100))
        expected = .now() + Self.interval
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    public func stop() { timer?.cancel(); timer = nil }

    private func tick() {
        let now = DispatchTime.now()
        if let e = expected, now.uptimeNanoseconds > e.uptimeNanoseconds {
            record(timer: Double(now.uptimeNanoseconds - e.uptimeNanoseconds) / 1e9)
        }
        expected = now + Self.interval
        let sent = now
        DispatchQueue.main.async { [weak self] in
            self?.record(main: Double(DispatchTime.now().uptimeNanoseconds - sent.uptimeNanoseconds) / 1e9)
        }
    }

    func record(timer lag: TimeInterval? = nil, main: TimeInterval? = nil) {
        lock.lock(); defer { lock.unlock() }
        if let lag { timerLagMax = max(timerLagMax, lag) }
        if let main { mainLagMax = max(mainLagMax, main); lastMain = main }
    }

    /// The latest main-thread answer time, seconds.
    public var lastMainLag: TimeInterval { lock.lock(); defer { lock.unlock() }; return lastMain }

    /// Maxima since the last call (seconds), then resets.
    public func takeMinute() -> (timerLag: TimeInterval, mainLag: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        let r = (timerLagMax, mainLagMax)
        timerLagMax = 0; mainLagMax = 0
        return r
    }
}
