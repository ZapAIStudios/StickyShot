// Draws StickyShot's Zap-branded artwork from the approved Zap brand kit.
// Usage: make-art <brand folder> <output folder>
// Writes AppIcon.iconset/, StickyShot-icon-1024.png and StickyShot-hero.png (2560×1280).
import AppKit

let brandDir = URL(fileURLWithPath: CommandLine.arguments[1])
let outDir = URL(fileURLWithPath: CommandLine.arguments[2])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// Brand colours (ZAP_BRAND_REFS.md)
func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(v >> 16 & 255) / 255, green: CGFloat(v >> 8 & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: a)
}
let zapBlue = hex(0x30B0FF)
let zapBlueDeep = hex(0x1C8FE0)
let cream = hex(0xFFFB96)
let ink = hex(0x0B1B2B)

// Fonts: Aeonik Bold for headlines; Aeonik Regular stands in for Geist, which isn't installed.
for name in ["Aeonik-Bold", "Aeonik-Medium", "Aeonik-Regular"] {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Fonts/\(name).otf")
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
}
func font(_ name: String, _ size: CGFloat) -> NSFont { NSFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: .bold) }

/// The Zap bolt, recoloured from the kit's old yellow (#FFE879) to Bolt Yellow (#FFFB96), outline kept black.
let bolt: CGImage = {
    let src = NSImage(contentsOf: brandDir.appendingPathComponent("bolt.png"))!
    var rect = CGRect(origin: .zero, size: src.size)
    let cg = src.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
    let w = cg.width, h = cg.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
    for i in stride(from: 0, to: w * h * 4, by: 4) {
        let a = CGFloat(p[i + 3]) / 255
        guard a > 0 else { continue }
        let t = min(1, CGFloat(p[i]) / 255 / a)   // 0 on the black outline, 1 inside the yellow fill
        p[i] = UInt8(255 * t * a); p[i + 1] = UInt8(251 * t * a); p[i + 2] = UInt8(150 * t * a)
    }
    return ctx.makeImage()!
}()
/// The bolt's bottom tip, as a fraction of the image (origin bottom-left), found from its pixels.
let boltTip: CGPoint = {
    let w = bolt.width, h = bolt.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(bolt, in: CGRect(x: 0, y: 0, width: w, height: h))
    let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
    // Bitmap context memory starts at the top row; walk up from the bottom row to the first opaque pixels.
    for row in stride(from: h - 1, through: 0, by: -1) {
        let xs = (0..<w).filter { p[(row * w + $0) * 4 + 3] > 100 }
        if !xs.isEmpty {
            return CGPoint(x: CGFloat(xs.reduce(0, +)) / CGFloat(xs.count) / CGFloat(w), y: 1 - CGFloat(row) / CGFloat(h))
        }
    }
    return CGPoint(x: 0.5, y: 0)
}()
let wordmark = NSImage(contentsOf: brandDir.appendingPathComponent("wordmark-yellow.png"))!

