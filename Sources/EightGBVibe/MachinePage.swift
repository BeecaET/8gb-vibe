import SwiftUI
import VibeCore

/// "Mac" page: this Mac's configuration in detail, read only. Static values come from the saved scan
/// (hardware.json); live values (memory, battery, displays, uptime, heat) are read while the page is open, never saved.
/// No network, no other app is run. Anything not readable says so instead of guessing.
struct MachinePage: View {
    @EnvironmentObject var monitor: Monitor
    @State private var live: MacLive?

    private static let date: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy HH:mm"
        return f
    }()

    var body: some View {
        PageContainer {
            hero
            summaryCards
            memoryCard
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                chipCard
                diskCard
                if live?.battery != nil { batteryCard }
                displayCard
                systemCard
            }
            toolsCard
            profileCard
            scanFooter
        }
        .task {
            while !Task.isCancelled {
                live = await Task.detached(priority: .utility) { MacLive.read() }.value
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    // MARK: Hero, like "About This Mac"

    private var hero: some View {
        let h = monitor.hardware
        let p = monitor.profile
        return HStack(alignment: .center, spacing: 20) {
            Image(systemName: Self.symbol(for: h.modelName))
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(Palette.tint)
                .frame(width: 96, height: 80)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(h.modelName).font(.largeTitle.weight(.bold)).lineLimit(2).minimumScaleFactor(0.8)
                Text(heroLine).font(.title3).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    StatusPill(owner: LocalizedStringKey(p.name), color: Palette.tint)
                    if p.tier != .gb8 { StatusPill(owner: "thử nghiệm", color: .orange) }
                    if let y = h.modelYear { Text(verbatim: String(y)).font(.callout).foregroundStyle(.secondary) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var heroLine: String {
        let h = monitor.hardware
        return [h.chip, "\(h.ramGB) GB", "macOS " + (h.macOSFull ?? h.macOSVersion)].joined(separator: " · ")
    }

    /// SF Symbol for the kind of Mac, from its marketing name.
    static func symbol(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("macbook") { return "laptopcomputer" }
        if n.contains("imac") { return "desktopcomputer" }
        if n.contains("mac mini") { return "macmini" }
        if n.contains("mac studio") { return "macstudio" }
        if n.contains("mac pro") { return "macpro.gen3" }
        return "laptopcomputer"
    }

    // MARK: Summary cards with live numbers

    private var summaryCards: some View {
        let h = monitor.hardware
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12, alignment: .top)], spacing: 12) {
            summary("cpu", "Chip", value: String(localized: "\(h.totalCores) nhân", bundle: .main),
                    detail: h.gpuCores.map { String(localized: "\($0) nhân GPU", bundle: .main) }
                        ?? (h.appleSilicon ? String(localized: "\(h.performanceCores) hiệu năng, \(h.efficiencyCores) tiết kiệm", bundle: .main) : h.chip),
                    ratio: nil)
            if let s = monitor.system {
                summary("memorychip", "Bộ nhớ", value: "\(h.ramGB) GB",
                        detail: String(localized: "Đang dùng \(Format.percent(s.memory.usedRatio))", bundle: .main),
                        ratio: s.memory.usedRatio)
            } else {
                summary("memorychip", "Bộ nhớ", value: "\(h.ramGB) GB", detail: h.memoryType, ratio: nil)
            }
            summary("internaldrive", "Ổ đĩa", value: h.diskBytes > 0 ? Format.bytes(h.diskBytes, digits: 0) : "-",
                    detail: live?.diskFree.map { String(localized: "Còn trống \(Format.bytes($0))", bundle: .main) },
                    ratio: diskRatio)
            if let b = live?.battery {
                summary("battery.100percent", "Dung lượng tối đa của pin", value: b.capacityPercent.map { "\($0)%" } ?? "-",
                        detail: b.cycleCount.map { String(localized: "\($0) lần sạc", bundle: .main) },
                        ratio: nil)
            }
        }
    }

    private var diskRatio: Double? {
        let h = monitor.hardware
        guard h.diskBytes > 0, let free = live?.diskFree else { return nil }
        return min(1, max(0, 1 - Double(free) / Double(h.diskBytes)))
    }

    private func summary(_ symbol: String, _ title: LocalizedStringKey, value: String, detail: String?,
                         ratio: Double?, goodWhenHigh: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            Text(detail ?? String(localized: "Không đọc được", bundle: .main))
                .font(.callout).foregroundStyle(.secondary).lineLimit(1)
            if let ratio {
                ProgressView(value: ratio).progressViewStyle(.linear)
                    .tint(meterColor(ratio, goodWhenHigh: goodWhenHigh))
            }
        }
        .card(padding: 14)
    }

    private func meterColor(_ r: Double, goodWhenHigh: Bool) -> Color {
        let bad = goodWhenHigh ? 1 - r : r
        return bad >= 0.9 ? .red : (bad >= 0.75 ? .orange : Palette.tint)
    }

    // MARK: Memory

    private var memoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Bộ nhớ").font(.headline)
                Spacer()
                if let s = monitor.system {
                    Text("Swap đang dùng \(Format.bytes(s.swap.used))").font(.callout)
                        .foregroundStyle(s.swap.used > 0 ? Color.orange : Color.secondary)
                }
            }
            if let s = monitor.system {
                let m = s.memory
                let parts: [(LocalizedStringKey, UInt64, Color)] = [
                    ("Ứng dụng", m.app, .blue), ("Nén", m.compressed, .purple),
                    ("Wired", m.wired, .gray), ("Trống", m.total > m.used ? m.total - m.used : 0, Color.primary.opacity(0.12)),
                ]
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                            RoundedRectangle(cornerRadius: 3).fill(part.2)
                                .frame(width: max(0, geo.size.width * CGFloat(part.1) / CGFloat(max(m.total, 1)) - 2))
                        }
                    }
                }
                .frame(height: 14)
                .accessibilityHidden(true)
                HStack(spacing: 16) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(part.2).frame(width: 10, height: 10)
                            Text(part.0).foregroundStyle(.secondary)
                            Text(Format.bytes(part.1)).monospacedDigit()
                        }
                        .font(.callout)
                        .accessibilityElement(children: .combine)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                if monitor.hardware.appleSilicon {
                    Text("\(monitor.hardware.ramGB) GB \(monitor.hardware.memoryType ?? ""), dùng chung cho CPU và GPU.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                Text("Đang đọc...").foregroundStyle(.secondary)
            }
        }
        .card()
    }

    // MARK: Detail cards (2-column grid)

    private var chipCard: some View {
        let h = monitor.hardware
        return detailCard("Chip", symbol: "cpu") {
            row("Chip", h.chip)
            row("Nhân CPU", h.appleSilicon
                ? String(localized: "\(h.totalCores) nhân: \(h.performanceCores) hiệu năng, \(h.efficiencyCores) tiết kiệm", bundle: .main)
                : String(localized: "\(h.totalCores) nhân", bundle: .main))
            row("Nhân GPU", h.gpuCores.map(String.init))
            row("Kiến trúc", h.architecture)
            row("Mã model", h.model)
        }
    }

    private var diskCard: some View {
        let h = monitor.hardware
        return detailCard("Ổ đĩa", symbol: "internaldrive") {
            row("Dung lượng", h.diskBytes > 0 ? Format.bytes(h.diskBytes, digits: 0) : nil)
            row("Còn trống", live?.diskFree.map { Format.bytes($0) })
            row("Định dạng", h.diskFormat.isEmpty ? nil : h.diskFormat)
            row("Vị trí", h.diskInternal ? String(localized: "Ổ trong", bundle: .main) : String(localized: "Ổ ngoài", bundle: .main))
            row("Ổ", [h.diskModel, h.diskMedium].compactMap { $0 }.joined(separator: ", ").nilIfEmpty)
            if h.smartCapable == true {
                Text("SMART: ổ có hỗ trợ. Tình trạng cần công cụ khác để đọc, app không đọc.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var batteryCard: some View {
        let b = live?.battery
        return detailCard("Pin", symbol: "battery.100percent") {
            row("Tình trạng", b?.health)
            row("Số lần sạc", b?.cycleCount.map { c in b?.designCycles.map { String(localized: "\(c) / \($0) lần theo thiết kế", bundle: .main) } ?? "\(c)" })
            row("Dung lượng tối đa", b?.capacityPercent.map { pct in
                String(localized: "\(pct)% so với thiết kế (\(b?.fullChargeCapacity ?? 0) / \(b?.designCapacity ?? 0) mAh)", bundle: .main) })
            row("Mức pin", b?.chargePercent.map { "\($0)%" })
            row("Đang sạc", b?.isCharging.map { $0 ? String(localized: "Có", bundle: .main) : String(localized: "Không", bundle: .main) })
            row("Nguồn điện", b?.onAC.map { $0 ? String(localized: "Bộ sạc", bundle: .main) : String(localized: "Pin", bundle: .main) })
        }
    }

    private var displayCard: some View {
        detailCard("Màn hình", symbol: "display") {
            if let ds = live?.displays, !ds.isEmpty {
                ForEach(Array(ds.enumerated()), id: \.offset) { _, d in
                    row(d.builtIn ? "Màn hình tích hợp" : "Màn hình ngoài", displayText(d))
                }
            } else {
                row("Số màn hình", live == nil ? String(localized: "Đang đọc...", bundle: .main) : nil)
            }
        }
    }

    private var systemCard: some View {
        let h = monitor.hardware
        return detailCard("Hệ thống", symbol: "apple.logo") {
            row("macOS", [h.macOSFull ?? h.macOSVersion, h.macOSBuild.map { "(\($0))" }].compactMap { $0 }.joined(separator: " "))
            row("Đã chạy", live?.uptime.map { Format.duration($0) })
            row("Nhiệt", live.map { thermalText($0.thermal) })
            row("Chế độ Nguồn điện thấp", live.map { $0.lowPowerMode ? String(localized: "Bật", bundle: .main) : String(localized: "Tắt", bundle: .main) })
        }
    }

    // MARK: Developer tools, with each app's real icon

    private var toolsCard: some View {
        let h = monitor.hardware
        return VStack(alignment: .leading, spacing: 12) {
            Label("Công cụ phát triển", systemImage: "hammer").font(.headline)
            if let tools = h.toolDetails, !tools.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10, alignment: .leading)], alignment: .leading, spacing: 10) {
                    ForEach(tools, id: \.name) { t in
                        HStack(spacing: 10) {
                            IconApp(path: t.path, size: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(LocalizedStringKey(t.name)).lineLimit(1)
                                Text(t.version ?? String(localized: "có, không rõ phiên bản", bundle: .main))
                                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityElement(children: .combine)
                    }
                }
            } else {
                Text(h.toolDetails == nil ? "Bấm Quét lại để đọc." : "Không thấy Xcode, Docker, OrbStack, Android Studio.")
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    // MARK: Optimization profile

    private var profileCard: some View {
        let p = monitor.profile
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label("Hồ sơ tối ưu", systemImage: "slider.horizontal.3").font(.headline)
                StatusPill(owner: LocalizedStringKey(p.name), color: Palette.tint)
                if p.tier != .gb8 { StatusPill(owner: "thử nghiệm", color: .orange) }
                Spacer()
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                gridRow("Swap vàng / đỏ", "\(Format.number(p.thresholds.swapYellowGB, digits: 0)) / \(Format.number(p.thresholds.swapRedGB, digits: 0)) GB")
                gridRow("Phiên agent khuyên dưới / báo đỏ", "\(p.thresholds.sessionsYellow) / \(p.thresholds.sessionsRed)")
                gridRow("Tải CPU 5 phút vàng / đỏ", "\(Format.number(p.thresholds.load5Yellow, digits: 0)) / \(Format.number(p.thresholds.load5Red, digits: 0))")
                gridRow("RAM chừa cho hệ thống", Format.bytes(p.headroomReserve, digits: 1))
                gridRow("Báo \"Swap đang rất nặng\" từ", String(localized: "\(Format.number(p.freezeSevereMBPerMin / 1024, digits: 1)) GB mỗi phút", bundle: .main))
                gridRow("Quét tiến trình khi chạy nền", String(localized: "mỗi \(Int(p.backgroundScanSeconds)) giây", bundle: .main))
            }
            Text(p.tier == .gb8
                 ? "Mặc định cho máy 8 GB. Giá trị bạn đã tự chỉnh trong Cài đặt được giữ nguyên."
                 : "Giá trị cho máy 16 GB và 24 GB trở lên là thử nghiệm (ước tính, chưa đo). Giá trị bạn đã tự chỉnh trong Cài đặt được giữ nguyên.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private func gridRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit().textSelection(.enabled)
        }
    }

    private var scanFooter: some View {
        let h = monitor.hardware
        return VStack(alignment: .leading, spacing: 6) {
            if let notice = monitor.hardwareNotice { Text(notice).foregroundStyle(.green) }
            HStack {
                Text("Quét lúc \(Self.date.string(from: h.scannedAt))").foregroundStyle(.secondary)
                Spacer()
                Button("Quét lại") { monitor.rescanHardware() }
            }
            Text("Chỉ đọc thông tin trên máy, không gửi đi đâu. Không đọc số serial. Thông tin tĩnh lưu ở hardware.json (chỉ bạn đọc được); số đang chạy không lưu.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Building blocks

    private func detailCard<C: View>(_ title: LocalizedStringKey, symbol: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.headline)
            VStack(alignment: .leading, spacing: 8) { content() }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card()
    }

    /// One row; a missing value reads "Không đọc được" in secondary text (never a guess, never loud).
    private func row(_ label: LocalizedStringKey, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if let value {
                Text(value).textSelection(.enabled).multilineTextAlignment(.trailing)
            } else {
                Text("Không đọc được").foregroundStyle(.secondary)
            }
        }
    }

    private func displayText(_ d: DisplayInfo) -> String {
        let size = String(localized: "\(d.pixelWidth) x \(d.pixelHeight) điểm ảnh, hiển thị như \(d.width) x \(d.height)", bundle: .main)
        let hz: String
        if let r = d.refreshHz { hz = String(localized: "\(Int(r.rounded())) Hz", bundle: .main) }
        else { hz = String(localized: "tần số không đọc được", bundle: .main) }
        return size + ", " + hz
    }

    private func thermalText(_ s: String) -> String {
        switch s {
        case "nominal": return String(localized: "Bình thường", bundle: .main)
        case "fair": return String(localized: "Hơi nóng", bundle: .main)
        case "serious": return String(localized: "Nóng, máy có thể giảm tốc", bundle: .main)
        case "critical": return String(localized: "Rất nóng, hiệu năng có thể bị giới hạn", bundle: .main)
        default: return String(localized: "Không đọc được", bundle: .main)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// One line on About: what this Mac is, and a button to the Mac page.
struct MachineSummaryRow: View {
    @EnvironmentObject var monitor: Monitor

    var body: some View {
        HStack {
            Label(monitor.hardware.summary, systemImage: "laptopcomputer")
            Spacer()
            Button("Xem cấu hình máy") { monitor.page = .machine }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }
}
