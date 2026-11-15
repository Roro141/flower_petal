import SwiftUI

/// A friend's flower head: their cut petal repeated around a centre.
/// This is the one place a flower is drawn. The app shows it directly and the
/// widget shows PNGs rendered from it.
struct FlowerView: View {
    let petal: Petal
    let size: CGFloat
    /// false: folded, every petal stacked on the first, as it was cut. When this turns
    /// true the petals rotate out one after another (about 1 s, 90 ms apart, ease-out).
    /// Widgets and rendered PNGs always pass true, so they never animate.
    var isOpen = true

    private static let unfoldStagger = 0.09

    /// Where each petal sits. Small per-owner jitter in angle and length keeps
    /// the repeat from ever being perfectly even, and stays the same on every render.
    private var placements: [(angle: Double, scale: CGFloat)] {
        let count = min(max(petal.nPetals, 5), 8)
        var random = SeededRandom(petal.owner)
        let turn = random.next() * 360
        return (0..<count).map { index in
            (angle: turn + Double(index) * 360 / Double(count) + random.next() * 12 - 6,
             scale: 0.92 + random.next() * 0.08)
        }
    }

    var body: some View {
        ZStack {
            let placements = placements
            ForEach(Array(placements.enumerated()), id: \.offset) { index, placement in
                let length = size / 2 * placement.scale
                let angle = isOpen ? placement.angle : placements[0].angle
                // Each petal is laid on top of the one before, so sits a little higher.
                let lift = 1.1 + 0.07 * CGFloat(index)
                let shadow = PaperShadow.offset(lift: lift, unit: size * 0.02)
                ZStack {
                    // Hard paper shadow, cast down and to the right in screen space.
                    PetalPath(points: petal.points)
                        .fill(PaperShadow.colour(lift: lift))
                        .frame(width: length, height: length)
                        .offset(y: -length / 2)
                        .rotationEffect(.degrees(angle))
                        .offset(x: shadow.width, y: shadow.height)
                    paperPetal
                        .frame(width: length, height: length)
                        .offset(y: -length / 2)
                        .rotationEffect(.degrees(angle))
                }
                .animation(
                    .timingCurve(0.2, 0.8, 0.2, 1, duration: 1 - Self.unfoldStagger * Double(placements.count - 1))
                        .delay(Self.unfoldStagger * Double(index)),
                    value: isOpen
                )
            }
            CentreView(
                style: FlowerCentre.for(owner: petal.owner),
                diameter: size * 0.2,
                turn: placements.first?.angle ?? 0
            )
        }
        .frame(width: size, height: size)
    }

    /// One petal cut from the paper, with a faint crease down the fold.
    private var paperPetal: some View {
        PaperFill(paper: petal.pattern, scale: size * 0.05)
            .overlay {
                Crease(tip: petal.points.last?.last ?? 1)
                    .stroke(Color.ink.opacity(0.2), lineWidth: max(0.5, size * 0.006))
            }
            .clipShape(PetalPath(points: petal.points))
    }
}

/// The fold line down the middle of a petal, from just above the base to just below the tip.
private struct Crease: Shape {
    let tip: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.08))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * tip * 0.9))
        return path
    }
}

/// The five flower centres, one picked per owner.
enum FlowerCentre: CaseIterable {
    case button, seeds, crossStitch, star, kraft

    static func `for`(owner: String) -> FlowerCentre {
        var random = SeededRandom(owner + "-centre")
        return allCases[Int(random.next() * Double(allCases.count))]
    }
}

/// A flower centre, drawn as a small paper piece with its own hard shadow.
struct CentreView: View {
    let style: FlowerCentre
    let diameter: CGFloat
    var turn: Double = 0

    var body: some View {
        Canvas { context, size in
            let radius = diameter / 2
            context.translateBy(x: size.width / 2, y: size.height / 2)
            let outline = outlinePath(radius: radius)
                .applying(CGAffineTransform(rotationAngle: turn * .pi / 180))
            // The centre is glued on last, so it sits highest.
            let shadow = PaperShadow.offset(lift: 1.7, unit: radius * 0.2)
            context.fill(outline.offsetBy(dx: shadow.width, dy: shadow.height), with: .color(PaperShadow.colour(lift: 1.7)))
            context.fill(outline, with: .color(fill))
            context.rotate(by: .degrees(turn))
            drawDetails(in: &context, radius: radius)
        }
        .frame(width: diameter * 1.3, height: diameter * 1.3)
    }