func render(_ w: Int, _ h: Int, _ draw: (CGFloat, CGFloat) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    g.imageInterpolation = .high
    NSGraphicsContext.current = g
    draw(CGFloat(w), CGFloat(h))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func save(_ rep: NSBitmapImageRep, _ url: URL) { try! rep.representation(using: .png, properties: [:])!.write(to: url) }

func shadow(_ blur: CGFloat, _ y: CGFloat, _ alpha: CGFloat) {
    let s = NSShadow()
    s.shadowBlurRadius = blur
    s.shadowOffset = NSSize(width: 0, height: -y)
    s.shadowColor = NSColor.black.withAlphaComponent(alpha)
    s.set()
}

func drawBolt(in r: NSRect, rotation: CGFloat = 0) {
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.translateBy(x: r.midX, y: r.midY)
    ctx.rotate(by: rotation * .pi / 180)
    let aspect = CGFloat(bolt.width) / CGFloat(bolt.height)
    let bh = r.height, bw = bh * aspect
    ctx.draw(bolt, in: CGRect(x: -bw / 2, y: -bh / 2, width: bw, height: bh))
    ctx.restoreGState()
}

/// A stand-in screenshot: a little window with a title bar and content bars (no real user content).
func drawScreenshotCard(_ r: NSRect, radius: CGFloat, dark: Bool, accent: NSColor, closeButton: Bool) {
    NSGraphicsContext.saveGraphicsState()
    shadow(r.width * 0.08, r.width * 0.03, 0.35)
    let card = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
    (dark ? hex(0x15202B) : .white).setFill()
    card.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    card.addClip()
    let u = r.width / 100
    // Title bar with traffic lights
    (dark ? hex(0x22303D) : hex(0xEEF3F8)).setFill()
    NSRect(x: r.minX, y: r.maxY - 11 * u, width: r.width, height: 11 * u).fill()
    for (i, c) in [hex(0xFF5F57), hex(0xFEBC2E), hex(0x28C840)].enumerated() {
        c.setFill()
        NSBezierPath(ovalIn: NSRect(x: r.minX + (5 + CGFloat(i) * 5) * u, y: r.maxY - 7.3 * u, width: 3.4 * u, height: 3.4 * u)).fill()
    }
    // Content: a hero block and text lines
    accent.setFill()
    NSBezierPath(roundedRect: NSRect(x: r.minX + 6 * u, y: r.maxY - 11 * u - 28 * u, width: 50 * u, height: 22 * u), xRadius: 2 * u, yRadius: 2 * u).fill()
    let line = dark ? hex(0x3A4B5C) : hex(0xD8E2EC)
    line.setFill()
    for (i, len) in [80, 64, 72, 40].enumerated() {
        let y = r.maxY - 11 * u - 36 * u - CGFloat(i) * 7.5 * u
        if y < r.minY + 4 * u { break }
        NSBezierPath(roundedRect: NSRect(x: r.minX + 6 * u, y: y, width: CGFloat(len) * u * 0.88, height: 3.4 * u), xRadius: 1.7 * u, yRadius: 1.7 * u).fill()
    }
    hex(0xFFFFFF, 0.12).setFill()
    NSRect(x: r.minX + 62 * u, y: r.maxY - 11 * u - 28 * u, width: 32 * u, height: 22 * u).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Border
    hex(0xFFFFFF, 0.5).setStroke()
    card.lineWidth = max(1, r.width * 0.006)
    card.stroke()

    if closeButton {
        let d = r.width * 0.11
        let c = NSRect(x: r.minX + r.width * 0.035, y: r.maxY - r.width * 0.035 - d, width: d, height: d)
        (dark ? NSColor.white : NSColor.black).withAlphaComponent(0.85).setFill()
        NSBezierPath(ovalIn: c).fill()
        let x = NSBezierPath()
        let k = d * 0.28
        x.move(to: NSPoint(x: c.midX - k, y: c.midY - k)); x.line(to: NSPoint(x: c.midX + k, y: c.midY + k))
        x.move(to: NSPoint(x: c.midX - k, y: c.midY + k)); x.line(to: NSPoint(x: c.midX + k, y: c.midY - k))
        x.lineWidth = d * 0.13
        x.lineCapStyle = .round
        (dark ? NSColor.black : NSColor.white).setStroke()
        x.stroke()
    }
}

// MARK: App icon

func drawIcon(_ s: CGFloat) {
    // macOS icon grid: 824/1024 tile, ~185 radius
    let tile = NSRect(x: s * 0.098, y: s * 0.098, width: s * 0.804, height: s * 0.804)
    let path = NSBezierPath(roundedRect: tile, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGraphicsContext.saveGraphicsState()
    shadow(s * 0.02, s * 0.01, 0.3)
    zapBlue.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGradient(colors: [hex(0x5CC4FF), zapBlue, zapBlueDeep])!.draw(in: tile, angle: -70)

    // The screenshot card, sitting in the lower right like a preview
    // Everything sits on the tile's centre line: ZAP on top, the bolt, then the screenshot it strikes
    let card = NSRect(x: s * 0.255, y: s * 0.17, width: s * 0.49, height: s * 0.33)
    drawScreenshotCard(card, radius: s * 0.035, dark: false, accent: zapBlue.withAlphaComponent(0.85), closeButton: false)

    // Impact sparks where the bolt strikes the top of the card
    let hit = NSPoint(x: card.midX, y: card.maxY)  // the bolt's tip lands on the card's top centre
    let sparks = NSBezierPath()
    // Mirrored pairs, evenly either side of the strike
    for (angle, inner, outer) in [(168.0, 0.055, 0.115), (12.0, 0.055, 0.115), (138.0, 0.065, 0.115), (42.0, 0.065, 0.115)] {
        let a = angle * .pi / 180
        sparks.move(to: NSPoint(x: hit.x + cos(a) * s * inner, y: hit.y + sin(a) * s * inner))
        sparks.line(to: NSPoint(x: hit.x + cos(a) * s * outer, y: hit.y + sin(a) * s * outer))
    }
    sparks.lineWidth = s * 0.018
    sparks.lineCapStyle = .round
    cream.setStroke()
    sparks.stroke()

    // The ZAP wordmark up top, firing its bolt down into the screenshot
    let wmW = s * 0.44
    let wmH = wmW * wordmark.size.height / wordmark.size.width
    NSGraphicsContext.saveGraphicsState()
    shadow(s * 0.015, s * 0.008, 0.3)
    wordmark.draw(in: NSRect(x: (s - wmW) / 2, y: s * 0.715, width: wmW, height: wmH))
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shadow(s * 0.02, s * 0.01, 0.4)
    // Stand the bolt more upright and place it so its tip just touches the card's top edge
    let rot: CGFloat = 22, bh = s * 0.18, bw = bh * CGFloat(bolt.width) / CGFloat(bolt.height)
    let ox = (boltTip.x - 0.5) * bw, oy = (boltTip.y - 0.5) * bh
    let a = rot * .pi / 180
    let cx = hit.x - (ox * cos(a) - oy * sin(a)), cy = hit.y - (ox * sin(a) + oy * cos(a))
    drawBolt(in: NSRect(x: cx - bw / 2, y: cy - bh / 2, width: bw, height: bh), rotation: rot)
    NSGraphicsContext.restoreGraphicsState()
}

/// The app icon: small ZAP bug top left, the StickyShot name centred, the screenshot card below. No bolt or sparks.
func drawAppIcon(_ s: CGFloat) {
    let tile = NSRect(x: s * 0.098, y: s * 0.098, width: s * 0.804, height: s * 0.804)
    let path = NSBezierPath(roundedRect: tile, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGraphicsContext.saveGraphicsState()
    shadow(s * 0.02, s * 0.01, 0.3)
    zapBlue.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGradient(colors: [hex(0x5CC4FF), zapBlue, zapBlueDeep])!.draw(in: tile, angle: -70)

    // Golden-ratio layout. φ sets the type widths and every vertical gap.
    let phi: CGFloat = 1.618
    let card = NSRect(x: s * 0.255, y: s * 0.17, width: s * 0.49, height: s * 0.33)

    // ZAP bug, top left, inset from the tile corner by the same margin on both sides
    let inset = s * 0.077
    let bugW = s * 0.12
    let bugH = bugW * wordmark.size.height / wordmark.size.width
    let bug = NSRect(x: tile.minX + inset, y: tile.maxY - inset - bugH, width: bugW, height: bugH)
    wordmark.draw(in: bug)

    // Fit a line of text to an exact ink width; returns it with its ink bounds at size 1 scaled up.
    func fitted(_ text: String, _ fontName: String, _ color: NSColor, width: CGFloat, kern: CGFloat) -> (NSAttributedString, CGRect) {
        func make(_ size: CGFloat) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [.font: font(fontName, size), .foregroundColor: color, .kern: kern * size])
        }
        let probe = CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(make(100)), .useGlyphPathBounds)
        let size = 100 * width / probe.width
        let str = make(size)
        return (str, CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(str), .useGlyphPathBounds))
    }
    // Headline spans the card's width; the tagline is the headline less 1/φ⁴ (about 85%)
    let headW = card.width * 1.3
    let (title, tb) = fitted("StickyShot", "Aeonik-Bold", cream, width: headW, kern: -0.02)
    let (tagline, gb) = fitted("Screenshots that stick around.", "Aeonik-Medium", .white, width: headW * (1 - pow(1 / phi, 4)), kern: 0)

    // Gaps measured ink to ink: tagline↔headline = g, headline↔ZAP and card↔tagline = g·φ
    let room = bug.minY - card.maxY - tb.height - gb.height
    let g = room / (1 + 2 * phi)
    let tagBottom = card.maxY + g * phi
    let headBottom = tagBottom + gb.height + g

    // Draw each line from its baseline so the ink lands exactly where the gaps say
    func drawLine(_ str: NSAttributedString, _ b: CGRect, inkBottom: CGFloat) {
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: (s - b.width) / 2 - b.minX, y: inkBottom - b.minY)
        CTLineDraw(CTLineCreateWithAttributedString(str), ctx)
    }
    NSGraphicsContext.saveGraphicsState()
    shadow(s * 0.015, s * 0.008, 0.25)
    drawLine(title, tb, inkBottom: headBottom)
    NSGraphicsContext.restoreGraphicsState()
    drawLine(tagline, gb, inkBottom: tagBottom)

    // The screenshot card
    drawScreenshotCard(card, radius: s * 0.035, dark: false, accent: zapBlue.withAlphaComponent(0.85), closeButton: false)
    NSGraphicsContext.restoreGraphicsState()
}

