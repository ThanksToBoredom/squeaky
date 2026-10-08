// Renders the Squeaky app icon and writes an .icns file.
// Usage: swift scripts/make-icon.swift Resources/AppIcon.icns
//
// Design: the 3D guinea pig from Resources/Icon/guinea-pig-3d.png (transparent background),
// centred on a uniform blue tile. Resources/Icon/guinea-pig.svg is the flat version of the same design.
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns")
let artwork = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Resources/Icon/guinea-pig-3d.png")

guard let guineaPig = NSImage(contentsOf: artwork) else {
    fatalError("Couldn't load \(artwork.path)")
}

/// How much of the tile the guinea pig fills.
let artworkScale: CGFloat = 0.72

func render(_ pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Draw on a 1024 canvas and scale to the requested size.
    let transform = NSAffineTransform()
    transform.scale(by: size / 1024)
    transform.concat()

    // macOS icon grid: an 824 pt tile centred on the 1024 canvas.
    NSColor(red: 0.16, green: 0.42, blue: 0.96, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185).fill()

    let side = 824 * artworkScale
    guineaPig.draw(in: NSRect(x: 512 - side / 2, y: 512 - side / 2, width: side, height: side))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Squeaky.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote \(output.path)" : "iconutil failed")
