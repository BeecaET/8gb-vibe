// Draws the 8GB Vibe icon and builds Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
// Design: rounded square with an emerald background, the digit 8 drawn as two circulating arrow loops next to "GB",
// a small "VIBE" below and a mint RAM bar on top.
import AppKit

/// The "headroom, gained" color: used for the last 2 RAM cells and the reclaimed part of the 8.
let headroomColor = NSColor(red: 0.85, green: 0.98, blue: 0.55, alpha: 1)

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // Background: squircle on the macOS icon grid (about 10 % margin).
    let margin = s * 0.1
    let box = CGRect(x: margin, y: margin, width: s - 2 * margin, height: s - 2 * margin)
    let background = NSBezierPath(roundedRect: box, xRadius: box.width * 0.225, yRadius: box.width * 0.225)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor.black.setFill(); background.fill()
    ctx.restoreGState()
    background.addClip()
    // Emerald background: health, savings, calm (replaces indigo-violet, which felt more luxury than optimization).
    let gradient = NSGradient(colors: [NSColor(red: 0.02, green: 0.23, blue: 0.19, alpha: 1),
                                       NSColor(red: 0.02, green: 0.47, blue: 0.34, alpha: 1),
                                       NSColor(red: 0.06, green: 0.68, blue: 0.48, alpha: 1)])!
    gradient.draw(in: box, angle: 60)
    // Soft highlight on the upper half.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), NSColor.white.withAlphaComponent(0)])!
        .draw(in: CGRect(x: box.minX, y: box.midY, width: box.width, height: box.height / 2), angle: -90)

    // Rounded system font.
    func font(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let f = NSFont.systemFont(ofSize: size, weight: weight)
        if let d = f.fontDescriptor.withDesign(.rounded), let r = NSFont(descriptor: d, size: size) { return r }
        return f
    }
    // Hand-drawn 8: two round clock faces with a hand running around (optimize, circulate, reuse resources).
    // The upper loop runs counterclockwise, the lower loop clockwise; the mint end of the lower loop is
    // the reclaimed part. "GB" sits on the right, sharing the baseline with the bottom of the 8.
    let W = box.width
    // The single highlight color: bright lime, meaning "what you gain" (reclaimed RAM, headroom).
    let mint = headroomColor
    // The 8 is about 0.43 W tall. Loops are ellipses stretched sideways (widthScale) so the 8 looks sturdier;
    // the stroke stays even because the path is stretched before it is stroked.
    let stroke = W * 0.078
    let lowerRadius = W * 0.105, upperRadius = W * 0.088, widthScale: CGFloat = 1.15
    let eightWidth = 2 * lowerRadius * widthScale + stroke, gap8 = W * 0.045
    let gb = NSAttributedString(string: "GB", attributes: [
        .font: font(W * 0.34, .heavy), .foregroundColor: NSColor.white, .kern: -W * 0.012])
    let x8 = s / 2 - (eightWidth + gap8 + gb.size().width) / 2
    let bottom = box.minY + W * 0.30
    // The bottom of the 8 sits just above "VIBE"; GB keeps its own baseline.
    let lowerCenter = CGPoint(x: x8 + eightWidth / 2, y: box.minY + W * 0.28 + stroke / 2 + lowerRadius)
    let upperCenter = CGPoint(x: lowerCenter.x, y: lowerCenter.y + lowerRadius + upperRadius)

    /// Elliptical arc (angles in degrees, 0 is to the right) with round caps: a circle stretched by widthScale.
    func arc(_ c: CGPoint, _ r: CGFloat, _ from: CGFloat, _ to: CGFloat, clockwise: Bool, _ color: NSColor) {
        let p = NSBezierPath()
        p.appendArc(withCenter: .zero, radius: r, startAngle: from, endAngle: to, clockwise: clockwise)
        var t = AffineTransform(translationByX: c.x, byY: c.y)
        t.scale(x: widthScale, y: 1)
        p.transform(using: t)
        p.lineWidth = stroke; p.lineCapStyle = .round
        color.setStroke(); p.stroke()
    }
    /// Arrow head at the end of an arc, pointing along the direction of travel.
    func arrowHead(_ c: CGPoint, _ r: CGFloat, _ angle: CGFloat, clockwise: Bool, _ color: NSColor) {
        let a = angle * .pi / 180
        let rx = r * widthScale
        let tip = CGPoint(x: c.x + rx * cos(a), y: c.y + r * sin(a))
        // Tangent of the ellipse, normalized; the normal is perpendicular to it.
        let tx = clockwise ? rx * sin(a) : -rx * sin(a), ty = clockwise ? -r * cos(a) : r * cos(a)
        let len = max(0.0001, (tx * tx + ty * ty).squareRoot())
        let direction = CGPoint(x: tx / len, y: ty / len)
        let normal = CGPoint(x: direction.y, y: -direction.x)
        // Short triangle with rounded corners to match the rounded type.
        let length = min(stroke * 0.8, W * 0.06), halfWidth = min(stroke * 0.85, W * 0.065)
        let p = NSBezierPath()
        p.move(to: CGPoint(x: tip.x + direction.x * length, y: tip.y + direction.y * length))
        p.line(to: CGPoint(x: tip.x + normal.x * halfWidth, y: tip.y + normal.y * halfWidth))
        p.line(to: CGPoint(x: tip.x - normal.x * halfWidth, y: tip.y - normal.y * halfWidth))
        p.close()
        p.lineJoinStyle = .round; p.lineWidth = min(stroke * 0.45, W * 0.032)
        color.setFill(); color.setStroke(); p.fill(); p.stroke()
    }
    // Upper loop is solid and steady. The lower loop is a clock: faint track, a white hand running clockwise,
    // and a lime end with one rounded arrow: resources reclaimed and cycled back into use.
    arc(upperCenter, upperRadius, 0, 360, clockwise: false, .white)
    arc(lowerCenter, lowerRadius, 0, 360, clockwise: false, NSColor.white.withAlphaComponent(0.28))
    arc(lowerCenter, lowerRadius, 200, -20, clockwise: true, .white)
    arc(lowerCenter, lowerRadius, -20, -95, clockwise: true, mint)
    arrowHead(lowerCenter, lowerRadius, -95, clockwise: true, mint)
    gb.draw(at: CGPoint(x: x8 + eightWidth + gap8, y: bottom + font(W * 0.34, .heavy).descender))

    // "VIBE": small, tracked out, slightly transparent.
    let subtitle = NSAttributedString(string: "VIBE", attributes: [
        .font: font(box.width * 0.115, .semibold), .foregroundColor: NSColor.white.withAlphaComponent(0.78),
        .kern: box.width * 0.035])
    let subtitleSize = subtitle.size()
    subtitle.draw(at: CGPoint(x: s / 2 - subtitleSize.width / 2 + box.width * 0.017, y: box.minY + box.height * 0.165))

    // RAM bar on top: 8 cells, 6 bright and 2 mint ("headroom").
    let cellCount = 8, barWidth = box.width * 0.56, barHeight = box.width * 0.045, gap = box.width * 0.012
    let cellWidth = (barWidth - gap * CGFloat(cellCount - 1)) / CGFloat(cellCount)
    let x0 = s / 2 - barWidth / 2, y0 = box.minY + box.height * 0.815
    for i in 0..<cellCount {
        let cell = NSBezierPath(roundedRect: CGRect(x: x0 + CGFloat(i) * (cellWidth + gap), y: y0, width: cellWidth, height: barHeight),
                                xRadius: barHeight / 2, yRadius: barHeight / 2)
        (i < 6 ? NSColor.white.withAlphaComponent(0.85) : headroomColor).setFill()
        cell.fill()
    }

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
