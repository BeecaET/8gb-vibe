import SwiftUI
import VibeCore

/// First-run welcome: what the app found, where its icon lives, what happens in the first 30 minutes.
/// Skippable, shown once, reopened from About. Asks for nothing (no notifications, MCP or launch at login).
struct WelcomeSheet: View {
    @EnvironmentObject var monitor: Monitor
    static let seenKey = StoredName.welcomeSeen

    var body: some View {
        let h = monitor.hardware
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to 8GB Vibe").font(.title.weight(.bold))
                    Text("Monitor resources and review ways to reduce load when running agents, Xcode and Docker on a Mac.").foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                item("checkmark.seal.fill", .green, "Mac recognized",
                     String(localized: "\(h.modelName), \(h.ramGB) GB RAM. Alert thresholds are tuned for this Mac.", bundle: .main))
                item("menubar.rectangle", .blue, "The icon lives in the menu bar",
                     String(localized: "A small ring at the top right of the screen. On Macs with a notch it may be hidden: quit some other menu bar items, or hold Cmd and drag to rearrange. Click the ring and choose \"Open 8GB Vibe\" to open this window.", bundle: .main))
                item("hourglass", .orange, "Monitoring",
                     String(localized: "Suggestions cover items with low activity for over \(Format.number(monitor.thresholds.idleMinutes, digits: 0)) minutes and at least 200 MB of memory. There may be no matching items yet. The Memory page shows usage by group.", bundle: .main))
                item("hand.raised.fill", .purple, "Nothing else to turn on",
                     String(localized: "Notifications, agent connection (MCP) and open at login are all optional in Settings. The app never quits or deletes anything on its own; every quit asks you first.", bundle: .main))
            }
            HStack {
                Button("Skip") { finish() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("View Memory now") { finish(); monitor.page = .memory }
                Button("Get started") { finish() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
        .padding(26)
        .frame(width: 560)
    }

    private func item(_ symbol: String, _ tint: Color, _ title: LocalizedStringKey, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.seenKey)
        monitor.showWelcome = false
    }
}
