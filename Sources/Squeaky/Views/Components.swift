import SwiftUI

// MARK: - Background

/// The full-window gradient with soft blobs of light, recoloured per module.
struct ModuleBackground: View {
    let palette: Palette

    var body: some View {
        ZStack {
            LinearGradient(colors: [palette.top, palette.bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(
                colors: [palette.glow.opacity(0.55), .clear],
                center: UnitPoint(x: 0.25, y: 0.9), startRadius: 0, endRadius: 560
            )
            RadialGradient(
                colors: [Color.white.opacity(0.10), .clear],
                center: UnitPoint(x: 0.75, y: 0.1), startRadius: 0, endRadius: 460
            )
            Ellipse()
                .fill(palette.glow.opacity(0.28))
                .frame(width: 760, height: 280)
                .blur(radius: 110)
                .rotationEffect(.degrees(-25))
                .offset(x: 220, y: 140)
        }
    }
}

// MARK: - Hero artwork

/// A glossy, glassy tile with the module's symbol: each module's hero badge.
struct HeroIcon: View {
    let module: Module
    var size: CGFloat = 220
    var floating = true
    var fast = false

    @ViewState private var lifted = false

    var body: some View {
        let palette = module.palette
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)

        ZStack {
            shape
                // Fully opaque, so nothing behind the badge (like the bubbles) shows through.
                .fill(LinearGradient(
                    colors: [palette.accent, palette.glow, palette.bottom],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            Ellipse()
                .fill(Color.white.opacity(0.4))
                .frame(width: size * 0.8, height: size * 0.3)
                .blur(radius: size * 0.06)
                .offset(y: -size * 0.36)
            Circle()
                .fill(palette.accent.opacity(0.6))
                .frame(width: size * 0.7)
                .blur(radius: size * 0.12)
                .offset(x: size * 0.25, y: size * 0.3)
        }
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.8), .white.opacity(0.05), .white.opacity(0.3)], startPoint: .top, endPoint: .bottom),
                lineWidth: max(1.5, size * 0.01)
            )
        )
        .overlay(
            SymbolImage(name: module.symbol, size: size * 0.4)
                .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.72)], startPoint: .top, endPoint: .bottom))
                .shadow(color: palette.bottom.opacity(0.5), radius: size * 0.04, y: size * 0.03)
        )
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.35), radius: size * 0.12, y: size * 0.09)
        .modifier(Tilt(angle: lifted ? 7 : -7, enabled: !DebugSnapshot.disablesAnimations))
        .offset(y: lifted ? -size * 0.03 : size * 0.03)
        .onAppear {
            guard floating, !DebugSnapshot.disablesAnimations else { return }
            withAnimation(.easeInOut(duration: fast ? 1.1 : 3).repeatForever(autoreverses: true)) { lifted = true }
        }
    }
}

private struct Tilt: ViewModifier {
    let angle: Double
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.rotation3DEffect(.degrees(angle), axis: (x: 1, y: 1, z: 0))
        } else {
            content
        }
    }
}

/// Small rounded square with a category symbol, used in result cards.
struct CategoryBadge: View {
    let symbol: String
    let palette: Palette
    var size: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: [palette.accent, palette.glow], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).strokeBorder(.white.opacity(0.35)))
            .overlay(SymbolImage(name: symbol, size: size * 0.45, weight: .semibold).foregroundStyle(.white))
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }
}

// MARK: - Buttons

/// The big pill-shaped Scan / Stop / Clean button pinned to the bottom centre.
struct PrimaryActionButton: View {
    let title: String
    let palette: Palette
    var busy = false
    var enabled = true
    let action: () -> Void

    static let height: CGFloat = 56
    private static let size = CGSize(width: 164, height: height)
    /// Length of the capsule's outline, used to loop the busy highlight seamlessly.
    private static let perimeter = 2 * (size.width - size.height) + .pi * size.height
    private static let highlight: CGFloat = 46

    /// One explicit outline for fill, border and busy highlight so they line up exactly.
    private static let shape = RoundedRectangle(cornerRadius: size.height / 2, style: .circular)

    @ViewState private var phase: CGFloat = 0

