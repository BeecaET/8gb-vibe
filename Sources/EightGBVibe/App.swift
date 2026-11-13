import AppKit
import SwiftUI
import VibeCore
import UserNotifications

/// Handles clicks on notifications.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if Bundle.main.bundleIdentifier != nil { UNUserNotificationCenter.current().delegate = self }
        ActionLog.tightenPermissions()
        DockIcon.start()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        NotificationCenter.default.post(name: Notifier.openFreeRAM, object: nil)
        done()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }
}

/// The app lives in the menu bar (LSUIElement). While the main window is open it also shows in the Dock
/// and the app switcher (⌘Tab), like a normal app; closing the window hides the Dock icon again.
enum DockIcon {
    /// The SwiftUI `Window` scene id of the main window.
    static let mainWindowID = StoredName.mainWindow

    static func isMainWindow(_ w: NSWindow) -> Bool {
        w.identifier?.rawValue.contains(mainWindowID) == true
    }

    @MainActor static func update(closing: NSWindow? = nil) {
        let open = NSApp.windows.contains { $0 !== closing && isMainWindow($0) && $0.isVisible }
        let wanted: NSApplication.ActivationPolicy = open ? .regular : .accessory
        guard NSApp.activationPolicy() != wanted else { return }
        NSApp.setActivationPolicy(wanted)
        if open { NSApp.activate(ignoringOtherApps: true) }
    }

    static func start() {
        let nc = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification, NSWindow.didDeminiaturizeNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { n in
                guard let w = n.object as? NSWindow, isMainWindow(w) else { return }
                MainActor.assumeIsolated { update() }
            }
        }
        nc.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { n in
            guard let w = n.object as? NSWindow, isMainWindow(w) else { return }
            MainActor.assumeIsolated { update(closing: w) }
        }
    }
}

@main
struct EightGBVibeApp: App {
    init() {
        Self.runMeasurementCommand()
    }

    /// Command line tools for the measurements, run before any UI or sampling starts, then exit:
    ///   8GBVibe --measurement-summary          prints a per-session summary (strained minutes, overlapping heavy jobs)
    ///   8GBVibe --export-measurements <file>    writes every stored minute as one CSV file
    static func runMeasurementCommand() {
        let args = CommandLine.arguments
        let store = MeasurementStore(directory: MeasurementStore.defaultDirectory)
        if args.contains("--measurement-summary") {
            print(MeasurementSummary.report(store.rows(since: .distantPast), folder: store.directory))
            exit(0)
        }
        if let i = args.firstIndex(of: "--export-measurements"), i + 1 < args.count {
            let rows = store.rows(since: .distantPast)
            let text = ([MinuteRow.header] + rows.map(\.csv)).joined(separator: "\n") + "\n"
            let url = URL(fileURLWithPath: args[i + 1])
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                print("\(rows.count) rows -> \(url.path)")
                exit(0)
            } catch {
                print("Error: \(error.localizedDescription)")
                exit(1)
            }
        }
    }

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // @State, not @StateObject: the App must not observe the Monitor. With @StateObject every sample (every 5 s)
    // re-ran this body and rebuilt every scene's root, including the Settings window and its launch-at-login query
    // (an XPC call): the largest CPU cost with the main window open. Views observe the Monitor themselves.
    @State private var monitor = Monitor()

    var body: some Scene {
        MenuBarExtra {
            ThemedRoot { PopoverView() }
                .environmentObject(monitor)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)

        Window(Product.name, id: StoredName.mainWindow) {
            ThemedRoot { MainWindow() }
                .environmentObject(monitor)
                .frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 980, height: 680)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About \(Product.name)") { Product.openAboutPanel() }
            }
            // 8GB Vibe > Settings… (⌘,): opens the Settings page of the main window.
            CommandGroup(replacing: .appSettings) { SettingsMenuItem(monitor: monitor) }
            // View menu: every page with its standard shortcut, so shortcuts can be found where macOS users look.
            // (The main window's hidden buttons handle the same keys while it is key.)
            CommandGroup(before: .sidebar) {
                ForEach(Page.sidebarGroups.flatMap(\.pages).filter { $0 != .settings }) { p in  // Settings is in the app menu (⌘,)
                    if let k = p.shortcut {
                        Button(p.name) { monitor.page = p }.keyboardShortcut(KeyEquivalent(k))
                    } else {
                        Button(p.name) { monitor.page = p }
                    }
                }
                Divider()
                Button("Command Palette…") { monitor.showPalette.toggle() }.keyboardShortcut("k")
                Divider()
            }
        }

    }
}

/// "Settings…" in the app menu: shows the main window on its Settings page.
struct SettingsMenuItem: View {
    let monitor: Monitor
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Settings…") {
            monitor.page = .settings
            openWindow(id: DockIcon.mainWindowID)
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")
    }
}