    private var fill: Color {
        switch style {
        case .button, .star: .cream
        case .seeds: .grey
        case .crossStitch: .sky
        case .kraft: .wood
        }
    }

    private func outlinePath(radius: CGFloat) -> Path {
        let circle = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
        switch style {
        case .star:
            return polygon(count: 10) { index in index.isMultiple(of: 2) ? radius * 1.1 : radius * 0.5 }
        case .kraft:
            // Hand-torn disc: an uneven 9-sided polygon.
            var random = SeededRandom(seed: 11)
            return polygon(count: 9) { _ in radius * (0.9 + random.next() * 0.15) }
        case .button, .seeds, .crossStitch:
            return Path(ellipseIn: circle)
        }
    }

    private func polygon(count: Int, radius: (Int) -> CGFloat) -> Path {
        var path = Path()
        for index in 0..<count {
            let angle = Double(index) / Double(count) * 2 * .pi - .pi / 2
            let point = CGPoint(x: cos(angle) * radius(index), y: sin(angle) * radius(index))
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    private func drawDetails(in context: inout GraphicsContext, radius: CGFloat) {
        func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
        switch style {
        case .button:
            context.stroke(dot(0, 0, radius * 0.72), with: .color(.grey), lineWidth: radius * 0.08)
            for (x, y) in [(-1.0, -1.0), (1, -1), (-1, 1), (1, 1)] {
                context.fill(dot(x * radius * 0.25, y * radius * 0.25, radius * 0.11), with: .color(.ink))
            }
        case .seeds:
            // Seeds spiral out on the golden angle, like a sunflower head.
            for index in 0..<18 {
                let angle = Double(index) * 137.5 * .pi / 180
                let distance = radius * 0.8 * sqrt((Double(index) + 0.5) / 18)
                context.fill(dot(cos(angle) * distance, sin(angle) * distance, radius * 0.09), with: .color(.wood))
            }
        case .crossStitch:
            let arm = radius * 0.14
            for x in [-1.0, 0, 1] {
                for y in [-1.0, 0, 1] {
                    let centre = CGPoint(x: x * radius * 0.45, y: y * radius * 0.45)
                    var stitch = Path()
                    stitch.move(to: CGPoint(x: centre.x - arm, y: centre.y - arm))
                    stitch.addLine(to: CGPoint(x: centre.x + arm, y: centre.y + arm))
                    stitch.move(to: CGPoint(x: centre.x + arm, y: centre.y - arm))
                    stitch.addLine(to: CGPoint(x: centre.x - arm, y: centre.y + arm))
                    context.stroke(stitch, with: .color(.ink), lineWidth: radius * 0.07)
                }
            }
        case .star:
            context.fill(dot(0, 0, radius * 0.15), with: .color(.ink))
        case .kraft:
            // A few paper fibres.
            var random = SeededRandom(seed: 5)
            for _ in 0..<5 {
                let start = CGPoint(x: (random.next() - 0.5) * radius * 1.2, y: (random.next() - 0.5) * radius * 1.2)
                var fibre = Path()
                fibre.move(to: start)
                fibre.addLine(to: CGPoint(x: start.x + radius * 0.3, y: start.y + (random.next() - 0.5) * radius * 0.2))
                context.stroke(fibre, with: .color(.ink.opacity(0.25)), lineWidth: radius * 0.04)
            }
        }
    }
}

/// The five pot shapes. The sill gives each friend a different one.
enum PotStyle: CaseIterable {
    case tapered, tin, bowl, tallSlim, squat
}

/// A whole plant: the flower head on a paper-strip stem with 1–2 leaves, in a
/// hand-cut pot with a separate rim strip. `size` is the flower head's width.
/// The pot's bottom sits on the frame's bottom edge, so plants line up on a sill.
struct PlantView: View {
    let petal: Petal
    let pot: PotStyle
    let size: CGFloat

    private var height: CGFloat { size * 1.76 }

    var body: some View {
        Canvas { context, canvasSize in
            drawStemAndPot(in: &context, width: canvasSize.width)
        }
        .frame(width: size, height: height)
        .overlay(alignment: .top) {
            FlowerView(petal: petal, size: size)
        }
    }

    /// Stem, leaves, then pot body and rim, each with a hard shadow set by how high it sits.
    private func drawStemAndPot(in context: inout GraphicsContext, width: CGFloat) {
        var random = SeededRandom(petal.owner + "-plant")
        func paper(_ path: Path, _ colour: Color, lift: CGFloat) {
            let shadow = PaperShadow.offset(lift: lift, unit: size * 0.02)
            context.fill(path.offsetBy(dx: shadow.width, dy: shadow.height), with: .color(PaperShadow.colour(lift: lift)))
            context.fill(path, with: .color(colour))
        }
        /// Joins points with straight cuts, each nudged a little so no two pots are machine-even.
        // Edge wobble gets its own numbers, so it never changes the plant's layout.
        var edges = SeededRandom(petal.owner + "-edges")
        func cut(_ points: [CGPoint]) -> Path {
            let nudged = points.map { point in
                CGPoint(x: point.x + (random.next() - 0.5) * size * 0.016,
                        y: point.y + (random.next() - 0.5) * size * 0.016)
            }
            return RoughEdge.path(through: nudged, random: &edges)
        }

        let centreX = width / 2
        let bottom = height
        let unit = size * 0.38
        let shape = potShape(unit: unit)
        let rimHeight = unit * 0.16
        let bodyTop = bottom - shape.height
        let rimTop = bodyTop - rimHeight * 0.6

        // Stem: a slightly tapered strip from the flower centre down behind the rim.
        let stemTop = CGPoint(x: centreX, y: size / 2)
        let stemBottom = CGPoint(x: centreX + (random.next() - 0.5) * size * 0.08, y: rimTop + rimHeight * 0.3)
        let stemWidth = size * 0.045
        paper(cut([
            CGPoint(x: stemTop.x - stemWidth / 2, y: stemTop.y),
            CGPoint(x: stemTop.x + stemWidth / 2, y: stemTop.y),
            CGPoint(x: stemBottom.x + stemWidth * 0.6, y: stemBottom.y),
            CGPoint(x: stemBottom.x - stemWidth * 0.6, y: stemBottom.y),
        ]), .mat, lift: 0.7)

        // Leaves: the first on a random side, the optional second on the other side, higher up.
        let leafCount = random.next() < 0.5 ? 1 : 2
        let firstSide: CGFloat = random.next() < 0.5 ? -1 : 1
        for index in 0..<leafCount {
            let along = index == 0 ? 0.62 : 0.4
            let side = index == 0 ? firstSide : -firstSide
            let attach = CGPoint(x: stemTop.x + (stemBottom.x - stemTop.x) * along,
                                 y: stemTop.y + (stemBottom.y - stemTop.y) * along)
            let length = size * (0.32 + random.next() * 0.08)
            let angle = side * (50 + random.next() * 20) * .pi / 180
            let place = CGAffineTransform(rotationAngle: angle)
                .concatenating(CGAffineTransform(translationX: attach.x, y: attach.y))
            let leafRect = CGRect(x: -length / 2, y: -length, width: length, height: length)
            paper(PetalPath(points: Self.leafHalf).path(in: leafRect).applying(place), .mat, lift: 0.9)

            var crease = Path()
            crease.move(to: CGPoint(x: 0, y: -length * 0.08))
            crease.addLine(to: CGPoint(x: 0, y: -length * 0.85))
            context.stroke(crease.applying(place), with: .color(.cream.opacity(0.3)), lineWidth: max(0.5, size * 0.006))
        }

        // Pot body.
        let topHalf = shape.topWidth / 2
        let bottomHalf = shape.bottomWidth / 2
        var outline = [CGPoint(x: centreX - topHalf, y: bodyTop)]
        if pot == .bowl {
            // Faceted half-ellipse: a round bowl cut with a few straight snips.
            for step in 1..<7 {
                let theta = Double.pi - Double(step) / 7 * .pi
                outline.append(CGPoint(x: centreX + cos(theta) * topHalf, y: bodyTop + sin(theta) * shape.height))
            }
        } else {
            outline.append(CGPoint(x: centreX - bottomHalf, y: bottom))
            outline.append(CGPoint(x: centreX + bottomHalf, y: bottom))
        }
        outline.append(CGPoint(x: centreX + topHalf, y: bodyTop))
        paper(cut(outline), shape.body, lift: 1)

        if pot == .tin {
            // Pressed ridges round the tin.
            for step in 1...3 {
                let y = bodyTop + shape.height * Double(step) / 4
                var ridge = Path()
                ridge.move(to: CGPoint(x: centreX - bottomHalf + size * 0.01, y: y))
                ridge.addLine(to: CGPoint(x: centreX + bottomHalf - size * 0.01, y: y))
                context.stroke(ridge, with: .color(.grey.opacity(0.6)), lineWidth: max(0.5, size * 0.01))
            }
        }

        // Rim: its own strip, a little wider than the pot mouth and not quite level.
        let rimHalf = topHalf * 1.08
        let tilt = (random.next() - 0.5) * rimHeight * 0.4
        paper(cut([
            CGPoint(x: centreX - rimHalf, y: rimTop + tilt),
            CGPoint(x: centreX + rimHalf, y: rimTop - tilt),
            CGPoint(x: centreX + rimHalf, y: rimTop + rimHeight - tilt),
            CGPoint(x: centreX - rimHalf, y: rimTop + rimHeight + tilt),
        ]), shape.rim, lift: 1.3)
    }

    /// Widths, height and colours for each pot, in multiples of `unit`.
    private func potShape(unit: CGFloat) -> (topWidth: CGFloat, bottomWidth: CGFloat, height: CGFloat, body: Color, rim: Color) {
        switch pot {
        case .tapered: (unit * 1.5, unit * 1.08, unit, .wood, .sill)
        case .tin: (unit * 1.25, unit * 1.25, unit * 0.95, .sky, .grey)
        case .bowl: (unit * 1.6, unit * 1.6, unit * 0.7, .cream, .wood)
        case .tallSlim: (unit * 0.95, unit * 0.78, unit * 1.35, .sill, .wood)
        case .squat: (unit * 1.65, unit * 1.45, unit * 0.6, .grey, .cream)
        }
    }

    /// Half a leaf, in the same format as a petal's points.
    private static let leafHalf: [[Double]] = [[0, 0], [0.22, 0.18], [0.34, 0.48], [0.24, 0.8], [0, 1]]
}

extension PotStyle {
    /// Each place on the sill gets a different pot, left to right.
    static func forSill(_ index: Int) -> PotStyle {
        allCases[index % allCases.count]
    }
}

/// A friend's name under their pot.
struct NameLabel: View {
    let owner: String

    var body: some View {
        Text(SpikeUsers.name(for: owner))
            .font(Fonts.label())
            .foregroundStyle(Color.ink)
            .lineLimit(1)
    }
}

/// Every friend's plant in the window, drawn live (in the app).
/// The widget shows the same window with the plants as pre-rendered images.
struct SillView: View {
    let petals: [Petal]
    var plantSize: CGFloat = 80

    var body: some View {
        WindowScene(petals: petals) { index, petal in
            PlantView(petal: petal, pot: .forSill(index), size: plantSize)
        }
        // Room for the plants plus some window above them.
        .frame(height: plantSize * 2.6 + 26)
    }
}

#Preview("Plant") {
    PlantView(petal: Petal.samples[0], pot: .tapered, size: 200)
        .padding()
        .background(Color.wall)
}

#Preview("Sill") {
    SillView(petals: FlowerStore.defaultPetals)
        .padding()
        .background(Color.wall)
}
