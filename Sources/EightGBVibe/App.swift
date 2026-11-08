import AppKit
import SwiftUI
import VibeCore
import UserNotifications

/// Handles clicks on notifications.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if Bundle.main.bundleIdentifier != nil { UNUserNotificationCenter.current().delegate = self }
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
    @StateObject private var monitor = Monitor()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(monitor)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)

        Window(Product.name, id: "chinh") {
            MainWindow()
                .environmentObject(monitor)
                .frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 980, height: 680)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Giới thiệu \(Product.name)") { Product.openAboutPanel() }
            }
        }
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
                openWindow(id: "chinh")
                NSApp.activate(ignoringOtherApps: true)
            }
            .task {
                let args = CommandLine.arguments
                if let i = args.firstIndex(of: "--window") {
                    if i + 1 < args.count, let t = Page(rawValue: args[i + 1]) { monitor.page = t }
                    openWindow(id: "chinh")
                    NSApp.activate(ignoringOtherApps: true)
                }
                // --preview-reward <MB>: shows the reward card as if that much RAM was just freed (UI testing).
                if let i = args.firstIndex(of: "--preview-reward"), i + 1 < args.count, let mb = UInt64(args[i + 1]) {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    monitor.lastFreed = FreedSummary(bytes: mb << 20, count: 2)
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
