import Foundation

/// Formats numbers the Vietnamese way: decimal comma, GB/MB units (base 1024).
public enum Format {
    public static let GB: Double = 1024 * 1024 * 1024
    public static let MB: Double = 1024 * 1024

    /// Examples: 8,8 GB, 512 MB, 0 MB.
    public static func bytes(_ bytes: UInt64, digits: Int = 1) -> String {
        let b = Double(bytes)
        if b >= GB {
            return number(b / GB, digits: digits) + " GB"
        }
        return number(b / MB, digits: 0) + " MB"
    }

    /// Only the GB number, no unit. Example: 8,8
    public static func gbCount(_ bytes: UInt64, digits: Int = 1) -> String {
        number(Double(bytes) / GB, digits: digits)
    }

    public static func number(_ x: Double, digits: Int) -> String {
        let f = formatter(digits)
        return f.string(from: NSNumber(value: x)) ?? String(format: "%.\(digits)f", x)
    }

    /// The app is showing English (the localization macOS picked for the .app). English uses a decimal point: 8.8 GB.
    /// Only applies when the running bundle is this app (it has a vi localization), so tests and other tools always use the Vietnamese format.
    public static let isEnglish = Bundle.main.localizations.contains("vi")
        && Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true

    /// Creating a NumberFormatter is expensive, so keep one per number of decimal digits.
    private static let key = NSLock()
    private static var formatterCache: [Int: NumberFormatter] = [:]
    private static func formatter(_ digits: Int) -> NumberFormatter {
        key.lock(); defer { key.unlock() }
        if let f = formatterCache[digits] { return f }
        let f = NumberFormatter()
        f.locale = Locale(identifier: isEnglish ? "en_US" : "vi_VN")
        f.numberStyle = .decimal
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        f.usesGroupingSeparator = true
        formatterCache[digits] = f
        return f
    }

    /// Vietnamese writes "82 %", English writes "82%".
    public static var percentSign: String { isEnglish ? "%" : " %" }

    public static func percent(_ ratio: Double) -> String {
        number(ratio * 100, digits: 0) + percentSign
    }

    /// Examples: 45 giây, 12 phút, 3 giờ, 1 ngày 18 giờ.
    public static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return String(localized: "\(s) giây", bundle: .main) }
        let minutes = s / 60
        if minutes < 60 { return String(localized: "\(minutes) phút", bundle: .main) }
        let hours = minutes / 60
        if hours < 24 { return String(localized: "\(hours) giờ", bundle: .main) }
        let days = hours / 24
        let remainder = hours % 24
        return remainder == 0 ? String(localized: "\(days) ngày", bundle: .main) : String(localized: "\(days) ngày \(remainder) giờ", bundle: .main)
    }
}
