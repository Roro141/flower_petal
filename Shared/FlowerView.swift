import SwiftUI

/// A friend's flower head: their cut petal repeated around a centre.
/// This is the one place a flower is drawn. The app shows it directly and the
/// widget shows PNGs rendered from it.
struct FlowerView: View {
    let petal: Petal
    let size: CGFloat

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
            ForEach(Array(placements.enumerated()), id: \.offset) { _, placement in
                let length = size / 2 * placement.scale
                ZStack {
                    // Hard paper shadow, cast down and to the right in screen space.
                    PetalPath(points: petal.points)
                        .fill(Color.ink.opacity(0.22))
                        .frame(width: length, height: length)
                        .offset(y: -length / 2)
                        .rotationEffect(.degrees(placement.angle))
                        .offset(x: size * 0.012, y: size * 0.02)
                    paperPetal
                        .frame(width: length, height: length)
                        .offset(y: -length / 2)
                        .rotationEffect(.degrees(placement.angle))
                }
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
            context.fill(outline.offsetBy(dx: radius * 0.08, dy: radius * 0.12), with: .color(.ink.opacity(0.22)))
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

/// A single petal: a teardrop pointing up from the bottom-centre of its rect.
/// Stand-in for the mirrored half-petal polygon.
struct PetalShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let base = CGPoint(x: rect.midX, y: rect.maxY)
        let tip = CGPoint(x: rect.midX, y: rect.minY)
        path.move(to: base)
        path.addCurve(
            to: tip,
            control1: CGPoint(x: rect.minX - rect.width * 0.2, y: rect.maxY - rect.height * 0.35),
            control2: CGPoint(x: rect.minX + rect.width * 0.1, y: rect.minY)
        )
        path.addCurve(
            to: base,
            control1: CGPoint(x: rect.maxX - rect.width * 0.1, y: rect.minY),
            control2: CGPoint(x: rect.maxX + rect.width * 0.2, y: rect.maxY - rect.height * 0.35)
        )
        return path
    }
}

/// A flower in a pot with the friend's name underneath.
struct PottedFlowerView: View {
    let flower: Flower
    var size: CGFloat = 60

    var body: some View {
        VStack(spacing: 2) {
            bloom
                .frame(width: size, height: size)
            Rectangle()
                .fill(Color.ink.opacity(0.7))
                .frame(width: 2, height: size * 0.35)
            pot
            Text(flower.name)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(flower.name)'s flower")
    }

    private var bloom: some View {
        ZStack {
            ForEach(0..<flower.petalCount, id: \.self) { index in
                PetalShape()
                    .fill(Color(hex: flower.colorHex))
                    .frame(width: size * 0.3, height: size * 0.5)
                    .offset(y: -size * 0.25)
                    // Small per-petal wobble so the repeat is never perfectly symmetric.
                    .rotationEffect(.degrees(Double(index) * 360 / Double(flower.petalCount) + wobble(index)))
            }
            Circle()
                .fill(Color.ink)
                .frame(width: size * 0.16, height: size * 0.16)
        }
    }

    private var pot: some View {
        UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4)
            .fill(Color.wood)
            .frame(width: size * 0.55, height: size * 0.4)
    }

    /// Deterministic per-petal jitter (−6°…6°) derived from the flower id and index,
    /// so it stays stable between app and widget renders.
    private func wobble(_ index: Int) -> Double {
        var hash: UInt64 = 1469598103934665603
        for byte in "\(flower.id)-\(index)".utf8 {
            hash = (hash ^ UInt64(byte)) &* 1099511628211
        }
        return Double(hash % 13) - 6
    }
}

/// Every friend's flower side by side on one sill.
struct SillView: View {
    let flowers: [Flower]
    var flowerSize: CGFloat = 60

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 16) {
                ForEach(flowers) { flower in
                    PottedFlowerView(flower: flower, size: flowerSize)
                }
            }
            Rectangle()
                .fill(Color.sill)
                .frame(height: 8)
        }
    }
}

#Preview("Flower") {
    FlowerView(petal: Petal.samples[0], size: 240)
        .padding()
        .background(Color.wall)
}

#Preview("Spike sill") {
    SillView(flowers: FlowerStore.defaultFlowers)
        .padding()
        .background(Color.wall)
}
