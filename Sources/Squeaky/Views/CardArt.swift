import SwiftUI
import UniformTypeIdentifiers

/// Icons in a row, largest in the middle, shrinking towards the edges. Scales down to fit the card.
/// The spacing is negative because app icons carry transparent padding of their own.
struct IconStrip: View {
    let urls: [URL]
    var spacing: CGFloat = -6

    private static let sizes: [CGFloat] = [90, 62, 44]

    var body: some View {
        let middle = (urls.count - 1) / 2
        let sizes = urls.indices.map { Self.sizes[min(abs($0 - middle), Self.sizes.count - 1)] }
        let natural = sizes.reduce(0, +) + spacing * CGFloat(max(urls.count - 1, 0))

        GeometryReader { proxy in
            let scale = min(1, proxy.size.width / max(natural, 1))
            HStack(spacing: spacing * scale) {
                ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                    Image(nsImage: IconCache.icon(for: url))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: sizes[index] * scale, height: sizes[index] * scale)
                        .shadow(color: .black.opacity(0.3), radius: 10 * scale, y: 6 * scale)
                        // The middle icon sits on top of its neighbours.
                        .zIndex(-Double(abs(index - middle)))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(height: Self.sizes[0])
    }
}

/// A wall of icons that fades out towards the bottom-right corner, hinting that there's
/// more to see in the review. With `columns` set the grid is fixed (and `rows` deep);
/// without it, the wall picks as many columns of roughly `cellSize` as fit and fills the height.
struct IconWall: View {
    let icons: [NSImage]
    var columns: Int?
    var rows = 10
    var cellSize: CGFloat = 40
    var spacing: CGFloat = 10
    /// Show icons in only this share (0...1) of the fully visible cells, at least one, and leave
    /// the rest empty. Nil fills every cell.
    var fill: Double?

    var body: some View {
        GeometryReader { proxy in
            let columns = max(1, columns ?? max(1, Int((proxy.size.width + spacing) / max(1, cellSize + spacing))))
            let size = max(1, (proxy.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
            let fullRows = max(1, Int((proxy.size.height + spacing) / (size + spacing)))
            let rows = self.columns == nil ? fullRows + 1 : max(0, rows)
            let shown = fill.map { max(1, Int((Double(columns * fullRows) * $0).rounded())) } ?? Int.max
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = row * columns + column
                            if index >= shown {
                                Color.clear.frame(width: size, height: size)
                            } else if index < icons.count {
                                Image(nsImage: icons[index])
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: size, height: size)
                            } else {
                                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                                    .fill(.white.opacity(0.08))
                                    .frame(width: size, height: size)
                            }
                        }
                    }
                }
            }
        }
        .clipped()
        // Fully visible at the top left, gone by the bottom right…
        .mask(LinearGradient(
            stops: [.init(color: .black, location: 0), .init(color: .black.opacity(0), location: 0.9)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ))
        // …and softened along the bottom edge so clipped rows don't end abruptly.
        .mask(LinearGradient(
            stops: [.init(color: .black, location: 0.75), .init(color: .black.opacity(0), location: 1)],
            startPoint: .top,
            endPoint: .bottom
        ))
    }

    /// The given files' icons first, then generic file and folder icons to fill the wall.
    @MainActor
    static func fileIcons(
        for urls: [URL],
        count: Int = 160,
        fillers: [UTType] = [.folder, .pdf, .movie, .image, .zip, .diskImage, .mp3, .spreadsheet, .presentation, .plainText]
    ) -> [NSImage] {
        let count = max(0, count)
        let files = urls.prefix(count).map(IconCache.icon(for:))
        guard !fillers.isEmpty else { return files }
        let padding = (0..<max(0, count - files.count)).map { IconCache.icon(for: fillers[$0 % fillers.count]) }
        return files + padding
    }
}

/// Leftover take-away: a soda cup, a takeout box and fries. SVG art from Microsoft's
/// Fluent Emoji (MIT licence, see Resources/Art/FluentEmoji-LICENSE.txt).
struct FastFoodArt: View {
    private static let canvas = CGSize(width: 250, height: 170)

    var body: some View {
        GeometryReader { proxy in
            let scale = min(1.25, proxy.size.width / Self.canvas.width, proxy.size.height / Self.canvas.height)
            scene
                .frame(width: Self.canvas.width, height: Self.canvas.height)
                .scaleEffect(scale)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private static let crumbs: [(x: CGFloat, y: CGFloat, size: CGFloat, angle: Double)] = [
        (16, 156, 4.5, 20), (30, 161, 3, -30), (104, 160, 3.5, 45), (142, 162, 3, 10),
        (150, 152, 2.5, -15), (214, 160, 4, 70), (246, 160, 3, -40), (58, 158, 2.5, 0),
    ]

    /// Positions are the centre of each image on a 250 × 170 canvas; the ground line is y ≈ 150.
    private var scene: some View {
        ZStack {
            ContactShadow(width: 64).position(x: 128, y: 146)
            ContactShadow(width: 84).position(x: 70, y: 152)
            ContactShadow(width: 78).position(x: 182, y: 154)

            ArtImage(name: "cup_with_straw_color").frame(width: 124, height: 124).position(x: 128, y: 86)
            ArtImage(name: "takeout_box_color").frame(width: 112, height: 112).position(x: 70, y: 102)
            // The carton with all but one fry removed (edited from Fluent's french_fries_color.svg).
            ArtImage(name: "french_fries_empty").frame(width: 108, height: 108).position(x: 182, y: 106)

            // Leftovers on the table: a couple of loose fries and crumbs.
            ArtImage(name: "fry_single").frame(width: 40, height: 40).rotationEffect(.degrees(78)).position(x: 122, y: 156)
            ArtImage(name: "fry_single").frame(width: 34, height: 34).rotationEffect(.degrees(-64)).position(x: 236, y: 152)
            ForEach(Array(Self.crumbs.enumerated()), id: \.offset) { _, crumb in
                Crumb(size: crumb.size, angle: crumb.angle).position(x: crumb.x, y: crumb.y)
            }
        }
    }
}

/// An SVG copied into the app's Resources folder by scripts/build-app.sh.
private struct ArtImage: View {
    let name: String

    var body: some View {
        if let image = SVGImage.named(name) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        }
    }
}

/// A small, irregular bread crumb in the same soft 3D style as the Fluent art.
private struct Crumb: View {
    let size: CGFloat
    let angle: Double

    var body: some View {
        Ellipse()
            .fill(RadialGradient(
                colors: [Color(hex: 0xF6D58E), Color(hex: 0xD9A250), Color(hex: 0xA8702C)],
                center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size
            ))
            .frame(width: size * 1.4, height: size)
            .rotationEffect(.degrees(angle))
            .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
    }
}

private struct ContactShadow: View {
    let width: CGFloat

    var body: some View {
        Ellipse()
            .fill(.black.opacity(0.25))
            .frame(width: width, height: 10)
            .blur(radius: 5)
    }
}
