import SwiftUI

/// The window everyone's plants sit in, as cut-paper pieces: wall, sky, a wooden
/// frame whose strips don't quite line up, two curtains of different lengths, and
/// the sill board the pots stand on, with each friend's name on its front.
///
/// Used by both the app and the widget, so they always match. `plant` draws one
/// friend's plant: live in the app, a pre-rendered PNG in the widget.
struct WindowScene<Plant: View>: View {
    let petals: [Petal]
    var boardHeight: CGFloat = 26
    var plantSpacing: CGFloat = 12
    /// Keeps plants that size themselves to fit (the widget's images) below the top of the frame.
    var plantsTopInset: CGFloat = 0
    @ViewBuilder var plant: (_ index: Int, _ petal: Petal) -> Plant

    var body: some View {
        ZStack(alignment: .bottom) {
            WindowBackdrop(boardHeight: boardHeight)
            HStack(alignment: .bottom, spacing: plantSpacing) {
                ForEach(Array(petals.enumerated()), id: \.element.id) { index, petal in
                    VStack(spacing: 0) {
                        plant(index, petal)
                        // The pot stands on the board; the name sits on its front.
                        NameLabel(owner: petal.owner)
                            .frame(height: boardHeight)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(SpikeUsers.name(for: petal.owner))'s flower")
                }
            }
            .padding(.top, plantsTopInset)
        }
    }
}

/// Everything in the window except the plants, drawn as layered paper pieces.
private struct WindowBackdrop: View {
    let boardHeight: CGFloat

    var body: some View {
        Canvas { context, size in
            // A fixed seed: the same small misalignments on every render and device.
            var random = SeededRandom(seed: 21)
            func jitter(_ amount: CGFloat) -> CGFloat { (random.next() - 0.5) * 2 * amount }

            /// A rectangle cut by hand: each corner nudged a little.
            func cut(_ rect: CGRect, wobble: CGFloat = 1.5) -> Path {
                var path = Path()
                path.move(to: CGPoint(x: rect.minX + jitter(wobble), y: rect.minY + jitter(wobble)))
                path.addLine(to: CGPoint(x: rect.maxX + jitter(wobble), y: rect.minY + jitter(wobble)))
                path.addLine(to: CGPoint(x: rect.maxX + jitter(wobble), y: rect.maxY + jitter(wobble)))
                path.addLine(to: CGPoint(x: rect.minX + jitter(wobble), y: rect.maxY + jitter(wobble)))
                path.closeSubpath()
                return path
            }

            /// A paper piece with a hard shadow; `lift` is how far it sits off what's behind.
            func piece(_ path: Path, _ colour: Color, lift: CGFloat = 1) {
                context.fill(path.offsetBy(dx: 1.5 * lift, dy: 2.5 * lift), with: .color(.ink.opacity(0.2)))
                context.fill(path, with: .color(colour))
            }

            let width = size.width
            let height = size.height
            let boardTop = height - boardHeight
            let strip = max(5, min(width, height) * 0.035)
            let window = CGRect(x: width * 0.08, y: height * 0.07,
                                width: width * 0.84, height: boardTop - height * 0.07)

            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.wall))

            // Sky, then the frame on top of it. The strips are cut separately and
            // laid down slightly off, the way real paper strips would be.
            piece(cut(window), .sky, lift: 0.4)
            piece(cut(CGRect(x: window.midX - strip * 0.4 + jitter(2), y: window.minY,
                             width: strip * 0.8, height: window.height)), .wood, lift: 0.6)
            piece(cut(CGRect(x: window.minX, y: window.minY + window.height * 0.42 + jitter(2),
                             width: window.width, height: strip * 0.8)), .wood, lift: 0.6)
            piece(cut(CGRect(x: window.minX - strip * 0.6, y: window.minY - strip * 0.3,
                             width: strip, height: window.height + strip * 0.3)), .wood)
            piece(cut(CGRect(x: window.maxX - strip * 0.4, y: window.minY - strip * 0.3,
                             width: strip, height: window.height + strip * 0.3)), .wood)
            piece(cut(CGRect(x: window.minX - strip, y: window.minY - strip * 0.7,
                             width: window.width + strip * 2, height: strip)), .wood)

            // Curtains: the left one hangs longer than the right.
            let top = window.minY - strip * 0.2
            piece(curtain(x: window.minX - strip * 0.8, top: top, width: window.width * 0.24,
                          length: window.height * 0.74, flaresLeft: true), .cream, lift: 1.4)
            piece(curtain(x: window.maxX + strip * 0.8 - window.width * 0.2, top: top, width: window.width * 0.2,
                          length: window.height * 0.56, flaresLeft: false), .cream, lift: 1.4)
            for line in curtainFolds(x: window.minX - strip * 0.8, top: top, width: window.width * 0.24,
                                     length: window.height * 0.74) +
                        curtainFolds(x: window.maxX + strip * 0.8 - window.width * 0.2, top: top,
                                     width: window.width * 0.2, length: window.height * 0.56) {
                context.stroke(line, with: .color(.ink.opacity(0.08)), lineWidth: 1)
            }
            piece(cut(CGRect(x: window.minX - strip * 1.6, y: top - strip * 0.35,
                             width: window.width + strip * 3.2, height: strip * 0.55)), .sill, lift: 1.4)

            // The sill board: a top lip a little wider than the window, and its front face.
            piece(cut(CGRect(x: window.minX - strip * 1.8, y: boardTop + strip * 0.25,
                             width: window.width + strip * 3.6, height: boardHeight - strip * 0.25)), .sill, lift: 1.2)
            piece(cut(CGRect(x: window.minX - strip * 2, y: boardTop - strip * 0.35,
                             width: window.width + strip * 4, height: strip * 0.75)), .wood, lift: 1.2)
        }
        .accessibilityHidden(true)
    }

    /// A hanging curtain: straight along the rod, flaring a little towards the wall,
    /// with a snipped zigzag hem.
    private func curtain(x: CGFloat, top: CGFloat, width: CGFloat, length: CGFloat, flaresLeft: Bool) -> Path {
        let flare = width * 0.12
        let bottomLeft = x - (flaresLeft ? flare : -flare * 0.3)
        let bottomRight = x + width + (flaresLeft ? -flare * 0.3 : flare)
        var path = Path()
        path.move(to: CGPoint(x: x, y: top))
        path.addLine(to: CGPoint(x: x + width, y: top))
        path.addLine(to: CGPoint(x: bottomRight, y: top + length))
        // Hem: right to left, every other point snipped 4 pt lower.
        let points = 12
        for index in 1...points {
            let t = CGFloat(index) / CGFloat(points)
            let dip: CGFloat = index.isMultiple(of: 2) ? 0 : 4
            path.addLine(to: CGPoint(x: bottomRight + (bottomLeft - bottomRight) * t, y: top + length + dip))
        }
        path.closeSubpath()
        return path
    }

    /// Faint vertical folds down a curtain.
    private func curtainFolds(x: CGFloat, top: CGFloat, width: CGFloat, length: CGFloat) -> [Path] {
        [0.3, 0.55, 0.8].map { position in
            var path = Path()
            path.move(to: CGPoint(x: x + width * position, y: top + 4))
            path.addLine(to: CGPoint(x: x + width * position, y: top + length - 6))
            return path
        }
    }
}

#Preview {
    WindowScene(petals: FlowerStore.defaultPetals) { index, petal in
        PlantView(petal: petal, pot: .forSill(index), size: 80)
    }
    .frame(height: 260)
}
