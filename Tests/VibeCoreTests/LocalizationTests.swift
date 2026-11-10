import Foundation
import XCTest

/// Code is English; Vietnamese lives only in Resources/vi.lproj. These checks read the files directly.
/// (scripts/check-l10n.sh also checks that every key the compiler extracts has a Vietnamese entry.)
final class LocalizationTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Letters only Vietnamese uses (accented vowels and d with stroke).
    static let vietnamese = try! NSRegularExpression(pattern: "[àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ]",
                                                      options: [.caseInsensitive])

    func testNoVietnameseTextInSources() throws {
        let sources = Self.root.appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        var hits: [String] = []
        for f in files {
            let text = try String(contentsOf: f, encoding: .utf8)
            for (n, line) in text.components(separatedBy: "\n").enumerated()
            where Self.vietnamese.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                hits.append("\(f.lastPathComponent):\(n + 1)")
            }
        }
        XCTAssertEqual(hits, [], "Vietnamese text belongs in Resources/vi.lproj, not in Sources/")
    }

    func testVietnameseStringsMatchTheirKeys() throws {
        let url = Self.root.appendingPathComponent("Resources/vi.lproj/Localizable.strings")
        let vi = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String], "vi.lproj must parse")
        XCTAssertGreaterThan(vi.count, 500)
        let spec = try NSRegularExpression(pattern: "%(?:\\d+\\$)?(lld|llu|ld|lu|d|u|lf|f|@)")
        func types(_ s: String) -> [String] {
            spec.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { String(s[Range($0.range(at: 1), in: s)!]) }.sorted()
        }
        for (k, v) in vi { XCTAssertEqual(types(k), types(v), "format specifiers differ for \"\(k)\"") }
        // A few values stored or shown everywhere.
        XCTAssertEqual(vi["Quit"], "Thoát")
        XCTAssertEqual(vi["Closed"], "Đã thoát")
        XCTAssertEqual(vi["Overview"], "Tổng quan")
        XCTAssertEqual(vi["%lld min"], "%lld phút")
    }

    func testEnglishIsTheDevelopmentRegion() throws {
        let script = try String(contentsOf: Self.root.appendingPathComponent("scripts/common.sh"), encoding: .utf8)
        XCTAssertTrue(script.contains("<key>CFBundleDevelopmentRegion</key><string>en</string>"))
    }
}
