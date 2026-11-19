// Draws the app icon into an .iconset folder. Usage: swift make_icon.swift <out.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func arrow(in r: NSRect, up: Bool) -> NSBezierPath {
    let p = NSBezierPath()
    let shaft = r.width * 0.36
    let head = r.height * 0.42
    let (tip, base): (CGFloat, CGFloat) = up ? (r.maxY, r.maxY - head) : (r.minY, r.minY + head)
    let tail: CGFloat = up ? r.minY : r.maxY
    p.move(to: NSPoint(x: r.midX, y: tip))
    p.line(to: NSPoint(x: r.maxX, y: base))
    p.line(to: NSPoint(x: r.midX + shaft / 2, y: base))
    p.line(to: NSPoint(x: r.midX + shaft / 2, y: tail))
    p.line(to: NSPoint(x: r.midX - shaft / 2, y: tail))
    p.line(to: NSPoint(x: r.midX - shaft / 2, y: base))
    p.line(to: NSPoint(x: r.minX, y: base))
    p.close()
    return p
}

func draw(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Apple's grid leaves about 10% margin around the body
    let body = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let shape = NSBezierPath(roundedRect: body, xRadius: s * 0.18, yRadius: s * 0.18)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.shadowBlurRadius = s * 0.03
    shadow.set()
    NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.17, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(
        starting: NSColor(calibratedRed: 0.24, green: 0.26, blue: 0.30, alpha: 1),
        ending: NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.13, alpha: 1)
    )!.draw(in: body, angle: -90)

    // Yellow dashed center line, like a road
    let dashW = s * 0.028, dashH = s * 0.075, gap = s * 0.05
    NSColor(calibratedRed: 1.0, green: 0.80, blue: 0.18, alpha: 1).setFill()
    var y = body.minY - dashH / 2
    while y < body.maxY {
        NSBezierPath(roundedRect: NSRect(x: body.midX - dashW / 2, y: y, width: dashW, height: dashH),
                     xRadius: dashW / 2, yRadius: dashW / 2).fill()
        y += dashH + gap
    }

    let lane = NSSize(width: body.width * 0.3, height: body.height * 0.62)
    let left = NSRect(x: body.minX + body.width * 0.1, y: body.midY - lane.height / 2, width: lane.width, height: lane.height)
    let right = left.offsetBy(dx: body.width * 0.5, dy: 0)
    NSColor.systemGreen.setFill()
    arrow(in: left, up: true).fill()
    NSColor.systemBlue.setFill()
    arrow(in: right, up: false).fill()

    // Soft top shine
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.10), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try draw(size: base * scale).write(to: out.appendingPathComponent(name))
    }
}
