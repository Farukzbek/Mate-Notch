// Mate Notch ikonu: indigo-mor zemin, tepeden sarkan siyah notch içinde gülen yüz.
// swift tools/make-icon.swift Resources/AppIcon.iconset
import AppKit

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px), m = s * 0.1
    let tile = NSRect(x: m, y: m, width: s - 2 * m, height: s - 2 * m)
    let shape = NSBezierPath(roundedRect: tile, xRadius: s * 0.18, yRadius: s * 0.18)

    // Zemin
    NSGradient(colors: [NSColor(red: 0.42, green: 0.55, blue: 1.00, alpha: 1),
                        NSColor(red: 0.50, green: 0.24, blue: 0.90, alpha: 1)])!.draw(in: shape, angle: -60)

    // Karo içine kırp: notch yalnızca alt köşeleriyle görünsün (üst kenardan sarkar)
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()

    let nw = tile.width * 0.60, nh = tile.height * 0.50
    let nx = tile.midX - nw / 2
    let ny = tile.maxY - nh                                   // alt kenar
    let notch = NSBezierPath(roundedRect: NSRect(x: nx, y: ny, width: nw, height: nh + s * 0.2),
                             xRadius: s * 0.12, yRadius: s * 0.12)
    NSColor(white: 0.04, alpha: 1).setFill()
    notch.fill()
    // ince üst-ışık
    NSColor(white: 1, alpha: 0.10).setStroke()
    let rim = NSBezierPath(roundedRect: NSRect(x: nx + s * 0.004, y: ny + s * 0.004, width: nw - s * 0.008, height: nh + s * 0.2),
                           xRadius: s * 0.12, yRadius: s * 0.12)
    rim.lineWidth = max(1, s * 0.006); rim.stroke()

    // Gülen yüz (notch'un görünen kısmının ortasında)
    let cx = tile.midX, cy = ny + nh * 0.52
    NSColor.white.setFill()
    let ew = s * 0.050, eh = s * 0.082
    for dx in [-s * 0.095, s * 0.095 - ew] {
        NSBezierPath(ovalIn: NSRect(x: cx + dx, y: cy + s * 0.030, width: ew, height: eh)).fill()
    }
    let smile = NSBezierPath()
    smile.lineWidth = s * 0.030
    smile.lineCapStyle = .round
    NSColor.white.setStroke()
    smile.move(to: NSPoint(x: cx - s * 0.115, y: cy - s * 0.045))
    smile.curve(to: NSPoint(x: cx + s * 0.115, y: cy - s * 0.045),
                controlPoint1: NSPoint(x: cx - s * 0.075, y: cy - s * 0.155),
                controlPoint2: NSPoint(x: cx + s * 0.075, y: cy - s * 0.155))
    smile.stroke()

    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! draw(px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
