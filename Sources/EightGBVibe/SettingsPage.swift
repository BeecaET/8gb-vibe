import AppKit
import ServiceManagement
import SwiftUI
import VibeCore

/// Settings page in the main window (sidebar, ⌘,): a standard segmented tab bar at the top
/// (General, Appearance, Notifications, Thresholds, Agent AI), one grouped form per tab. Every control saves itself.
struct SettingsPage: View {
    @EnvironmentObject var monitor: Monitor
    // Read when the page appears, not in init (the status query is an XPC call).
    @State private var launchAtLogin = false
    @State private var launchAtLoginError: String?
    @State private var language = AppLanguage.current
    @AppStorage(AccentChoice.key) private var accent = AccentChoice.emerald.rawValue
    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.system.rawValue
    @AppStorage(StoredName.settingsTab) private var tab = SettingsTab.general.rawValue
    private let launchLanguage = AppLanguage.current

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general, look, notifications, thresholds, agents
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .general: return "General"
            case .look: return "Look"
            case .notifications: return "Notifications"
            case .thresholds: return "Thresholds"
            case .agents: return "AI Agents"
            }
        }
    }

    var body: some View {
        // Same page frame as every other page (PageContainer): left-aligned, cards as wide as the window,
        // the tab bar on the content's left edge at the top, like the first row of any other page.
        PageContainer {
            Picker("", selection: $tab) {
                ForEach(SettingsTab.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel(Text("Settings group"))
            switch SettingsTab(rawValue: tab) ?? .general {
            case .general: general
            case .look: look; menuBar
            case .notifications: notifications
            case .thresholds:
                thresholds
                SettingsSection {
                    HStack {
                        Text("Restore the default thresholds for this Mac.").foregroundStyle(.secondary)
                        Spacer()
                        Button("Restore Defaults") { monitor.thresholds = monitor.profile.thresholds }
                    }
                }
            case .agents: AgentAccessSettings()
            }
        }
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    // MARK: Sections

    /// Appearance and accent color; both apply immediately, no relaunch.
    private var look: some View {
        SettingsSection("Look") {
            PickerRow(selection: $appearance) {
                ForEach(AppAppearance.allCases) { Text($0.name).tag($0.rawValue) }
            } label: {
                FormLabel("Appearance", "Applies to the main window and the menu bar panel")
            }
            .pickerStyle(.segmented)
            LabeledRow {
                HStack(spacing: 10) {
                    ForEach(AccentChoice.allCases) { c in
                        Button { accent = c.rawValue } label: {
                            Circle().fill(c.color).frame(width: 20, height: 20)
                                .overlay {
                                    if accent == c.rawValue {
                                        Image(systemName: "checkmark").font(.callout.weight(.bold)).foregroundStyle(.white)
                                    }
                                }
                                .overlay(Circle().stroke(Color.primary.opacity(accent == c.rawValue ? 0.45 : 0), lineWidth: 2).padding(-3))
                        }
                        .buttonStyle(.plain)
                        .help(c.name)
                        .accessibilityLabel(Text(c.name))
                        .accessibilityAddTraits(accent == c.rawValue ? .isSelected : [])
                    }
                }
            } label: {
                FormLabel("Accent color", "Buttons, switches, links. Green, yellow and red status colors stay the same.")
            }
        }
    }

    private var general: some View {
        SettingsSection("General") {
            PickerRow(selection: $language) {
                ForEach(AppLanguage.allCases) { n in n.label.tag(n) }
            } label: {
                FormLabel("Language", "Follows the system language by default")
            }
            .onChange(of: language) { $0.save() }
            if language != launchLanguage {
                LabeledRow {
                    Button("Relaunch") { AppLanguage.relaunch() }.buttonStyle(.borderedProminent)
                } label: {
                    Text("Relaunch the app to change the language.").foregroundStyle(.secondary)
                }
            }
            ToggleRow(isOn: $launchAtLogin) {
                FormLabel("Open at login", "Opens the app when you log in to macOS")
            }
            .onChange(of: launchAtLogin) { enabled in toggleLaunchAtLogin(enabled) }
            if let launchAtLoginError {
                Text(launchAtLoginError).foregroundStyle(.red)
            }
        }
    }

    private var menuBar: some View {
        SettingsSection {
            HStack(spacing: 10) {
                ForEach([MenuBarStyle.ringOnly, .ringAndSwap, .ringAndRAM]) { style in
                    menuBarOption(style)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Menu bar")
        } footer: {
            Text("Choose what the menu bar shows.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var notifications: some View {
        SettingsSection("Notifications") {
            ToggleRow(isOn: $monitor.sendNotifications) {
                FormLabel("Notify when over threshold", "At most once per 30 minutes per metric, only when the level rises.")
            }
        }
    }

    private var thresholds: some View {
        let h = monitor.system
        return SettingsSection {
            ThresholdScale(title: "Swap", unit: "GB", higherIsWorse: true, maximum: 16,
                           current: h.map { Double($0.swap.used) / Format.GB },
                           yellow: $monitor.thresholds.swapYellowGB, red: $monitor.thresholds.swapRedGB, step: 1)
            ThresholdScale(title: "Free disk", unit: "GB", higherIsWorse: false, maximum: 200,
                           current: h.map { Double($0.disk.free) / Format.GB },
                           yellow: $monitor.thresholds.diskFreeYellowGB, red: $monitor.thresholds.diskFreeRedGB, step: 5)
            ThresholdScale(title: "5-minute CPU load", unit: "", higherIsWorse: true, maximum: 48,
                           current: h.map { $0.load.m5 },
                           yellow: $monitor.thresholds.load5Yellow, red: $monitor.thresholds.load5Red, step: 2,
                           note: String(localized: "This Mac has \(h?.coreCount ?? 8) cores. This is average load, not CPU percentage.", bundle: .main))
            ThresholdScale(title: "Claude Code sessions", unit: "", higherIsWorse: true, maximum: 30,
                           current: Double(monitor.processes.sessions.count),
                           yellow: Binding(get: { Double(monitor.thresholds.sessionsYellow) }, set: { monitor.thresholds.sessionsYellow = Int($0) }),
                           red: Binding(get: { Double(monitor.thresholds.sessionsRed) }, set: { monitor.thresholds.sessionsRed = Int($0) }),
                           step: 1)
            LabeledRow {
                HStack(spacing: 6) {
                    Text("\(Format.number(monitor.thresholds.idleMinutes, digits: 0)) min").monospacedDigit()
                    Stepper("", value: $monitor.thresholds.idleMinutes, in: 5...240, step: 5).labelsHidden()
                }
            } label: {
                FormLabel("Idle after", "Apps with low CPU use that stay in the background this long are suggested for quitting. Agent sessions are only suggested for review.")
            }
        } header: {
            Text("Alert thresholds")
        } footer: {
            Text("The bold mark is where this Mac is now. Adjust the yellow and red levels with the buttons on the right.").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One menu bar style as a selectable preview of what the menu bar will show.
    private func menuBarOption(_ style: MenuBarStyle) -> some View {
        let selected = monitor.menuBarStyle == style
        let h = monitor.system
        let img = MenuBarIcon.ring(ratio: h?.memory.usedRatio ?? 0.7, color: monitor.overallLevel.nsColor)
        return Button { monitor.menuBarStyle = style } label: {
            VStack(spacing: 10) {
                HStack(spacing: 4) {
                    Image(nsImage: img)
                    switch style {
                    case .ringOnly: EmptyView()
                    case .ringAndSwap: Text(h.map { Format.bytes($0.swap.used) } ?? "8,8 GB")
                    case .ringAndRAM: Text(h.map { Format.percent($0.memory.usedRatio) } ?? "82 %")
                    }
                }
                .font(.body.weight(.medium)).monospacedDigit()
                .padding(.horizontal, 12).frame(height: 26)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                Text(style.name).font(.callout).foregroundStyle(selected ? Color.primary : Color.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? Palette.tint.opacity(0.12) : Color.primary.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(selected ? Palette.tint : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(style.name))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = String(localized: "Could not change: \(error.localizedDescription)", bundle: .main)
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: Building blocks

/// A titled group like the cards on other pages: headline title, rows in a card, optional footnote.
/// Same call shape as SwiftUI's Section, so settings code reads the same.
struct SettingsSection<Content: View, Header: View, Footer: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var header: Header
    @ViewBuilder var footer: Footer

    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header, @ViewBuilder footer: () -> Footer) {
        self.content = content(); self.header = header(); self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header.font(.headline)
            VStack(alignment: .leading, spacing: 14) { content }
                .card()
            footer.font(.callout).foregroundStyle(.secondary)
        }
    }
}

extension SettingsSection where Footer == EmptyView {
    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) {
        self.init(content: content, header: header, footer: { EmptyView() })
    }
}

extension SettingsSection where Header == Text, Footer == EmptyView {
    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(content: content, header: { Text(title) }, footer: { EmptyView() })
    }
}

extension SettingsSection where Header == EmptyView, Footer == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.init(content: content, header: { EmptyView() }, footer: { EmptyView() })
    }
}

/// Label on the left (title and one line of explanation), control on the right.
struct LabeledRow<Content: View, Label: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var label: Label
    init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) { self.content = content(); self.label = label() }
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            label
            Spacer(minLength: 12)
            content
        }
    }
}

/// A picker as a settings row; .pickerStyle on the row reaches the picker.
struct PickerRow<Value: Hashable, Options: View, Label: View>: View {
    var selection: Binding<Value>
    @ViewBuilder var options: Options
    @ViewBuilder var label: Label
    init(selection: Binding<Value>, @ViewBuilder content: () -> Options, @ViewBuilder label: () -> Label) {
        self.selection = selection; self.options = content(); self.label = label()
    }
    var body: some View {
        LabeledRow { Picker("", selection: selection) { options }.labelsHidden().fixedSize() } label: { label }
    }
}

/// A switch as a settings row.
struct ToggleRow<Label: View>: View {
    var isOn: Binding<Bool>
    @ViewBuilder var label: Label
    init(isOn: Binding<Bool>, @ViewBuilder label: () -> Label) { self.isOn = isOn; self.label = label() }
    var body: some View {
        LabeledRow { Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch) } label: { label }
    }
}

/// Two-line form label: the setting's name and one line of explanation in secondary text (11 pt, never smaller).
struct FormLabel: View {
    var title: LocalizedStringKey
    var detail: LocalizedStringKey?
    init(_ title: LocalizedStringKey, _ detail: LocalizedStringKey? = nil) { self.title = title; self.detail = detail }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let detail { Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

/// A threshold as a scale: green, yellow and red zones, a marker for the Mac's current value,
/// and compact steppers for the yellow and red levels. Works for "higher is worse" (swap, load)
/// and "lower is worse" (free disk).
struct ThresholdScale: View {
    var title: LocalizedStringKey
    var unit: String
    var higherIsWorse: Bool
    var maximum: Double
    var current: Double?
    @Binding var yellow: Double
    @Binding var red: Double
    var step: Double
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                if let current {
                    Text("Now \(value(current))").font(.callout).foregroundStyle(levelColor(current)).monospacedDigit()
                }
                Spacer()
                levelStepper(color: .yellow, binding: $yellow)
                levelStepper(color: .red, binding: $red)
            }
            GeometryReader { geo in
                let w = geo.size.width
                let y = position(yellow) * w, r = position(red) * w
                ZStack(alignment: .leading) {
                    // Zones, drawn in scale order.
                    HStack(spacing: 2) {
                        if higherIsWorse {
                            zone(.green, width: y); zone(.yellow, width: max(0, r - y)); zone(.red, width: max(0, w - r))
                        } else {
                            zone(.red, width: r); zone(.yellow, width: max(0, y - r)); zone(.green, width: max(0, w - y))
                        }
                    }
                    if let current {
                        let x = position(current) * w
                        Capsule().fill(Color.primary).frame(width: 3, height: 16).offset(x: min(max(0, x - 1.5), w - 3))
                            .shadow(color: .black.opacity(0.3), radius: 1)
                    }
                }
                .frame(height: 16)
                .animation(.easeOut(duration: 0.2), value: yellow)
                .animation(.easeOut(duration: 0.2), value: red)
            }
            .frame(height: 16)
            if let note { Text(note).font(.callout).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 6)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }

    private func zone(_ c: Color, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(c.opacity(0.55)).frame(width: max(0, width), height: 8)
    }

    private func position(_ v: Double) -> CGFloat { CGFloat(min(max(v / maximum, 0), 1)) }

    private func value(_ v: Double) -> String {
        let n = Format.number(v, digits: v < 10 && v != v.rounded() ? 1 : 0)
        return unit.isEmpty ? n : "\(n) \(unit)"
    }

    private func levelColor(_ v: Double) -> Color {
        if higherIsWorse { return v >= red ? .red : (v >= yellow ? .orange : .green) }
        return v <= red ? .red : (v <= yellow ? .orange : .green)
    }

    private func levelStepper(color: Color, binding: Binding<Double>) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(value(binding.wrappedValue)).monospacedDigit().frame(minWidth: 44, alignment: .trailing)
            Stepper("", value: binding, in: step...maximum, step: step).labelsHidden()
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(color == .red ? Text("Red level") : Text("Yellow level"))
        .accessibilityValue(value(binding.wrappedValue))
    }
}