/// Menu bar label: a ring (filled by % RAM, colored by level) plus swap or % RAM.
struct MenuBarLabel: View {
    @ObservedObject var monitor: Monitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let h = monitor.system
        let img = MenuBarIcon.ring(ratio: h?.memory.usedRatio ?? 0, color: monitor.overallLevel.nsColor)
        switch monitor.menuBarStyle {
        case .ringOnly:
            Image(nsImage: img)
        case .ringAndSwap:
            Image(nsImage: img)
            Text(h.map { Format.bytes($0.swap.used) } ?? "")
        case .ringAndRAM:
            Image(nsImage: img)
            Text(h.map { Format.percent($0.memory.usedRatio) } ?? "")
        }
        // With --window [page] the main window opens right away (for development and testing).
        Color.clear.frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: Notifier.openFreeRAM)) { _ in
                monitor.page = .freeRAM
                openWindow(id: StoredName.mainWindow)
                NSApp.activate(ignoringOtherApps: true)
            }
            // A click on the floating bubble while the main window is closed.
            .onReceive(NotificationCenter.default.publisher(for: FloatingBubble.openMainWindow)) { _ in
                openWindow(id: StoredName.mainWindow)
                NSApp.activate(ignoringOtherApps: true)
            }
            .task {
                FloatingBubble.shared.attach(monitor)
                let args = CommandLine.arguments
                if let i = args.firstIndex(of: "--window") {
                    if i + 1 < args.count, let t = Page(rawValue: args[i + 1]) { monitor.page = t }
                    openWindow(id: StoredName.mainWindow)
                    NSApp.activate(ignoringOtherApps: true)
                    // --size WxH: resizes the main window, e.g. 720x480 for the smallest layout (UI testing).
                    if let j = args.firstIndex(of: "--size"), j + 1 < args.count {
                        let wh = args[j + 1].split(separator: "x").compactMap { Double($0) }
                        if wh.count == 2 {
                            try? await Task.sleep(nanoseconds: 600_000_000)
                            NSApp.windows.first(where: DockIcon.isMainWindow)?.setContentSize(NSSize(width: wh[0], height: wh[1]))
                        }
                    }
                }
                // First run (or --welcome): open the main window with the welcome sheet. Never while capturing the popover.
                if (args.contains("--welcome") || !UserDefaults.standard.bool(forKey: WelcomeSheet.seenKey)),
                   !args.contains("--capture-popover") {
                    if !args.contains("--window") { openWindow(id: StoredName.mainWindow); NSApp.activate(ignoringOtherApps: true) }
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    monitor.showWelcome = true
                }
                // --light / --dark: forces the app's own appearance (UI testing; system settings are untouched).
                if args.contains("--light") { NSApp.appearance = NSAppearance(named: .aqua) }
                if args.contains("--dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
                // --preview-inbox: sample alerts in the inbox, kept in memory only (UI testing).
                if args.contains("--preview-inbox") {
                    Inbox.shared.loadPreview()
                }
                // --palette: opens the Cmd-K command palette (UI testing).
                if args.contains("--palette") {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    monitor.showPalette = true
                }
                // --preview-reward <MB>: shows the reward card as if that much RAM was just freed (UI testing).
                if let i = args.firstIndex(of: "--preview-reward"), i + 1 < args.count, let mb = UInt64(args[i + 1]) {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    monitor.lastFreed = FreedSummary(bytes: mb << 20, count: 2, failed: 1)
                }
                // --capture-popover <file.png>: renders the popover to an image, then quits (UI testing).
                if let i = args.firstIndex(of: "--capture-popover"), i + 1 < args.count {
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    let r = ImageRenderer(content: PopoverContent().environmentObject(monitor)
                        .background(Color(nsColor: .windowBackgroundColor)))
                    r.scale = 2
                    if let img = r.nsImage, let tiff = img.tiffRepresentation,
                       let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: args[i + 1]))
                    }
                    NSApp.terminate(nil)
                }
                #if DEBUG
                // --test-stop-dev-server <port>: stops the dev server on that port through the same path as
                // "Stop Selected" in the confirmation dialog (identity check, log). Debug builds only, for testing,
                // and only for a server running from the temporary folder.
                if let i = args.firstIndex(of: "--test-stop-dev-server"), i + 1 < args.count, let port = UInt16(args[i + 1]) {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    monitor.sampleProcesses()
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    // Only servers whose working directory is inside the temporary folder: never a real project's server.
                    let temp = (NSTemporaryDirectory() as NSString).resolvingSymlinksInPath
                    if let d = monitor.processes.devServers.first(where: { d in
                        d.ports.contains { $0.number == port }
                            && (d.directory.map { ($0 as NSString).resolvingSymlinksInPath.hasPrefix(temp) } ?? false)
                    }) {
                        monitor.quitAll([CandidateBuilder.from(d)])
                    }
                }
                #endif
            }
    }
}
