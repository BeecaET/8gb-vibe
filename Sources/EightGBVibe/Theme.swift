import AppKit
import SwiftUI

/// Light, dark or follow the system. Applied to the whole app (main window and popover) right away.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    static let key = "giaoDien"

    var name: String {
        switch self {
        case .system: return String(localized: "Theo hệ thống", bundle: .main)
        case .light: return String(localized: "Sáng", bundle: .main)
        case .dark: return String(localized: "Tối", bundle: .main)
        }
    }

    static var current: AppAppearance { AppAppearance(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system }

    /// Sets NSApp.appearance; nil means follow the system.
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

/// Accent color for buttons, switches, links and highlights. Status colors (green, yellow, red) never change,
/// so a warning always looks like a warning. The app icon stays emerald.
enum AccentChoice: String, CaseIterable, Identifiable {
    case emerald, blue, purple, orange, pink, graphite
    var id: String { rawValue }
    static let key = "mauNhan"

    var name: String {
        switch self {
        case .emerald: return String(localized: "Ngọc lục bảo", bundle: .main)
        case .blue: return String(localized: "Xanh dương", bundle: .main)
        case .purple: return String(localized: "Tím", bundle: .main)
        case .orange: return String(localized: "Cam", bundle: .main)
        case .pink: return String(localized: "Hồng", bundle: .main)
        case .graphite: return String(localized: "Than chì", bundle: .main)
        }
    }

    /// Two tones for the primary button gradient; both keep white text readable (contrast checked in light and dark).
    var tones: (Color, Color) {
        switch self {
        case .emerald: return (Color(red: 0.02, green: 0.55, blue: 0.40), Color(red: 0.08, green: 0.72, blue: 0.50))
        case .blue: return (Color(red: 0.00, green: 0.42, blue: 0.90), Color(red: 0.16, green: 0.56, blue: 1.00))
        case .purple: return (Color(red: 0.45, green: 0.27, blue: 0.86), Color(red: 0.60, green: 0.40, blue: 0.96))
        case .orange: return (Color(red: 0.85, green: 0.40, blue: 0.05), Color(red: 0.96, green: 0.55, blue: 0.15))
        case .pink: return (Color(red: 0.82, green: 0.20, blue: 0.47), Color(red: 0.94, green: 0.34, blue: 0.60))
        case .graphite: return (Color(red: 0.33, green: 0.36, blue: 0.40), Color(red: 0.47, green: 0.50, blue: 0.55))
        }
    }

    var color: Color { tones.1 }
    var gradient: LinearGradient { LinearGradient(colors: [tones.0, tones.1], startPoint: .topLeading, endPoint: .bottomTrailing) }

    static var current: AccentChoice { AccentChoice(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .emerald }
}

extension View {
    /// Applies the chosen accent to a whole view tree (tint for controls) and rebuilds it when the choice changes,
    /// so styles that read Palette.accent update immediately.
    func themed(_ accent: String) -> some View {
        let choice = AccentChoice(rawValue: accent) ?? .emerald
        return self.tint(choice.color).id(choice)
    }
}

/// Wraps a scene's root view: applies the saved appearance and accent, and updates both as soon as Settings changes them.
struct ThemedRoot<Content: View>: View {
    @AppStorage(AccentChoice.key) private var accent = AccentChoice.emerald.rawValue
    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.system.rawValue
    @ViewBuilder var content: Content

    var body: some View {
        content
            .themed(accent)
            .onAppear { (AppAppearance(rawValue: appearance) ?? .system).apply() }
            .onChange(of: appearance) { (AppAppearance(rawValue: $0) ?? .system).apply() }
    }
}
