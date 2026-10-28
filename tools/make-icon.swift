// Renders the Happy Mama app icon. Usage: swift tools/make-icon.swift <output-dir>
// Produces icon_ios_1024.png (full-bleed, iOS masks it) and icon_mac_1024.png
// (rounded square with margin and shadow, per macOS convention).
import AppKit

let coralTop = NSColor(red: 1.00, green: 0.62, blue: 0.42, alpha: 1)
let coralBottom = NSColor(red: 0.90, green: 0.25, blue: 0.36, alpha: 1)
let gold = NSColor(red: 1.00, green: 0.80, blue: 0.30, alpha: 1)

func heartPath(in r: NSRect) -> NSBezierPath {
    let p = NSBezierPath()
    let w = r.width, h = r.height, x = r.minX, y = r.minY
    p.move(to: NSPoint(x: x + w * 0.5, y: y))
    p.curve(to: NSPoint(x: x, y: y + h * 0.66),
            controlPoint1: NSPoint(x: x + w * 0.18, y: y + h * 0.18),
            controlPoint2: NSPoint(x: x, y: y + h * 0.42))
    p.curve(to: NSPoint(x: x + w * 0.5, y: y + h * 0.80),
            controlPoint1: NSPoint(x: x, y: y + h * 0.92),
            controlPoint2: NSPoint(x: x + w * 0.38, y: y + h * 1.0))
    p.curve(to: NSPoint(x: x + w, y: y + h * 0.66),
            controlPoint1: NSPoint(x: x + w * 0.62, y: y + h * 1.0),
            controlPoint2: NSPoint(x: x + w, y: y + h * 0.92))
    p.curve(to: NSPoint(x: x + w * 0.5, y: y),
            controlPoint1: NSPoint(x: x + w, y: y + h * 0.42),
            controlPoint2: NSPoint(x: x + w * 0.82, y: y + h * 0.18))
    p.close()
    return p
}

func sparkle(at c: NSPoint, radius r: CGFloat, color: NSColor) {
    let p = NSBezierPath()
    for i in 0..<8 {
        let a = CGFloat(i) * .pi / 4 + .pi / 2
        let rad = i % 2 == 0 ? r : r * 0.22
        let pt = NSPoint(x: c.x + cos(a) * rad, y: c.y + sin(a) * rad)
        i == 0 ? p.move(to: pt) : p.line(to: pt)
    }
    p.close()
    color.setFill()
    p.fill()
}

/// Draws the artwork into `rect` (the icon's visible area).
func drawArt(in rect: NSRect) {
    let s = rect.width
    NSGradient(starting: coralTop, ending: coralBottom)!.draw(in: rect, angle: -75)

    // Soft sunburst glow behind the heart.
    let glow = NSGradient(colors: [NSColor.white.withAlphaComponent(0.35), NSColor.white.withAlphaComponent(0)])!
    glow.draw(fromCenter: NSPoint(x: rect.midX, y: rect.midY + s * 0.04), radius: 0,
              toCenter: NSPoint(x: rect.midX, y: rect.midY + s * 0.04), radius: s * 0.52, options: [])

    // Heart with drop shadow.
    let heartRect = NSRect(x: rect.minX + s * 0.17, y: rect.minY + s * 0.19, width: s * 0.66, height: s * 0.62)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(red: 0.5, green: 0.05, blue: 0.15, alpha: 0.38)
    shadow.shadowBlurRadius = s * 0.035
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.02)
    shadow.set()
    NSColor.white.setFill()
    heartPath(in: heartRect).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Chunky checkmark: gold-to-coral, with a subtle shadow so it reads at small sizes.
    let check = NSBezierPath()
    check.move(to: NSPoint(x: rect.minX + s * 0.355, y: rect.minY + s * 0.505))
    check.line(to: NSPoint(x: rect.minX + s * 0.46, y: rect.minY + s * 0.395))
    check.line(to: NSPoint(x: rect.minX + s * 0.665, y: rect.minY + s * 0.625))
    check.lineWidth = s * 0.085
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    NSGraphicsContext.saveGraphicsState()
    check.addClip() // no-op for stroke; use stroked outline below
    NSGraphicsContext.restoreGraphicsState()
    NSColor(red: 0.93, green: 0.30, blue: 0.36, alpha: 1).setStroke()
    check.stroke()
    let highlight = NSBezierPath()
    highlight.append(check)
    highlight.lineWidth = s * 0.035
    highlight.lineCapStyle = .round
    highlight.lineJoinStyle = .round
    gold.withAlphaComponent(0.9).setStroke()
    highlight.stroke()

    // Sparkles.
    sparkle(at: NSPoint(x: rect.minX + s * 0.80, y: rect.minY + s * 0.82), radius: s * 0.075, color: .white)
    sparkle(at: NSPoint(x: rect.minX + s * 0.22, y: rect.minY + s * 0.78), radius: s * 0.045, color: gold)
    sparkle(at: NSPoint(x: rect.minX + s * 0.86, y: rect.minY + s * 0.62), radius: s * 0.03, color: .white.withAlphaComponent(0.85))
}

func render(_ path: String, _ draw: () -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 1024, height: 1024)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

// iOS: full-bleed square; the system applies the corner mask.
render("\(out)/icon_ios_1024.png") { drawArt(in: NSRect(x: 0, y: 0, width: 1024, height: 1024)) }

// macOS: 824pt rounded square centered in the canvas with a soft shadow.
render("\(out)/icon_mac_1024.png") {
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    drawArt(in: body)
    NSGraphicsContext.restoreGraphicsState()
}
