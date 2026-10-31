// Renders the GitHub social preview (1280×640) and a square avatar from the app's artwork.
// Usage: swift scripts/make-social-images.swift
// Writes docs/images/social-preview.png and docs/images/avatar.png. Upload them on GitHub by hand:
// Settings → Social preview, and the organisation's profile picture.
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
func path(_ relative: String) -> String { root.appendingPathComponent(relative).path }

guard let guineaPig = NSImage(contentsOfFile: path("Resources/Icon/guinea-pig-3d.png")),
      let icon = NSImage(contentsOfFile: path("docs/images/icon.png")),
      let screenshot = NSImage(contentsOfFile: path("docs/images/sweep-results.png"))
else { fatalError("Missing artwork in Resources/Icon or docs/images") }

func rgb(_ hex: UInt32) -> NSColor {
    NSColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

/// Background for the social preview: chosen to contrast with the blue app and icon.
/// `swift scripts/make-social-images.swift <style> [output]` renders another style for comparison.
struct Style {
    let top: NSColor, bottom: NSColor, glow: NSColor
    let text: NSColor
}
let styles: [String: Style] = [
    // Pink behind the text for contrast, orange behind the app.
    "sunset": Style(top: rgb(0xE8457A), bottom: rgb(0xFFB25B), glow: rgb(0xB8235F), text: .white),
    "graphite": Style(top: rgb(0x23232B), bottom: rgb(0x0C0C10), glow: rgb(0x7B5CFF), text: .white),
    "light": Style(top: rgb(0xFFF6EA), bottom: rgb(0xF3E3FF), glow: rgb(0xFFFFFF), text: rgb(0x1F1A2E)),
]
let styleName = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "sunset"
let style = styles[styleName] ?? styles["sunset"]!

// Sweep's blue, as used in the app (avatar background).
let blueTop = rgb(0x4B1FB0)
let blueBottom = rgb(0x0A39A6)
let blueGlow = rgb(0x3F7BFF)

func render(width: Int, height: Int, to output: String, draw: (NSRect) -> Void) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(NSRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
    print("Wrote \(output)")
}

func background(_ rect: NSRect, top: NSColor, bottom: NSColor, glow: NSColor) {
    NSGradient(starting: top, ending: bottom)!.draw(in: rect, angle: -35)
    // Soft glow towards the bottom left, like the app's windows.
    NSGradient(colors: [glow.withAlphaComponent(0.45), glow.withAlphaComponent(0)])!
        .draw(fromCenter: NSPoint(x: rect.width * 0.2, y: rect.height * 0.1), radius: 0,
              toCenter: NSPoint(x: rect.width * 0.2, y: rect.height * 0.1), radius: rect.width * 0.55, options: [])
}

func text(_ string: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat = 1, color: NSColor = style.text, at point: NSPoint) {
    (string as NSString).draw(at: point, withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color.withAlphaComponent(alpha),
    ])
}

// MARK: Social preview

let previewPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : path("docs/images/social-preview.png")
render(width: 1280, height: 640, to: previewPath) { rect in
    background(rect, top: style.top, bottom: style.bottom, glow: style.glow)

    // Left: icon, name, tagline, features.
    icon.draw(in: NSRect(x: 72, y: 382, width: 150, height: 150))
    text("Squeaky", size: 84, weight: .bold, at: NSPoint(x: 72, y: 268))
    text("A free, open-source cleaner for your Mac", size: 26, weight: .medium, alpha: 0.88, at: NSPoint(x: 76, y: 226))
    text("Cleanup · Protection · Performance", size: 20, weight: .regular, alpha: 0.7, at: NSPoint(x: 76, y: 160))
    text("Uninstaller · Declutter", size: 20, weight: .regular, alpha: 0.7, at: NSPoint(x: 76, y: 132))
    text("github.com/ThanksToBoredom/squeaky", size: 17, weight: .semibold, alpha: 0.55, at: NSPoint(x: 76, y: 72))

    // Right: the app, zoomed in and anchored to the bottom right, running off both edges so the
    // sidebar and the first cards fill the corner. The screenshot keeps its window shadow.
    let width: CGFloat = 1250
    let height = width * screenshot.size.height / screenshot.size.width
    let top: CGFloat = 560
    // A large, soft drop shadow on top of the window's own, so the app floats off the background.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 70
    shadow.shadowOffset = NSSize(width: 0, height: -26)
    shadow.set()
    screenshot.draw(in: NSRect(x: 610, y: top - height, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: Avatar

render(width: 1024, height: 1024, to: path("docs/images/avatar.png")) { rect in
    background(rect, top: blueTop, bottom: blueBottom, glow: blueGlow)
    let side = rect.width * 0.78
    guineaPig.draw(in: NSRect(x: (rect.width - side) / 2, y: (rect.height - side) / 2 - rect.height * 0.02, width: side, height: side))
}