let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    save(render(base, base) { s, _ in drawAppIcon(s) }, iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    save(render(base * 2, base * 2) { s, _ in drawAppIcon(s) }, iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
save(render(1024, 1024) { s, _ in drawAppIcon(s) }, outDir.appendingPathComponent("StickyShot-icon-1024.png"))

// MARK: Hero image (2:1, for the GitHub page and social cards)

save(render(2560, 1280) { W, H in
    NSGradient(colors: [hex(0x47BCFF), zapBlue, zapBlueDeep])!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -35)

    // Faint oversized bolt as texture
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current!.cgContext.setAlpha(0.07)
    drawBolt(in: NSRect(x: W * 0.36, y: -H * 0.25, width: W * 0.5, height: H * 1.5), rotation: 8)
    NSGraphicsContext.restoreGraphicsState()

    // Left: icon and name on one row, the pitch, then the benefits
    let left = W * 0.065
    let iconSize = H * 0.19
    let icon = render(Int(iconSize * 2), Int(iconSize * 2)) { s, _ in drawAppIcon(s) }
    icon.draw(in: NSRect(x: left - iconSize * 0.1, y: H * 0.755, width: iconSize, height: iconSize), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)

    let title = NSAttributedString(string: "StickyShot", attributes: [.font: font("Aeonik-Bold", H * 0.125), .foregroundColor: cream, .kern: -H * 0.003])
    title.draw(at: NSPoint(x: left + iconSize * 0.95, y: H * 0.765))

    let pitch = NSAttributedString(string: "Your Mac screenshot preview, kept on screen until you close it.",
                                   attributes: [.font: font("Aeonik-Medium", H * 0.034), .foregroundColor: NSColor.white])
    pitch.draw(at: NSPoint(x: left, y: H * 0.675))

    let benefits = [
        "Stays up until you close it, or on a timer you choose",
        "Take several and they stack neatly in the corner",
        "Drag into Mail, Slack or Messages, and it stays put",
        "Click to open, right-click to copy, find or trash",
        "Pops up the instant you take the shot",
        "Free and private: no account, never goes online",
    ]
    let rowH = H * 0.067
    for (i, text) in benefits.enumerated() {
        let y = H * 0.575 - CGFloat(i) * rowH
        drawBolt(in: NSRect(x: left, y: y - H * 0.004, width: H * 0.035, height: H * 0.046), rotation: 0)
        NSAttributedString(string: text, attributes: [.font: font("Aeonik-Regular", H * 0.036), .foregroundColor: NSColor.white])
            .draw(at: NSPoint(x: left + H * 0.06, y: y))
    }

    // Free tag + credit line
    let tagText = NSAttributedString(string: "FREE FOR MAC", attributes: [.font: font("Aeonik-Medium", H * 0.026), .foregroundColor: ink, .kern: H * 0.004])
    let tagSize = tagText.size()
    let tag = NSRect(x: left, y: H * 0.075, width: tagSize.width + H * 0.05, height: tagSize.height + H * 0.022)
    cream.setFill()
    NSBezierPath(roundedRect: tag, xRadius: tag.height / 2, yRadius: tag.height / 2).fill()
    tagText.draw(at: NSPoint(x: tag.minX + H * 0.025, y: tag.minY + H * 0.011))

    let by = NSAttributedString(string: "by", attributes: [.font: font("Aeonik-Regular", H * 0.03), .foregroundColor: NSColor.white.withAlphaComponent(0.9)])
    let byX = tag.maxX + H * 0.04
    by.draw(at: NSPoint(x: byX, y: tag.minY + H * 0.008))
    let wmH = tag.height * 0.78
    let wmW = wmH * wordmark.size.width / wordmark.size.height
    wordmark.draw(in: NSRect(x: byX + by.size().width + H * 0.016, y: tag.midY - wmH / 2, width: wmW, height: wmH))
    let site = NSAttributedString(string: "getzapped.xyz", attributes: [.font: font("Aeonik-Medium", H * 0.03), .foregroundColor: NSColor.white.withAlphaComponent(0.9)])
    site.draw(at: NSPoint(x: byX + by.size().width + H * 0.016 + wmW + H * 0.03, y: tag.minY + H * 0.008))

    // Right: a Mac desktop with StickyShot's menu open and previews stacked, newest at the bottom
    let screen = NSRect(x: W * 0.595, y: H * 0.075, width: W * 0.378, height: H * 0.85)
    NSGraphicsContext.saveGraphicsState()
    shadow(H * 0.05, H * 0.02, 0.35)
    let screenPath = NSBezierPath(roundedRect: screen, xRadius: H * 0.03, yRadius: H * 0.03)
    hex(0x0E2233).setFill()
    screenPath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    screenPath.addClip()
    // Wallpaper: deep blue with soft light
    NSGradient(colors: [hex(0x1E5A8C), hex(0x123A5C), hex(0x0B1B2B)])!.draw(in: screen, angle: -60)
    NSGradient(colors: [hex(0x30B0FF, 0.35), hex(0x30B0FF, 0)])!.draw(in: NSBezierPath(ovalIn: NSRect(x: screen.minX - screen.width * 0.3, y: screen.minY - screen.height * 0.2, width: screen.width, height: screen.height * 0.8)), relativeCenterPosition: .zero)

    func symbol(_ name: String, _ size: CGFloat, _ color: NSColor) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .medium).applying(.init(paletteColors: [color])))
    }
    func text(_ s: String, _ size: CGFloat, _ color: NSColor, bold: Bool = false) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular), .foregroundColor: color])
    }

    // Menu bar
    let barH = H * 0.04
    let bar = NSRect(x: screen.minX, y: screen.maxY - barH, width: screen.width, height: barH)
    hex(0x000000, 0.28).setFill()
    bar.fill()
    let barFont = barH * 0.42
    var bx = screen.minX + H * 0.03
    for (i, item) in ["Finder", "File", "Edit", "View", "Go"].enumerated() {
        let t = text(item, barFont, .white, bold: i == 0)
        t.draw(at: NSPoint(x: bx, y: bar.midY - t.size().height / 2))
        bx += t.size().width + barH * 0.55
    }
    let clock = text("Thu 9:41 AM", barFont, .white)
    var rx = bar.maxX - H * 0.03 - clock.size().width
    clock.draw(at: NSPoint(x: rx, y: bar.midY - clock.size().height / 2))
    for name in ["wifi", "battery.75percent"] {
        if let img = symbol(name, barFont, .white) {
            rx -= img.size.width + barH * 0.5
            img.draw(in: NSRect(x: rx, y: bar.midY - img.size.height / 2, width: img.size.width, height: img.size.height))
        }
    }
    // StickyShot's icon, highlighted because its menu is open
    let iconBox = NSRect(x: rx - barH * 1.45, y: bar.minY + barH * 0.1, width: barH * 1.15, height: barH * 0.8)
    hex(0xFFFFFF, 0.25).setFill()
    NSBezierPath(roundedRect: iconBox, xRadius: barH * 0.18, yRadius: barH * 0.18).fill()
    if let img = symbol("camera.viewfinder", barFont * 1.05, .white) {
        img.draw(in: NSRect(x: iconBox.midX - img.size.width / 2, y: iconBox.midY - img.size.height / 2, width: img.size.width, height: img.size.height))
    }

    // The open menu, with StickyShot's real items
    let rowH2 = H * 0.034, sepH = H * 0.014, menuFont = rowH2 * 0.46
    let items: [(String, Bool, Bool, Bool)] = [  // title, checked, submenu, dimmed; "-" is a separator
        ("Keep Previews On Screen", true, false, false), ("Close Previews Automatically", false, true, false),
        ("Close All Previews", false, false, false), ("-", false, false, false),
        ("Watching: Screenshots", false, false, true), ("Open Screenshots Folder", false, false, false),
        ("Start at Login", true, false, false), ("-", false, false, false), ("Quit StickyShot", false, false, false),
    ]
    let menuW = screen.width * 0.47
    let menuH = items.reduce(H * 0.016) { $0 + ($1.0 == "-" ? sepH : rowH2) }
    // Like macOS, the menu slides left when it would run off the screen edge
    let menu = NSRect(x: min(iconBox.minX, screen.maxX - H * 0.025 - menuW), y:bar.minY - H * 0.006 - menuH, width: menuW, height: menuH)
    NSGraphicsContext.saveGraphicsState()
    shadow(H * 0.03, H * 0.012, 0.45)
    let menuPath = NSBezierPath(roundedRect: menu, xRadius: H * 0.014, yRadius: H * 0.014)
    hex(0x2A2F36, 0.97).setFill()
    menuPath.fill()
    NSGraphicsContext.restoreGraphicsState()
    hex(0xFFFFFF, 0.18).setStroke()
    menuPath.lineWidth = 1.5
    menuPath.stroke()
    var my = menu.maxY - H * 0.008
    var hoverRow = NSRect.zero
    for (i, (title, checked, sub, dim)) in items.enumerated() {
        if title == "-" {
            my -= sepH
            hex(0xFFFFFF, 0.15).setFill()
            NSRect(x: menu.minX + H * 0.014, y: my + sepH / 2, width: menu.width - H * 0.028, height: 1.5).fill()
            continue
        }
        my -= rowH2
        let row = NSRect(x: menu.minX + H * 0.006, y: my, width: menu.width - H * 0.012, height: rowH2)
        if i == 0 {  // the item under the pointer
            hoverRow = row
            zapBlue.setFill()
            NSBezierPath(roundedRect: row, xRadius: H * 0.008, yRadius: H * 0.008).fill()
        }
        let color = dim ? hex(0xFFFFFF, 0.4) : .white
        if checked {
            let c = text("✓", menuFont, color, bold: true)
            c.draw(at: NSPoint(x: row.minX + H * 0.012, y: row.midY - c.size().height / 2))
        }
        let t = text(title, menuFont, color)
        t.draw(at: NSPoint(x: row.minX + H * 0.04, y: row.midY - t.size().height / 2))
        if sub {
            let c = text("›", menuFont * 1.3, color, bold: true)
            c.draw(at: NSPoint(x: row.maxX - H * 0.028, y: row.midY - c.size().height / 2))
        }
    }

    // Previews stacked in the lower right, newest at the bottom
    let cw = screen.width * 0.28, gap = H * 0.02, margin = H * 0.03
    var y = screen.minY + margin
    let cards: [(CGFloat, Bool, NSColor, Bool)] = [(0.64, false, zapBlue, true), (0.6, true, cream, false), (0.62, false, hex(0xFF8A65), false)]
    for (ratio, dark, accent, hovered) in cards {
        let ch = cw * ratio
        drawScreenshotCard(NSRect(x: screen.maxX - cw - margin, y: y, width: cw, height: ch), radius: H * 0.012,
                           dark: dark, accent: accent, closeButton: hovered)
        y += ch + gap
    }
    NSGraphicsContext.restoreGraphicsState()

    // Pointer on the menu's top item
    if let arrow = NSCursor.arrow.image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        let a = H * 0.06
        NSGraphicsContext.current!.cgContext.draw(arrow, in: CGRect(x: hoverRow.minX + hoverRow.width * 0.55, y: hoverRow.midY - a * 0.85, width: a * 0.7, height: a))
    }
}, outDir.appendingPathComponent("StickyShot-hero.png"))
print("done")
