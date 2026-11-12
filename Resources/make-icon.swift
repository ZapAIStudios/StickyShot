// Draws the app icon and writes Resources/AppIcon.icns. Run: swift Resources/make-icon.swift
import AppKit

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let tile = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let path = NSBezierPath(roundedRect: tile, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(starting: NSColor(red: 0.27, green: 0.45, blue: 1.0, alpha: 1),
               ending: NSColor(red: 0.55, green: 0.25, blue: 0.95, alpha: 1))!.draw(in: path, angle: -60)

    // A screenshot card pinned in the lower-right corner.
    let card = NSRect(x: s * 0.42, y: s * 0.2, width: s * 0.36, height: s * 0.26)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: card, xRadius: s * 0.03, yRadius: s * 0.03).fill()
    NSColor(white: 0.85, alpha: 1).setFill()
    NSBezierPath(roundedRect: card.insetBy(dx: s * 0.025, dy: s * 0.025), xRadius: s * 0.015, yRadius: s * 0.015).fill()

    if let symbol = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: s * 0.3, weight: .semibold)) {
        let tinted = NSImage(size: symbol.size, flipped: false) { r in
            symbol.draw(in: r); NSColor.white.set(); r.fill(using: .sourceAtop); return true
        }
        tinted.draw(in: NSRect(x: s * 0.2, y: s * 0.46, width: s * 0.36, height: s * 0.36 * symbol.size.height / symbol.size.width))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.iconset")
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: dir.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: dir.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
