import Foundation

/// Names under which settings and files are stored. They are Vietnamese words written without accents, from before
/// the code moved to English; they stay exactly as they are so existing settings, kept items, alerts and logs keep
/// working after an update. Do not rename the values.
enum StoredName {
    /// UserDefaults keys.
    static let appearance = "giaoDien"         // light, dark or follow the system
    static let accent = "mauNhan"              // accent color
    static let welcomeSeen = "daChao"          // first-run welcome shown
    static let keptItems = "mucGiu"            // apps kept out of suggestions
    static let thresholds = "nguong"           // alert thresholds (JSON)
    static let menuBarStyle = "kieuThanhMenu"  // what the menu bar shows
    static let sendNotifications = "guiThongBao"
    static let settingsTab = "tabCaiDat"       // last Settings tab
    static let bubbleMode = "bubbleMode"       // floating bubble: off, whenMinimized, always
    static let bubbleSessions = "bubbleSessions" // floating bubble shows the agent session count
    static let bubbleOrigin = "bubbleOrigin"   // floating bubble position, "x,y"
    /// SwiftUI Window id of the main window (macOS saves its frame under it).
    static let mainWindow = "chinh"
    /// Files in ~/Library/Application Support/8GB Vibe.
    static let inboxFile = "thong-bao.json"
    static let logFile = "nhat-ky.jsonl"
}
