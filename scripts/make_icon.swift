import AppKit

// A browser globe with a folded navigation ribbon, on the standard macOS icon grid.
// Keep this vector source reproducible; every AppIcon resolution is rendered from it.
let size: CGFloat = 1024

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func squircle(_ rect: NSRect, exponent n: CGFloat = 5) -> NSBezierPath {
    let path = NSBezierPath()
    let a = rect.width / 2, b = rect.height / 2
    for i in 0...720 {
        let t = CGFloat(i) / 720 * 2 * .pi
        let c = cos(t), s = sin(t)
        let point = NSPoint(x: rect.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n),
                            y: rect.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n))
        i == 0 ? path.move(to: point) : path.line(to: point)
    }
    path.close()
    return path
}

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    let tile = squircle(NSRect(x: 100, y: 100, width: 824, height: 824))
    NSGraphicsContext.saveGraphicsState()
    let tileShadow = NSShadow()
    tileShadow.shadowColor = color(0x17375C, alpha: 0.18)
    tileShadow.shadowBlurRadius = 18
    tileShadow.shadowOffset = NSSize(width: 0, height: -8)
    tileShadow.set()
    color(0xEAF2FA).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0xD9E7F7), color(0xFFFFFF)])!.draw(in: tile, angle: 90)

    // The circular silhouette and latitude lines read as a browser even at Dock size.
    let globe = NSBezierPath(ovalIn: NSRect(x: 194, y: 194, width: 636, height: 636))
    NSGraphicsContext.saveGraphicsState()
    let globeShadow = NSShadow()
    globeShadow.shadowColor = color(0x1552A0, alpha: 0.3)
    globeShadow.shadowBlurRadius = 26
    globeShadow.shadowOffset = NSSize(width: 0, height: -12)
    globeShadow.set()
    color(0x2367D5).setFill()
    globe.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0x183BA6), color(0x237CE4), color(0x49D9D0)])!.draw(in: globe, angle: 72)

    NSGraphicsContext.saveGraphicsState()
    globe.addClip()
    let longitude = NSBezierPath(ovalIn: NSRect(x: 337, y: 184, width: 350, height: 656))
    longitude.lineWidth = 12
    color(0xE2FFFF, alpha: 0.21).setStroke()
    longitude.stroke()
    for y: CGFloat in [346, 644] {
        let latitude = NSBezierPath()
        latitude.move(to: NSPoint(x: 194, y: y))
        latitude.curve(to: NSPoint(x: 830, y: y),
                       controlPoint1: NSPoint(x: 374, y: y - 64),
                       controlPoint2: NSPoint(x: 650, y: y - 64))
        latitude.lineWidth = 12
        latitude.stroke()
    }

    // A broad sweep gives the globe a sense of travel without copying another browser's mark.
    let sweep = NSBezierPath()
    sweep.move(to: NSPoint(x: 146, y: 410))
    sweep.curve(to: NSPoint(x: 872, y: 546),
                controlPoint1: NSPoint(x: 282, y: 150), controlPoint2: NSPoint(x: 714, y: 240))
    sweep.lineWidth = 62
    sweep.lineCapStyle = .round
    color(0x5CE8D0, alpha: 0.9).setStroke()
    sweep.stroke()

    // The white folded Z remains recognizable while the globe becomes the primary silhouette.
    let ribbon = NSBezierPath()
    ribbon.move(to: NSPoint(x: 368, y: 640))
    ribbon.line(to: NSPoint(x: 659, y: 640))
    ribbon.line(to: NSPoint(x: 371, y: 392))
    ribbon.line(to: NSPoint(x: 662, y: 392))
    ribbon.lineWidth = 62
    ribbon.lineCapStyle = .round
    ribbon.lineJoinStyle = .round
    let ribbonShadow = NSShadow()
    ribbonShadow.shadowColor = color(0x183BA6, alpha: 0.23)
    ribbonShadow.shadowBlurRadius = 12
    ribbonShadow.shadowOffset = NSSize(width: 0, height: -5)
    ribbonShadow.set()
    color(0xFFFFFF).setStroke()
    ribbon.stroke()
    NSGraphicsContext.restoreGraphicsState()

    globe.lineWidth = 3
    color(0xFFFFFF, alpha: 0.3).setStroke()
    globe.stroke()
    return true
}

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift scripts/make_icon.swift <AppIcon.appiconset directory>")
}
let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
for px in [16, 32, 64, 128, 256, 512, 1024] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("icon_\(px).png"))
}
