import AppKit
import SwiftUI
import VibeCore

/// Small key cap, e.g. "⌘K", shown next to actions so shortcuts are discoverable.
struct KeyHint: View {
    var keys: String
    init(_ keys: String) { self.keys = keys }
    var body: some View {
        Text(verbatim: keys)
            .font(.callout.monospaced().weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.10)))
            .accessibilityHidden(true)
    }
}

/// One command: go to a page or run a safe action. Nothing here quits anything directly;
/// quitting always goes through Free RAM and its confirmation sheet.
struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let keys: String?
    let run: () -> Void
}

/// Cmd-K: type to find a page or an action, arrow keys to move, Return to run, Esc to close.
struct CommandPalette: View {
    @EnvironmentObject var monitor: Monitor
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    private var commands: [PaletteCommand] {
        var list: [PaletteCommand] = []
        let a = monitor.advice
        if let title = a.actionTitle {
            list.append(PaletteCommand(id: "advice", title: title, subtitle: a.headline, symbol: "bolt.fill", keys: nil) {
                monitor.perform(a.action)
            })
        }
        // Pages in shortcut order (Cmd-1 first), About last.
        // Cmd-0 (Notifications) sits after Cmd-9; pages without a number go last.
        func order(_ p: Page) -> Int { p.shortcut.flatMap { $0.wholeNumberValue }.map { $0 == 0 ? 10 : $0 } ?? 99 }
        let pages = Page.allCases.sorted { order($0) < order($1) }
        for p in pages {
            list.append(PaletteCommand(id: "page-\(p.rawValue)", title: String(localized: "Go to \(p.name)", bundle: .main),
                                       subtitle: String(localized: "Page", bundle: .main), symbol: p.symbol,
                                       keys: p.shortcut.map { "⌘\($0)" }) { monitor.page = p })
        }
        list.append(PaletteCommand(id: "claude", title: String(localized: "Review sessions", bundle: .main),
                                   subtitle: String(localized: "\(monitor.processes.sessions.count) Claude Code sessions open", bundle: .main),
                                   symbol: "list.bullet", keys: nil) { monitor.page = .agents })
        list.append(PaletteCommand(id: "scan", title: String(localized: "Rescan disk", bundle: .main),
                                   subtitle: String(localized: "Measure caches and app data", bundle: .main), symbol: "internaldrive", keys: nil) {
            monitor.page = .disk; monitor.scanDisk()
        })
        list.append(PaletteCommand(id: "log", title: String(localized: "Show log file in Finder", bundle: .main),
                                   subtitle: String(localized: "Every app quit is recorded", bundle: .main), symbol: "folder", keys: nil) {
            NSWorkspace.shared.activateFileViewerSelecting([ActionLog.file])
        })
        guard !query.isEmpty else { return list }
        let q = Self.fold(query)
        return list.filter { Self.fold($0.title + " " + $0.subtitle).contains(q) }
    }

    /// Case- and accent-insensitive text, so "don ram" finds the Vietnamese "Free RAM" title (accents and the
    /// letter d-with-stroke folded away).
    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).replacingOccurrences(of: "\u{0111}", with: "d")
    }

    var body: some View {
        let items = commands
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find a page or command", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit { run(items) }
                    .onChange(of: query) { _ in selected = 0 }
                KeyHint("esc")
            }
            .padding(14)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, c in
                            row(c, isSelected: i == selected)
                                .id(i)
                                .onTapGesture { selected = i; run(items) }
                        }
                        if items.isEmpty {
                            Text("No matching command").foregroundStyle(.secondary).padding(20)
                        }
                    }
                    .padding(6)
                }
                .frame(height: 320)
                .onChange(of: selected) { i in proxy.scrollTo(i) }
            }
            Divider()
            HStack(spacing: 14) {
                Label("select", systemImage: "arrow.up.arrow.down")
                Label("run", systemImage: "return")
                Spacer()
                Text("Quitting an app always asks first").foregroundStyle(.secondary)
            }
            .font(.callout).foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
        .frame(width: 560)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))  // opaque: a translucent panel let the page show through in light mode
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.3), radius: 30, y: 12)
        .arrowKeys(up: { selected = max(0, selected - 1) }, down: { selected = min(max(0, items.count - 1), selected + 1) })
        .onExitCommand { monitor.showPalette = false }
        .onAppear { query = ""; selected = 0; focused = true }
    }

    private func row(_ c: PaletteCommand, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: c.symbol).frame(width: 22).foregroundStyle(isSelected ? Color.white : Palette.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(c.title).foregroundStyle(isSelected ? Color.white : Color.primary)
                Text(c.subtitle).font(.callout).foregroundStyle(isSelected ? Color.white : Color.secondary).lineLimit(1)
            }
            Spacer()
            if let k = c.keys { KeyHint(k) }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(isSelected ? Palette.tint : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    private func run(_ items: [PaletteCommand]) {
        guard items.indices.contains(selected) else { return }
        let c = items[selected]
        monitor.showPalette = false
        c.run()
    }
}

extension View {
    /// Up and down arrows move the palette selection (macOS 14 key handling; on macOS 13 use the mouse or type to filter).
    @ViewBuilder func arrowKeys(up: @escaping () -> Void, down: @escaping () -> Void) -> some View {
        if #available(macOS 14.0, *) {
            self.onKeyPress(.upArrow) { up(); return .handled }
                .onKeyPress(.downArrow) { down(); return .handled }
        } else {
            self
        }
    }
}
