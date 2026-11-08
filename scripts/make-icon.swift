// Draws the 8GB Vibe icon and builds Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
// Design ("premium emerald"): a rounded square with depth (emerald gradient, soft top-left light, darker base,
// thin light rim), the digit 8 drawn as two clock loops next to "GB", a small "VIBE" below and a RAM bar on top.
// Below 48 px only the 8 is drawn, larger and bolder, so the icon stays readable in Finder lists and the menu.
import AppKit

/// The "headroom, gained" color: the last 2 RAM cells and the reclaimed part of the 8.
let headroomColor = NSColor(red: 0.85, green: 0.98, blue: 0.55, alpha: 1)

func hex(_ h: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(red: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a)
}

func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let f = NSFont.systemFont(ofSize: size, weight: weight)
    if let d = f.fontDescriptor.withDesign(.rounded), let r = NSFont(descriptor: d, size: size) { return r }
    return f
}

/// The 8 as two clock loops: a solid upper loop, a lower loop with a faint track, a white hand running clockwise and
/// a lime end with a rounded arrow head (resources reclaimed and cycled back). Loops are ellipses stretched sideways;
/// the path is stretched before stroking so the stroke stays even.
func drawEight(center: CGPoint, scale W: CGFloat, stroke: CGFloat, arrow: Bool) {
    let lowerRadius = W * 0.105, upperRadius = W * 0.088, widthScale: CGFloat = 1.15
    let lowerCenter = CGPoint(x: center.x, y: center.y - upperRadius)
    let upperCenter = CGPoint(x: center.x, y: lowerCenter.y + lowerRadius + upperRadius)
    func arc(_ c: CGPoint, _ r: CGFloat, _ from: CGFloat, _ to: CGFloat, clockwise: Bool, _ color: NSColor) {
        let p = NSBezierPath()
        p.appendArc(withCenter: .zero, radius: r, startAngle: from, endAngle: to, clockwise: clockwise)
        var t = AffineTransform(translationByX: c.x, byY: c.y)
        t.scale(x: widthScale, y: 1)
        p.transform(using: t)
        p.lineWidth = stroke; p.lineCapStyle = .round
        color.setStroke(); p.stroke()
    }
    arc(lowerCenter, lowerRadius, 0, 360, clockwise: false, NSColor.white.withAlphaComponent(0.28))
    arc(upperCenter, upperRadius, 0, 360, clockwise: false, .white)
    arc(lowerCenter, lowerRadius, 200, -20, clockwise: true, .white)
    arc(lowerCenter, lowerRadius, -20, -95, clockwise: true, headroomColor)
    guard arrow else { return }
    // Arrow head at the end of the lime arc, following the ellipse tangent; its size is capped.
    let a = -95 * CGFloat.pi / 180, rx = lowerRadius * widthScale
    let tip = CGPoint(x: lowerCenter.x + rx * cos(a), y: lowerCenter.y + lowerRadius * sin(a))
    let tx = rx * sin(a), ty = -lowerRadius * cos(a), len = max(0.0001, (tx * tx + ty * ty).squareRoot())
    let dir = CGPoint(x: tx / len, y: ty / len), normal = CGPoint(x: dir.y, y: -dir.x)
    let length = min(stroke * 0.8, W * 0.06), halfWidth = min(stroke * 0.85, W * 0.065)
    let p = NSBezierPath()
    p.move(to: CGPoint(x: tip.x + dir.x * length, y: tip.y + dir.y * length))
    p.line(to: CGPoint(x: tip.x + normal.x * halfWidth, y: tip.y + normal.y * halfWidth))
    p.line(to: CGPoint(x: tip.x - normal.x * halfWidth, y: tip.y - normal.y * halfWidth))
    p.close()
    p.lineJoinStyle = .round; p.lineWidth = min(stroke * 0.45, W * 0.032)
    headroomColor.setFill(); headroomColor.setStroke(); p.fill(); p.stroke()
}

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // Squircle on the macOS icon grid (about 10 % margin) with a soft drop shadow.
    let margin = s * 0.1
    let box = CGRect(x: margin, y: margin, width: s - 2 * margin, height: s - 2 * margin), W = box.width
    let shape = NSBezierPath(roundedRect: box, xRadius: W * 0.225, yRadius: W * 0.225)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.015), blur: s * 0.035, color: NSColor.black.withAlphaComponent(0.4).cgColor)
    NSColor.black.setFill(); shape.fill()
    ctx.restoreGState()
    ctx.saveGState()
    shape.addClip()

    // Material: emerald gradient, light from the top left, a darker base, then a thin light rim.
    NSGradient(colors: [hex(0x053D30), hex(0x047857), hex(0x10B981)])!.draw(in: box, angle: 65)
    let light = CGPoint(x: box.minX + W * 0.25, y: box.maxY - W * 0.1)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.30), NSColor.white.withAlphaComponent(0)])!
        .draw(fromCenter: light, radius: 0, toCenter: light, radius: W * 0.8, options: [])
    NSGradient(colors: [NSColor.black.withAlphaComponent(0), NSColor.black.withAlphaComponent(0.28)])!
        .draw(in: CGRect(x: box.minX, y: box.minY, width: W, height: W * 0.45), angle: -90)
    let rim = NSBezierPath(roundedRect: box.insetBy(dx: W * 0.004, dy: W * 0.004), xRadius: W * 0.222, yRadius: W * 0.222)
    rim.lineWidth = max(1, W * 0.008)
    NSColor.white.withAlphaComponent(0.22).setStroke(); rim.stroke()

    // The glyphs share one soft shadow, drawn as a group so overlapping strokes do not darken each other.
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -W * 0.012)
    shadow.shadowBlurRadius = W * 0.025

    if px < 48 {
        // Small sizes: only the 8, centered, large and bold.
        let scale = W * 1.75
        ctx.saveGState(); shadow.set(); ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        drawEight(center: CGPoint(x: box.midX, y: box.midY - W * 0.02), scale: scale, stroke: scale * 0.085, arrow: false)
        ctx.endTransparencyLayer(); ctx.restoreGState()
    } else {
        let gbFont = roundedFont(W * 0.34, .heavy)
        let gb = NSAttributedString(string: "GB", attributes: [.font: gbFont, .foregroundColor: NSColor.white, .kern: -W * 0.012])
        let stroke = W * 0.078
        let eightWidth = 2 * 0.105 * W * 1.15 + stroke, gap = W * 0.04
        let x8 = s / 2 - (eightWidth + gap + gb.size().width) / 2
        let baseline = box.minY + W * 0.30
        ctx.saveGState(); shadow.set(); ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        drawEight(center: CGPoint(x: x8 + eightWidth / 2, y: baseline + stroke / 2 + 0.088 * W + 0.105 * W - W * 0.005),
                  scale: W, stroke: stroke, arrow: true)
        gb.draw(at: CGPoint(x: x8 + eightWidth + gap, y: baseline + gbFont.descender))
        ctx.endTransparencyLayer(); ctx.restoreGState()

        // "VIBE": small, tracked out, slightly transparent.
        let vibe = NSAttributedString(string: "VIBE", attributes: [.font: roundedFont(W * 0.105, .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.75), .kern: W * 0.04])
        vibe.draw(at: CGPoint(x: s / 2 - vibe.size().width / 2 + W * 0.02, y: box.minY + W * 0.14))

        // RAM bar on top: 8 cells, 6 bright and 2 lime ("headroom").
        let cells = 8, barWidth = W * 0.5, cellHeight = W * 0.04, cellGap = W * 0.013
        let cellWidth = (barWidth - cellGap * CGFloat(cells - 1)) / CGFloat(cells)
        for i in 0..<cells {
            let r = CGRect(x: s / 2 - barWidth / 2 + CGFloat(i) * (cellWidth + cellGap), y: box.minY + W * 0.83,
                           width: cellWidth, height: cellHeight)
            (i < 6 ? NSColor.white.withAlphaComponent(0.85) : headroomColor).setFill()
            NSBezierPath(roundedRect: r, xRadius: cellHeight / 2, yRadius: cellHeight / 2).fill()
        }
    }
    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let directory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.iconset")
try? fm.removeItem(at: directory)
try! fm.createDirectory(at: directory, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                  ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! draw(px).write(to: directory.appendingPathComponent("icon_\(name).png"))
}
print("Drew icons into \(directory.path)")
