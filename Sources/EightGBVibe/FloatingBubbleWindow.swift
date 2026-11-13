import AppKit
import Combine
import SwiftUI
import VibeCore

/// Floating status bubble: a small borderless panel above other windows, shown when the main window is minimized
/// (or always, by choice) and hidden while the main window is open. It reuses the Monitor's samples (no extra
/// measuring) and only redraws when a shown value changes. Click: opens the main window. Right click: Hide / Turn Off.
@MainActor
final class FloatingBubble {
    static let shared = FloatingBubble()
    /// Posted to open the main window (handled by the menu bar label, which has `openWindow`).
    static let openMainWindow = Notification.Name("vn.beeca.8gbvibe.openMainWindow")

    static var mode: BubbleMode {
        get { BubbleMode(rawValue: UserDefaults.standard.string(forKey: StoredName.bubbleMode) ?? "") ?? .off }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: StoredName.bubbleMode) }
    }
    static var showsSessions: Bool { UserDefaults.standard.bool(forKey: StoredName.bubbleSessions) }

    private weak var monitor: Monitor?
    private let model = BubbleModel()
    private var panel: NSPanel?
    private var hiddenByUser = false
    private var samples: AnyCancellable?

    func attach(_ monitor: Monitor) {
        guard self.monitor == nil else { return }
        self.monitor = monitor
        let nc = NotificationCenter.default
        let names = [NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                     NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification]
        for name in names {
            nc.addObserver(forName: name, object: nil, queue: .main) { n in
                guard let w = n.object as? NSWindow, DockIcon.isMainWindow(w) else { return }
                MainActor.assumeIsolated { FloatingBubble.shared.refresh() }
            }
        }
        nc.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { n in
            guard let w = n.object as? NSWindow, DockIcon.isMainWindow(w) else { return }
            MainActor.assumeIsolated { FloatingBubble.shared.refresh(closing: w) }
        }
        // Screens added, removed or rearranged: keep the bubble on one.
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { FloatingBubble.shared.placePanel() }
        }
        refresh()
    }

    /// Shows or hides the bubble for the current setting and main window state.
    func refresh(closing: NSWindow? = nil) {
        let mains = NSApp.windows.filter { $0 !== closing && DockIcon.isMainWindow($0) }
        let onScreen = mains.contains { $0.isVisible && !$0.isMiniaturized }
        if onScreen { hiddenByUser = false }  // "Hide" lasts until the main window is opened again
        let state = BubbleWindowState(mainWindowOnScreen: onScreen,
                                      mainWindowMinimized: mains.contains { $0.isMiniaturized },
                                      hiddenByUser: hiddenByUser)
        BubbleRules.shouldShow(Self.mode, state) ? show() : hide()
    }

    private func show() {
        guard let monitor else { return }
        updateReading()
        if samples == nil {
            // Subscribe only while the bubble shows: one cheap comparison per system sample (every 5 s).
            samples = monitor.$system.dropFirst().receive(on: RunLoop.main).sink { _ in
                MainActor.assumeIsolated { FloatingBubble.shared.updateReading() }
            }
        }
        let p = panel ?? makePanel()
        panel = p
        if !p.isVisible {
            placePanel()
            p.orderFrontRegardless()
        }
    }

    private func hide() {
        samples = nil
        panel?.orderOut(nil)
    }

    private func updateReading() {
        guard let monitor, let h = monitor.system else { return }
        let sessions = Self.showsSessions ? monitor.processes.sessions.count + monitor.processes.agentSessions.count : nil
        let r = BubbleReading(score: monitor.score, usedRatio: h.memory.usedRatio, swapUsed: h.swap.used,
                              swapIOBytesPerSecond: monitor.recorder.lastRates?.swapIOBytes, sessions: sessions)
        guard r != model.reading else { return }
        model.reading = r
        guard let p = panel, let content = p.contentView as? BubbleContainerView else { return }
        content.describe(r)
        // The width changes when the swap rate or session count appears: keep the right edge where it was.
        // SwiftUI lays out the new values on the next pass, so measure after it.
        DispatchQueue.main.async {
            let size = content.hosting.fittingSize
            guard size != p.frame.size else { return }
            var f = p.frame
            f.origin.x += f.width - size.width
            f.origin.y += f.height - size.height
            f.size = size
            p.setFrame(f, display: true)
        }
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.animationBehavior = .none
        // Every Space, but not full screen Spaces (no .fullScreenAuxiliary): hidden while an app is full screen.
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let root = ThemedRoot { BubbleView().environmentObject(model) }
        let container = BubbleContainerView(hosting: NSHostingView(rootView: AnyView(root)))
        container.onClick = { FloatingBubble.shared.openMain() }
        container.onMoved = { FloatingBubble.shared.saveOrigin() }
        container.menu = contextMenu()
        if let r = model.reading { container.describe(r) }
        p.contentView = container
        p.setContentSize(container.hosting.fittingSize)
        return p
    }

    private func contextMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(MenuAction(String(localized: "Open \(Product.name)", bundle: .main)) { FloatingBubble.shared.openMain() })
        m.addItem(.separator())
        m.addItem(MenuAction(String(localized: "Hide", bundle: .main)) {
            FloatingBubble.shared.hiddenByUser = true
            FloatingBubble.shared.hide()
        })
        m.addItem(MenuAction(String(localized: "Turn Off Bubble", bundle: .main)) {
            FloatingBubble.mode = .off
            FloatingBubble.shared.hide()
        })
        return m
    }

    func placePanel() {
        guard let p = panel else { return }
        let saved = BubblePlacement.decode(UserDefaults.standard.string(forKey: StoredName.bubbleOrigin))
        let screens = NSScreen.screens.map(\.visibleFrame)
        p.setFrameOrigin(BubblePlacement.origin(saved: saved, size: p.frame.size, screens: screens))
    }

    private func saveOrigin() {
        guard let p = panel else { return }
        placePanel(at: p.frame.origin)
    }

    /// Saves a dragged position, moved fully onto a screen.
    private func placePanel(at origin: CGPoint) {
        guard let p = panel else { return }
        let fixed = BubblePlacement.origin(saved: origin, size: p.frame.size, screens: NSScreen.screens.map(\.visibleFrame))
        UserDefaults.standard.set(BubblePlacement.encode(fixed), forKey: StoredName.bubbleOrigin)
        if fixed != origin { p.setFrameOrigin(fixed) }
    }

    /// Opens (or brings back) the main window; the bubble hides once it is on screen.
    func openMain() {
        if let w = NSApp.windows.first(where: DockIcon.isMainWindow) {
            if w.isMiniaturized { w.deminiaturize(nil) }
            w.makeKeyAndOrderFront(nil)
        } else {
            NotificationCenter.default.post(name: Self.openMainWindow, object: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        hide()
    }
}

/// The reading the bubble view shows. Only assigned when it changed.
final class BubbleModel: ObservableObject {
    @Published var reading: BubbleReading?
}

/// Takes every mouse event for the bubble: a click opens the main window, a drag moves the bubble,
/// a right click shows its menu. The SwiftUI view inside only draws.
final class BubbleContainerView: NSView {
    let hosting: NSHostingView<AnyView>
    var onClick: () -> Void = {}
    var onMoved: () -> Void = {}

    init(hosting: NSHostingView<AnyView>) {
        self.hosting = hosting
        super.init(frame: NSRect(origin: .zero, size: hosting.fittingSize))
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = bounds
        addSubview(hosting)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let start = NSEvent.mouseLocation
        let origin = window.frame.origin
        var dragged = false
        // Track until the button is released: moving more than 3 points is a drag, otherwise a click.
        while let e = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let now = NSEvent.mouseLocation
            if e.type == .leftMouseUp { break }
            if !dragged, hypot(now.x - start.x, now.y - start.y) > 3 { dragged = true }
            if dragged { window.setFrameOrigin(NSPoint(x: origin.x + now.x - start.x, y: origin.y + now.y - start.y)) }
        }
        dragged ? onMoved() : onClick()
    }

    /// Tooltip and VoiceOver: one button that says how the Mac is doing and opens the main window.
    func describe(_ r: BubbleReading) {
        let summary = HealthScore.summary(r.score)
        toolTip = summary
        setAccessibilityLabel(String(localized: "\(summary). RAM \(r.ram), swap \(r.swap).", bundle: .main))
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityChildren() -> [Any]? { [] }
    override func accessibilityPerformPress() -> Bool { onClick(); return true }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

/// Menu item that runs a closure.
private final class MenuAction: NSMenuItem {
    private let run: () -> Void
    init(_ title: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(runAction), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("not used") }
    @objc private func runAction() { run() }
}

/// The bubble: a ring colored by the health score, RAM %, swap in use, the swap rate while the Mac swaps hard,
/// and optionally the number of agent sessions. Static: no repeating animation.
struct BubbleView: View {
    @EnvironmentObject var model: BubbleModel

    var body: some View {
        HStack(spacing: 10) {
            if let r = model.reading {
                ring(r)
                VStack(alignment: .leading, spacing: 1) {
                    Text("RAM \(r.ram)").font(.system(size: 13, weight: .semibold))
                    Text("Swap \(r.swap)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if let rate = r.swapRate {
                    // Swap in and out per minute: only while the Mac swaps hard.
                    Label(rate, systemImage: "arrow.up.arrow.down")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.orange)
                }
                if let n = r.sessions {
                    // Agent sessions (optional, Settings > Look).
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles").foregroundStyle(Palette.tint)
                        Text("\(n)")
                    }
                    .font(.system(size: 12, weight: .medium))
                }
            } else {
                Text("Measuring…").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
        .padding(.leading, 6).padding(.trailing, 14).padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .padding(4)  // room for the shadow edge
    }

    private func ring(_ r: BubbleReading) -> some View {
        let color = Self.color(r.tone)
        return ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: 3.5)
            Circle().trim(from: 0, to: max(0.02, Double(r.score) / 100))
                .stroke(color, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(r.score)").font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .frame(width: 30, height: 30)
    }

    /// Same colors as the health ring (the stronger tone of each band).
    static func color(_ t: BubbleReading.Tone) -> Color {
        switch t {
        case .smooth: return .green
        case .heavy: return .yellow
        case .slow: return .orange
        case .overloaded: return .red
        }
    }
}

extension BubbleMode {
    var name: String {
        switch self {
        case .off: return String(localized: "Off", bundle: .main)
        case .whenMinimized: return String(localized: "When the window is minimized", bundle: .main)
        case .always: return String(localized: "Always", bundle: .main)
        }
    }
}
