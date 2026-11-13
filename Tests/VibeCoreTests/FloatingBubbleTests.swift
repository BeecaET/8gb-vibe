import CoreGraphics
import XCTest
@testable import VibeCore

final class FloatingBubbleTests: XCTestCase {
    private func state(open: Bool = false, minimized: Bool = false, hidden: Bool = false) -> BubbleWindowState {
        BubbleWindowState(mainWindowOnScreen: open, mainWindowMinimized: minimized, hiddenByUser: hidden)
    }

    func testOffNeverShows() {
        for s in [state(), state(minimized: true), state(open: true)] {
            XCTAssertFalse(BubbleRules.shouldShow(.off, s))
        }
    }

    func testWhenMinimized() {
        XCTAssertTrue(BubbleRules.shouldShow(.whenMinimized, state(minimized: true)))
        XCTAssertFalse(BubbleRules.shouldShow(.whenMinimized, state()))  // window closed, not minimized
        XCTAssertFalse(BubbleRules.shouldShow(.whenMinimized, state(open: true)))
        XCTAssertFalse(BubbleRules.shouldShow(.whenMinimized, state(minimized: true, hidden: true)))
    }

    func testAlways() {
        XCTAssertTrue(BubbleRules.shouldShow(.always, state()))
        XCTAssertTrue(BubbleRules.shouldShow(.always, state(minimized: true)))
        XCTAssertFalse(BubbleRules.shouldShow(.always, state(open: true)), "the open main window hides the bubble")
        XCTAssertFalse(BubbleRules.shouldShow(.always, state(hidden: true)))
    }

    func testModeRawValuesAreStable() {
        XCTAssertEqual(BubbleMode.allCases.map(\.rawValue), ["off", "whenMinimized", "always"])
    }

    func testReadingFormat() {
        let r = BubbleReading(score: 72, usedRatio: 0.823, swapUsed: UInt64(2.1 * Format.GB), swapIOBytesPerSecond: 0, sessions: nil)
        XCTAssertEqual(r.ram, "82 %")
        XCTAssertEqual(r.swap, "2,1 GB")
        XCTAssertNil(r.swapRate)
        XCTAssertNil(r.sessions)
        XCTAssertEqual(r.tone, .heavy)
    }

    func testSwapRateOnlyWhenHeavy() {
        let below = BubbleReading(score: 90, usedRatio: 0.5, swapUsed: 0, swapIOBytesPerSecond: HealthScore.swapIOStart / 2, sessions: 3)
        XCTAssertNil(below.swapRate)
        XCTAssertEqual(below.sessions, 3)
        let heavy = BubbleReading(score: 30, usedRatio: 0.95, swapUsed: 0, swapIOBytesPerSecond: 2 * Format.MB, sessions: nil)
        XCTAssertEqual(heavy.swapRate, "120 MB/min")
        XCTAssertNil(BubbleReading(score: 30, usedRatio: 0.95, swapUsed: 0, swapIOBytesPerSecond: nil, sessions: nil).swapRate)
    }

    func testEqualReadingsDoNotRedraw() {
        let a = BubbleReading(score: 72, usedRatio: 0.821, swapUsed: 100 << 20, swapIOBytesPerSecond: 0, sessions: 2)
        let b = BubbleReading(score: 72, usedRatio: 0.822, swapUsed: 100 << 20, swapIOBytesPerSecond: 1, sessions: 2)
        XCTAssertEqual(a, b, "values that format the same are the same reading")
    }

    func testToneBands() {
        XCTAssertEqual(BubbleReading.tone(100), .smooth)
        XCTAssertEqual(BubbleReading.tone(85), .smooth)
        XCTAssertEqual(BubbleReading.tone(84), .heavy)
        XCTAssertEqual(BubbleReading.tone(64), .slow)
        XCTAssertEqual(BubbleReading.tone(39), .overloaded)
    }

    func testPlacementCoding() {
        XCTAssertEqual(BubblePlacement.encode(CGPoint(x: 100.4, y: -20.6)), "100,-21")
        XCTAssertEqual(BubblePlacement.decode("100,-21"), CGPoint(x: 100, y: -21))
        XCTAssertNil(BubblePlacement.decode(nil))
        XCTAssertNil(BubblePlacement.decode("abc"))
        XCTAssertNil(BubblePlacement.decode("1,2,3"))
    }

    func testPlacement() {
        let main = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let right = CGRect(x: 1440, y: 0, width: 1920, height: 1055)
        let size = CGSize(width: 180, height: 48)
        // No saved spot: top-right of the first screen.
        XCTAssertEqual(BubblePlacement.origin(saved: nil, size: size, screens: [main]), CGPoint(x: 1244, y: 811))
        // Saved spot fully on a screen: kept.
        XCTAssertEqual(BubblePlacement.origin(saved: CGPoint(x: 2000, y: 500), size: size, screens: [main, right]), CGPoint(x: 2000, y: 500))
        // Hanging over the right edge: moved back inside.
        XCTAssertEqual(BubblePlacement.origin(saved: CGPoint(x: 1400, y: 500), size: size, screens: [main]), CGPoint(x: 1260, y: 500))
        // Its screen was unplugged: back to the default spot.
        XCTAssertEqual(BubblePlacement.origin(saved: CGPoint(x: 2000, y: 500), size: size, screens: [main]), CGPoint(x: 1244, y: 811))
    }
}
