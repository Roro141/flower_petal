import SwiftUI

/// A faint paper grain laid over a scene: tiny dark and light flecks and fibres at
/// about 5%. Drawn once into a small tile, then repeated, so it costs almost nothing
/// to show (in the widget too) and never shimmers between renders.
struct PaperGrain: View {
    var strength = 0.05

    private static let tileSize: CGFloat = 96
    private static let tileScale: CGFloat = 2

    var body: some View {
        if let tile = Self.tile {
            Image(decorative: tile, scale: Self.tileScale)
                .resizable(resizingMode: .tile)
                .opacity(strength)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @MainActor private static let tile: CGImage? = {
        let renderer = ImageRenderer(content:
            Canvas { context, size in
                var random = SeededRandom(seed: 9)
                let count = Int(size.width * size.height / 3)
                for index in 0..<count {
                    let point = CGPoint(x: random.next() * size.width, y: random.next() * size.height)
                    let colour: Color = index.isMultiple(of: 2) ? .ink : .white
                    if index.isMultiple(of: 9) {
                        // An occasional short fibre.
                        let angle = random.next() * .pi
                        let length = 2 + random.next() * 3
                        var fibre = Path()
                        fibre.move(to: point)
                        fibre.addLine(to: CGPoint(x: point.x + cos(angle) * length, y: point.y + sin(angle) * length))
                        context.stroke(fibre, with: .color(colour), lineWidth: 0.5)
                    } else {
                        let radius = 0.3 + random.next() * 0.5
                        context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                                            width: radius * 2, height: radius * 2)),
                                     with: .color(colour))
                    }
                }
            }
            .frame(width: tileSize, height: tileSize)
        )
        renderer.scale = tileScale
        return renderer.cgImage
    }()
}

/// Hard cast shadows for paper pieces. `lift` is how high a piece sits above what's
/// behind it: higher pieces throw a longer, slightly lighter shadow, down and to the right.
/// `unit` is the shadow length at a lift of 1.
enum PaperShadow {
    static func offset(lift: CGFloat, unit: CGFloat) -> CGSize {
        CGSize(width: unit * 0.6 * lift, height: unit * lift)
    }

    static func colour(lift: CGFloat) -> Color {
        .ink.opacity(max(0.12, 0.27 - 0.05 * Double(lift)))
    }
}
