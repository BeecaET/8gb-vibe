import AppKit
import SwiftUI

/// Product information, read from Info.plist when running as an .app.
enum Product {
    static let name = "8GB Vibe"
    static let summary = String(localized: "Trợ lý cho người vibe code trên máy Mac 8 GB. Theo dõi RAM, swap, CPU, ổ đĩa và giúp tắt app đang chiếm tài nguyên.", bundle: .main)
    static let tagline = "Vibe coding on a budget Mac"
    /// Download and about page for 8GB Vibe.
    static let website = URL(string: "https://8gb.beeca.vn")!
    static let companyPage = URL(string: "https://beeca.vn")!
    static let priceNote = String(localized: "Miễn phí 100%. Không quảng cáo, không thu phí ẩn, không cần tài khoản.", bundle: .main)
    static let defaultCopyright = String(localized: "© 2026 BEECA. Mã nguồn theo Apache 2.0.", bundle: .main)
    static let licenseNote = String(localized: "Apache 2.0. Tên 8GB Vibe, icon app và logo BEECA là nhãn hiệu của BEECA, không thuộc giấy phép này.", bundle: .main)

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

    static let privacy = String(localized: "8GB Vibe chạy hoàn toàn trên máy của bạn. App không thu thập, không gửi dữ liệu đi đâu, không cần tài khoản và không cần quyền quản trị.", bundle: .main)

    /// Standard macOS "About" panel.
    static func openAboutPanel() {
        let credits = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 6
        let owner: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
                                                  .paragraphStyle: paragraph]
        credits.append(NSAttributedString(string: summary + "\n", attributes: owner))
        credits.append(NSAttributedString(string: String(localized: "Miễn phí 100%.", bundle: .main) + "\n", attributes: owner))
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
                    Text("Phiên bản \(Product.versionString) (build \(Product.buildNumber))")
                        .font(.callout).foregroundStyle(.secondary)
                    StatusPill(owner: "Miễn phí 100%", color: .green)
                }
                Text(Product.summary)
                    .font(.title3).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    .frame(maxWidth: 520)
                HStack(spacing: 10) {
                    Link(destination: Product.website) { Label("8gb.beeca.vn", systemImage: "arrow.down.circle") }
                        .buttonStyle(.borderedProminent)
                    Button { Product.openAboutPanel() } label: { Label("Bảng giới thiệu", systemImage: "info.circle") }
                    Button { monitor.showWelcome = true } label: { Label("Xem lại hướng dẫn", systemImage: "hand.wave") }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)

            MachineSummaryRow()

            VStack(alignment: .leading, spacing: 10) {
                Label("Miễn phí 100%", systemImage: "gift").font(.headline)
                Text(Product.priceNote).foregroundStyle(.secondary)
                Text("Tải bản mới nhất tại 8gb.beeca.vn.").foregroundStyle(.secondary)
            }
            .card()

            VStack(alignment: .leading, spacing: 10) {
                Label("Quyền riêng tư", systemImage: "lock.shield").font(.headline)
                Text(Product.privacy).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .card()

            VStack(alignment: .leading, spacing: 10) {
                Label("An toàn", systemImage: "checkmark.shield").font(.headline)
                VStack(alignment: .leading, spacing: 6) {
                    row("Không tự tắt, không tự xoá. Mọi lần thoát app đều cần bạn xác nhận.")
                    row("App có giao diện nhận lệnh thoát macOS; tiến trình nền nhận tín hiệu dừng. Hãy lưu việc trước.")
                    row("Không cho thoát Finder, Dock và app Claude từ 8GB Vibe.")
                    row("Kết quả đóng app, dừng tiến trình, cài/gỡ MCP và nhả chỗ việc nặng được ghi vào Nhật ký.")
                }
            }
            .card()

            VStack(alignment: .leading, spacing: 10) {
                Label("Thông tin", systemImage: "doc.text").font(.headline)
                table("Nhà phát triển", "BEECA")
                table("Giá", String(localized: "Miễn phí 100%", bundle: .main))
                table("Tải về", "8gb.beeca.vn")
                table("Bản quyền", Product.copyright)
                table("Giấy phép mã nguồn", Product.licenseNote)
                table("Yêu cầu", String(localized: "macOS 13 trở lên, Apple Silicon hoặc Intel", bundle: .main))
                table("Thư viện bên thứ ba", String(localized: "Không dùng. Chỉ dùng thư viện của Apple.", bundle: .main))
            }
            .card()

            VStack(spacing: 8) {
                Text("Một sản phẩm của").font(.callout).foregroundStyle(.secondary)
                if let logo = Product.logoBeeca {
                    Link(destination: Product.companyPage) {
                        // Yellow and green logo: always on a black tile so it reads in light and dark mode.
                        Image(nsImage: logo).resizable().interpolation(.high).aspectRatio(contentMode: .fit).frame(height: 56)
                            .padding(10)
                            .background(Color.black, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .help("beeca.vn")
                    .accessibilityLabel("BEECA, mở beeca.vn")
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
