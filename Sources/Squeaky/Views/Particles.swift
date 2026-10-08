import AppKit
import QuartzCore
import SwiftUI

// Particle effects built on Core Animation's emitter (CAEmitterLayer): bubbles behind the
// hero badge and a confetti burst when something has been removed. Both respect the
// "Reduce motion" accessibility setting.

private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

// Emission angles, verified with screen captures. They depend on the emitter's shape:
// for a `.line` emitter, π points up the screen; for a `.point` emitter, 0 points right and
// π/2 points up. Accelerations always use plain layer axes (+y is up).
private let lineUpwards: CGFloat = .pi
private let pointUpwards: CGFloat = .pi / 2

/// Hosts one or more emitter layers and keeps them sized to the view. Lets clicks through.
final class EmitterHostView: NSView {
    let emitters: [CAEmitterLayer]
    var onLayout: ((CGRect, [CAEmitterLayer]) -> Void)?
    /// Optional oval fade towards the edges. It has to be a layer mask: SwiftUI masks
    /// don't reach the particles, which Core Animation draws on its own.
    private let fade: CAGradientLayer?

    init(emitters: [CAEmitterLayer], fadesAtEdges: Bool = false) {
        self.emitters = emitters
        if fadesAtEdges {
            let fade = CAGradientLayer()
            fade.type = .radial
            fade.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
            fade.locations = [0, 0.5, 1]
            // A radial gradient from the centre to the corner point fills the bounds as an oval.
            fade.startPoint = CGPoint(x: 0.5, y: 0.5)
            fade.endPoint = CGPoint(x: 1, y: 1)
            self.fade = fade
        } else {
            self.fade = nil
        }
        super.init(frame: .zero)
        wantsLayer = true
        emitters.forEach { layer?.addSublayer($0) }
        layer?.mask = fade
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var appliedSize: CGSize = .zero

    /// Sizes the emitters (and fade) for `size` and positions them via `onLayout`.
    /// SwiftUI passes the size in directly, because `layout()` isn't reliably called for
    /// representable views; without this the emitters can end up stuck at the origin.
    func apply(size: CGSize) {
        guard size.width > 0, size.height > 0, size != appliedSize else { return }
        appliedSize = size
        let bounds = CGRect(origin: .zero, size: size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        emitters.forEach { $0.frame = bounds }
        fade?.frame = bounds
        onLayout?(bounds, emitters)
        CATransaction.commit()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        apply(size: newSize)
    }

    override func layout() {
        super.layout()
        apply(size: bounds.size)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - Bubbles

/// Translucent bubbles that rise straight up behind the badge and pop as they fade.
struct BubbleField: NSViewRepresentable {
    let tint: Color
    var busy = false
    /// The size SwiftUI lays the field out at (see `EmitterHostView.apply(size:)`).
    let size: CGSize

    func makeNSView(context: Context) -> EmitterHostView {
        let emitter = CAEmitterLayer()
        emitter.emitterShape = .line
        emitter.renderMode = .additive
        emitter.emitterCells = [bubbleCell(large: false), bubbleCell(large: true)]
        // Start as if it had been running for a while, so the field isn't empty on appear.
        emitter.beginTime = CACurrentMediaTime() - 8

        let view = EmitterHostView(emitters: [emitter], fadesAtEdges: true)
        // Layer coordinates have y pointing up: emit along the bottom edge, rising.
        view.onLayout = { bounds, emitters in
            emitters[0].emitterPosition = CGPoint(x: bounds.midX, y: bounds.minY)
            emitters[0].emitterSize = CGSize(width: bounds.width * 0.95, height: 1)
        }
        view.apply(size: size)
        apply(to: emitter)
        return view
    }

    func updateNSView(_ view: EmitterHostView, context: Context) {
        view.apply(size: size)
        apply(to: view.emitters[0])
    }

    private func apply(to emitter: CAEmitterLayer) {
        emitter.birthRate = reduceMotion ? 0 : (busy ? 3 : 1)
        emitter.velocity = busy ? 1.9 : 1
        emitter.emitterCells?.forEach { $0.color = NSColor(tint).cgColor }
    }

    private func bubbleCell(large: Bool) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = ParticleImages.bubble
        cell.birthRate = large ? 1.6 : 4.5
        cell.lifetime = 8
        cell.lifetimeRange = 2
        cell.velocity = large ? 52 : 68
        cell.velocityRange = 22
        // Straight up, with just enough spread not to look mechanical.
        cell.emissionLongitude = lineUpwards
        cell.emissionRange = 0.035
        cell.yAcceleration = 6
        cell.xAcceleration = 0
        cell.scale = large ? 0.42 : 0.18
        cell.scaleRange = large ? 0.14 : 0.1
        cell.scaleSpeed = 0.015
        cell.alphaRange = 0.3
        // Fades over its life and disappears at the end: a quiet pop.
        cell.alphaSpeed = -0.08
        return cell
    }
}

/// The badge with bubbles rising behind it, softly faded towards the edges.
struct HeroStage: View {
    let module: Module
    var size: CGFloat = 220
    var busy = false

    var body: some View {
        ZStack {
            // Bubbles fade in at the bottom and dissolve towards the sides and top (see EmitterHostView).
            let field = CGSize(width: size * 3.2, height: size * 2.6)
            BubbleField(tint: module.palette.accent, busy: busy, size: field)
                .frame(width: field.width, height: field.height)
                .offset(y: -size * 0.05)
                .allowsHitTesting(false)
            HeroIcon(module: module, size: size, fast: busy)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Confetti

/// Two party poppers fire from the bottom corners; the confetti flies up and rains down.
struct ConfettiBurst: NSViewRepresentable {
    /// The window's content size (see `EmitterHostView.apply(size:)`).
    let size: CGSize

    private static let colors: [NSColor] = [
        NSColor(red: 1.00, green: 0.42, blue: 0.62, alpha: 1), // pink
        NSColor(red: 1.00, green: 0.82, blue: 0.30, alpha: 1), // yellow
        NSColor(red: 0.45, green: 0.90, blue: 0.70, alpha: 1), // mint
        NSColor(red: 0.40, green: 0.75, blue: 1.00, alpha: 1), // sky
        NSColor(red: 0.72, green: 0.58, blue: 1.00, alpha: 1), // lavender
        NSColor(red: 1.00, green: 0.62, blue: 0.32, alpha: 1), // orange
        .white,
    ]

    /// Where the confetti peaks, as a fraction of the window's height.
    private static let apex: CGFloat = 0.8
    /// Downward acceleration in points per second², which sets how fast it falls.
    private static let gravity: CGFloat = 2200
    /// Each popper fires up and slightly in towards the middle of the window.
    private static let angles: [CGFloat] = [pointUpwards - 0.3, pointUpwards + 0.3]

    func makeNSView(context: Context) -> EmitterHostView {
        let poppers = Self.angles.map { _ in
            let emitter = CAEmitterLayer()
            emitter.emitterShape = .point
            emitter.beginTime = CACurrentMediaTime()
            return emitter
        }
        let view = EmitterHostView(emitters: poppers)
        view.onLayout = { bounds, emitters in
            emitters[0].emitterPosition = CGPoint(x: bounds.minX + bounds.width * 0.08, y: bounds.minY)
            emitters[1].emitterPosition = CGPoint(x: bounds.maxX - bounds.width * 0.08, y: bounds.minY)
            // The launch speed that makes the confetti peak at `apex` under `gravity`:
            // height = speed² / (2 × gravity). Cells are only created once, so a resize
            // mid-burst doesn't restart it.
            let speed = (2 * Self.gravity * Self.apex * bounds.height).squareRoot()
            for (emitter, angle) in zip(emitters, Self.angles) where emitter.emitterCells == nil {
                emitter.emitterCells = Self.cells(speed: speed, angle: angle)
            }
        }
        view.apply(size: size)
        guard !reduceMotion else {
            view.emitters.forEach { $0.birthRate = 0 }
            return view
        }
        // A short burst, then the confetti already in the air finishes falling.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            view.emitters.forEach { $0.birthRate = 0 }
        }
        return view
    }

    func updateNSView(_ view: EmitterHostView, context: Context) {
        view.apply(size: size)
    }

    private static func cells(speed: CGFloat, angle: CGFloat) -> [CAEmitterCell] {
        colors.flatMap { color in
            ParticleImages.confetti.map { image in
                let cell = CAEmitterCell()
                cell.contents = image
                cell.color = color.cgColor
                cell.birthRate = 30
                cell.lifetime = 6
                cell.velocity = speed
                // ±10% speed spreads the peaks between roughly 65% and 95% of the height.
                cell.velocityRange = speed * 0.1
                cell.emissionLongitude = angle
                cell.emissionRange = .pi / 7
                // Gravity (y points up in layer coordinates).
                cell.yAcceleration = -gravity
                cell.spin = 3
                cell.spinRange = 9
                cell.scale = 0.34
                cell.scaleRange = 0.14
                cell.alphaSpeed = -0.1
                return cell
            }
        }
    }
}

// MARK: - Particle images

private enum ParticleImages {
    /// A soap bubble: clear middle, bright rim and a highlight. White, so the cell colour tints it.
    static let bubble: CGImage? = render(size: 64) { rect in
        let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
        NSGradient(colors: [NSColor.white.withAlphaComponent(0.04), NSColor.white.withAlphaComponent(0.28)])?
            .draw(in: circle, relativeCenterPosition: .zero)
        NSColor.white.withAlphaComponent(0.75).setStroke()
        circle.lineWidth = 2
        circle.stroke()
        NSColor.white.withAlphaComponent(0.85).setFill()
        NSBezierPath(ovalIn: NSRect(x: rect.width * 0.24, y: rect.height * 0.6, width: rect.width * 0.2, height: rect.height * 0.13)).fill()
    }

    /// Paper rectangles, thin streamers and dots.
    static let confetti: [CGImage] = [
        render(size: 24) { rect in NSBezierPath(roundedRect: NSRect(x: 4, y: 7, width: 16, height: 10), xRadius: 2, yRadius: 2).fill() },
        render(size: 24) { rect in NSBezierPath(roundedRect: NSRect(x: 9, y: 1, width: 6, height: 22), xRadius: 3, yRadius: 3).fill() },
        render(size: 24) { rect in NSBezierPath(ovalIn: NSRect(x: 6, y: 6, width: 12, height: 12)).fill() },
    ].compactMap { $0 }

    private static func render(size: CGFloat, draw: @escaping (NSRect) -> Void) -> CGImage? {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor.white.setFill()
            draw(rect)
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
