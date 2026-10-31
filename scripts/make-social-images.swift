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

// Sweep's blue, as used in the app.
let blueTop = NSColor(red: 0.29, green: 0.12, blue: 0.69, alpha: 1)
let blueBottom = NSColor(red: 0.04, green: 0.22, blue: 0.65, alpha: 1)
let glow = NSColor(red: 0.25, green: 0.48, blue: 1.0, alpha: 1)

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

func background(_ rect: NSRect) {
    NSGradient(starting: blueTop, ending: blueBottom)!.draw(in: rect, angle: -35)
    // Soft glow towards the bottom left, like the app's windows.
    NSGradient(colors: [glow.withAlphaComponent(0.45), glow.withAlphaComponent(0)])!
        .draw(fromCenter: NSPoint(x: rect.width * 0.2, y: rect.height * 0.1), radius: 0,
              toCenter: NSPoint(x: rect.width * 0.2, y: rect.height * 0.1), radius: rect.width * 0.55, options: [])
}

func text(_ string: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat = 1, at point: NSPoint) {
    (string as NSString).draw(at: point, withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor.white.withAlphaComponent(alpha),
    ])
}

// MARK: Social preview

render(width: 1280, height: 640, to: path("docs/images/social-preview.png")) { rect in
    background(rect)

    // Left: icon, name, tagline, features.
    icon.draw(in: NSRect(x: 72, y: 382, width: 150, height: 150))
    text("Squeaky", size: 84, weight: .bold, at: NSPoint(x: 72, y: 268))
    text("A free, open-source cleaner for your Mac", size: 26, weight: .medium, alpha: 0.88, at: NSPoint(x: 76, y: 226))
    text("Cleanup · Protection · Performance", size: 20, weight: .regular, alpha: 0.7, at: NSPoint(x: 76, y: 160))
    text("Uninstaller · Declutter", size: 20, weight: .regular, alpha: 0.7, at: NSPoint(x: 76, y: 132))
    text("github.com/ThanksToBoredom/squeaky", size: 17, weight: .semibold, alpha: 0.55, at: NSPoint(x: 76, y: 72))

    // Right: the app, running off the right edge. The screenshot keeps its window shadow.
    let width: CGFloat = 820
    let height = width * screenshot.size.height / screenshot.size.width
    screenshot.draw(in: NSRect(x: 600, y: (rect.height - height) / 2 - 10, width: width, height: height))
}

// MARK: Avatar

render(width: 1024, height: 1024, to: path("docs/images/avatar.png")) { rect in
    background(rect)
    let side = rect.width * 0.78
    guineaPig.draw(in: NSRect(x: (rect.width - side) / 2, y: (rect.height - side) / 2 - rect.height * 0.02, width: side, height: side))
}
