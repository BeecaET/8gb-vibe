import AppKit
import SwiftUI

/// Product information, read from Info.plist when running as an .app.
enum Product {
    static let name = "8GB Vibe"
    static let summary = String(localized: "A helper for vibe coding on an 8 GB Mac. Watches RAM, swap, CPU and disk, and helps quit apps hogging resources.", bundle: .main)
    static let tagline = "Vibe coding on a budget Mac"
    /// Download and about page for 8GB Vibe.
    static let website = URL(string: "https://8gb.beeca.vn")!
    static let companyPage = URL(string: "https://beeca.vn")!
    static let priceNote = String(localized: "100% free. No ads, no hidden fees, no account.", bundle: .main)
    static let defaultCopyright = String(localized: "© 2026 BEECA. Source code licensed under Apache 2.0.", bundle: .main)
    static let licenseNote = String(localized: "Apache 2.0. The 8GB Vibe name, the app icon and the BEECA logo are trademarks of BEECA and are not covered by this license.", bundle: .main)

    static var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
    static var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? defaultCopyright
    }

    /// BEECA logo bundled in the .app (Resources/BeecaLogo.png).
    static var logoBeeca: NSImage? {
        Bundle.main.url(forResource: "BeecaLogo", withExtension: "png").flatMap(NSImage.init(contentsOf:))
    }

    static let privacy = String(localized: "8GB Vibe runs entirely on your Mac. It collects nothing, sends no data anywhere, needs no account and no admin rights.", bundle: .main)

    /// Standard macOS "About" panel.
    static func openAboutPanel() {
        let credits = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 6
        let owner: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
                                                  .paragraphStyle: paragraph]
        credits.append(NSAttributedString(string: summary + "\n", attributes: owner))
        credits.append(NSAttributedString(string: String(localized: "100% free.", bundle: .main) + "\n", attributes: owner))
        credits.append(NSAttributedString(string: privacy + "\n", attributes: owner))
        var linkAttributes = owner
        linkAttributes[.link] = website
        credits.append(NSAttributedString(string: "8gb.beeca.vn", attributes: linkAttributes))
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: name,
            .applicationVersion: versionString,
            .version: "Build \(buildNumber)",
            .credits: credits
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// About page in the main window.
struct AboutPage: View {
    @EnvironmentObject var monitor: Monitor
    var body: some View {
        PageContainer {
            VStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 112, height: 112)
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                (Text("8GB").font(.system(size: 34, weight: .heavy, design: .rounded))
                 + Text(" Vibe").font(.system(size: 30, weight: .regular, design: .rounded)).foregroundColor(.secondary))
                Text(Product.tagline).font(.callout.italic()).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text("Version \(Product.versionString) (build \(Product.buildNumber))")
                        .font(.callout).foregroundStyle(.secondary)
                    StatusPill(owner: "100% free", color: .green)
                }
                Text(Product.summary)
                    .font(.title3).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    .frame(maxWidth: 520)
                HStack(spacing: 10) {
                    Link(destination: Product.website) { Label("8gb.beeca.vn", systemImage: "arrow.down.circle") }
                        .buttonStyle(.borderedProminent)
                    Button { Product.openAboutPanel() } label: { Label("About panel", systemImage: "info.circle") }
                    Button { monitor.showWelcome = true } label: { Label("Show welcome again", systemImage: "hand.wave") }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)

            MachineSummaryRow()

            VStack(alignment: .leading, spacing: 10) {
                Label("100% free", systemImage: "gift").font(.headline)
                Text(Product.priceNote).foregroundStyle(.secondary)
                Text("Get the latest version at 8gb.beeca.vn.").foregroundStyle(.secondary)
            }
            .card()

            VStack(alignment: .leading, spacing: 10) {
                Label("Privacy", systemImage: "lock.shield").font(.headline)
                Text(Product.privacy).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .card()

            VStack(alignment: .leading, spacing: 10) {
                Label("Safety", systemImage: "checkmark.shield").font(.headline)
                VStack(alignment: .leading, spacing: 6) {
                    row("Never quits or deletes on its own. Every quit needs your confirmation.")
                    row("GUI apps receive a macOS quit request; background processes receive a stop signal. Save your work first.")
                    row("Finder, Dock and the Claude app cannot be quit from 8GB Vibe.")
                    row("App quits, process stops, MCP installation/removal and heavy-job slot releases are recorded in the Log.")
                }
            }
            .card()

            VStack(alignment: .leading, spacing: 10) {
                Label("Info", systemImage: "doc.text").font(.headline)
                table("Developer", "BEECA")
                table("Price", String(localized: "100% free", bundle: .main))
                table("Download", "8gb.beeca.vn")
                table("Copyright", Product.copyright)
                table("Source code license", Product.licenseNote)
                table("Requirements", String(localized: "macOS 13 or later, Apple silicon or Intel", bundle: .main))
                table("Third-party libraries", String(localized: "None. Apple frameworks only.", bundle: .main))
            }
            .card()

            VStack(spacing: 8) {
                Text("A product of").font(.callout).foregroundStyle(.secondary)
                if let logo = Product.logoBeeca {
                    Link(destination: Product.companyPage) {
                        // Yellow and green logo: always on a black tile so it reads in light and dark mode.
                        Image(nsImage: logo).resizable().interpolation(.high).aspectRatio(contentMode: .fit).frame(height: 56)
                            .padding(10)
                            .background(Color.black, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .help("beeca.vn")
                    .accessibilityLabel("BEECA, open beeca.vn")
                } else {
                    Link("BEECA", destination: Product.companyPage).font(.headline)
                }
                Text(Product.copyright).font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
    }

    private func row(_ s: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark").font(.callout.weight(.bold)).foregroundStyle(.green)
            Text(s).foregroundStyle(.secondary)
        }
    }

    private func table(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary).frame(width: 160, alignment: .leading)
            Text(value).textSelection(.enabled)
            Spacer()
        }
        .font(.callout)
    }
}