    var body: some View {
        Button(action: action) {
            ZStack {
                Self.shape
                    .fill(RadialGradient(
                        colors: [palette.accent, palette.glow, palette.bottom],
                        center: .center, startRadius: 2, endRadius: 110
                    ))
                Self.shape.strokeBorder(.white.opacity(0.75), lineWidth: 2.5)
                if busy {
                    // A short highlight that runs around the outline.
                    Self.shape
                        .inset(by: 1.25)
                        .stroke(.white, style: StrokeStyle(
                            lineWidth: 3.5, lineCap: .round,
                            dash: [Self.highlight, Self.perimeter - Self.highlight], dashPhase: phase
                        ))
                        .onAppear {
                            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                                phase = -Self.perimeter
                            }
                        }
                }
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: Self.size.width, height: Self.size.height)
            .shadow(color: palette.accent.opacity(0.65), radius: 24)
            .contentShape(Self.shape)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .keyboardShortcut(.defaultAction)
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Translucent pill buttons ("Review"), or white ones for the primary action ("Clean").
struct GlassButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(prominent ? Color.black.opacity(0.85) : Color.white)
            .background(shape.fill(prominent ? Color.white.opacity(0.95) : Color.white.opacity(configuration.isPressed ? 0.26 : 0.14)))
            .overlay(shape.strokeBorder(Color.white.opacity(prominent ? 0 : 0.18)))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(shape)
    }
}

/// A plain text button for secondary actions, e.g. "Start Over". Brightens on hover.
struct TextLink: View {
    let title: String
    let action: () -> Void

    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.72))
                .underline(hovering)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The bottom of a results screen: "Start Over" above the primary button, or, on screens
/// without one, in the button's place.
struct ResultsFooter<Action: View>: View {
    let onStartOver: () -> Void
    let action: Action?

    init(onStartOver: @escaping () -> Void, @ViewBuilder action: () -> Action) {
        self.onStartOver = onStartOver
        self.action = action()
    }

    var body: some View {
        VStack(spacing: 14) {
            if let action {
                TextLink(title: "Start Over", action: onStartOver)
                action.frame(height: PrimaryActionButton.height)
            } else {
                TextLink(title: "Start Over", action: onStartOver)
                    .frame(height: PrimaryActionButton.height)
            }
        }
        .padding(.bottom, 40)
    }
}

extension ResultsFooter where Action == Never {
    /// For screens without a primary button: the link takes the button's place.
    init(onStartOver: @escaping () -> Void) {
        self.onStartOver = onStartOver
        self.action = nil
    }
}

// MARK: - Glass surfaces

extension View {
    func glassCard(cornerRadius: CGFloat = 18) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(shape.fill(LinearGradient(
            colors: [.white.opacity(0.17), .white.opacity(0.07)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )))
        .overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 1))
    }
}

// MARK: - Checkbox

enum CheckState { case on, off, mixed }

struct CheckBox: View {
    let state: CheckState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(state == .off ? Color.white.opacity(0.08) : Color.white)
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white.opacity(state == .off ? 0.55 : 0)))
                .overlay {
                    switch state {
                    case .on: Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy))
                    case .mixed: Image(systemName: "minus").font(.system(size: 10, weight: .heavy))
                    case .off: EmptyView()
                    }
                }
                .foregroundStyle(Color.black.opacity(0.8))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Header

/// The strip next to the traffic lights: a back button on the left and the module name centred.
struct ScreenHeader: View {
    let title: String
    var backTitle: String?
    var onBack: (() -> Void)?

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            HStack {
                if let backTitle, let onBack {
                    Button(action: onBack) {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                            Text(backTitle)
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .frame(height: 44)
    }
}

// MARK: - Symbols

/// Draws an SF Symbol, or a bundled single-colour SVG when the name starts with `svg:`
/// (e.g. `svg:apps`). SVGs are rendered as templates, so they take the
/// foreground style just like symbols do.
struct SymbolImage: View {
    let name: String
    let size: CGFloat
    var weight: Font.Weight = .medium

    var body: some View {
        if name.hasPrefix("svg:"), let image = Self.template(named: String(name.dropFirst(4))) {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                // Tabler glyphs leave padding inside their 24 pt canvas; scale up to match SF Symbols.
                .frame(width: size * 1.3, height: size * 1.3)
        } else {
            Image(systemName: name)
                .font(.system(size: size, weight: weight))
        }
    }

    private static func template(named name: String) -> NSImage? {
        guard let image = SVGImage.named(name, template: true) else { return nil }
        image.isTemplate = true
        return image
    }
}

/// Loads bundled SVGs. Their files declare a tiny natural size (24–32 pt), and SwiftUI
/// rasterises an NSImage at its natural size before scaling it, which looked blurry when
/// enlarged. Giving the image a large size first makes it render crisply at any display size.
@MainActor
enum SVGImage {
    private static var cache: [String: NSImage] = [:]

    static func named(_ name: String, template: Bool = false) -> NSImage? {
        let key = template ? "template:\(name)" : name
        if let cached = cache[key] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        let aspect = image.size.height / max(image.size.width, 1)
        image.size = NSSize(width: 512, height: 512 * aspect)
        cache[key] = image
        return image
    }
}
