import SwiftUI

/// A sheet of patterned paper, drawn in code until the scanned textures arrive in milestone 3.
/// Clip it to a shape to "cut" it, e.g. `PaperFill(paper: .dots).clipShape(PetalPath(points: ...))`.
///
/// `scale` is the pattern's repeat size in points, so small flowers get a small print.
struct PaperFill: View {
    let paper: Paper
    var scale: CGFloat = 10

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            switch paper {
            case .dots: drawDots(in: &context, rect: rect)
            case .gingham: drawGingham(in: &context, rect: rect)
            case .stripe: drawStripe(in: &context, rect: rect)
            case .ditsy: drawDitsy(in: &context, rect: rect)
            case .newsprint: drawNewsprint(in: &context, rect: rect)
            }
        }
    }

    /// Red ground, cream dots on a staggered grid.
    private func drawDots(in context: inout GraphicsContext, rect: CGRect) {
        context.fill(Path(rect), with: .color(paper.base))
        let spacing = scale * 1.6
        let radius = scale * 0.28
        var row = 0
        for y in stride(from: 0, through: rect.maxY + spacing, by: spacing * 0.87) {
            let shift = row.isMultiple(of: 2) ? 0 : spacing / 2
            for x in stride(from: -spacing, through: rect.maxX + spacing, by: spacing) {
                let dot = CGRect(x: x + shift - radius, y: y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: dot), with: .color(.cream))
            }
            row += 1
        }
    }

    /// Cream ground with see-through blue bands both ways; the crossings come out darker.
    private func drawGingham(in context: inout GraphicsContext, rect: CGRect) {
        context.fill(Path(rect), with: .color(.cream))
        let period = scale * 1.6
        let band = period / 2
        let wash = GraphicsContext.Shading.color(paper.base.opacity(0.55))
        for offset in stride(from: 0, through: max(rect.width, rect.height), by: period) {
            context.fill(Path(CGRect(x: 0, y: offset, width: rect.width, height: band)), with: wash)
            context.fill(Path(CGRect(x: offset, y: 0, width: band, height: rect.height)), with: wash)
        }
    }

    /// Lilac ground with thin cream stripes running base to tip.
    private func drawStripe(in context: inout GraphicsContext, rect: CGRect) {
        context.fill(Path(rect), with: .color(paper.base))
        let period = scale * 1.2
        for x in stride(from: period / 3, through: rect.maxX, by: period) {
            context.fill(Path(CGRect(x: x, y: 0, width: scale * 0.35, height: rect.height)),
                         with: .color(.cream.opacity(0.8)))
        }
    }

    /// Yellow ground scattered with tiny white and red specks.
    private func drawDitsy(in context: inout GraphicsContext, rect: CGRect) {
        context.fill(Path(rect), with: .color(paper.base))
        // Fixed seed: the same paper looks the same in the app and the widget.
        var random = SeededRandom(seed: 7)
        let count = Int(rect.width * rect.height / (scale * scale) * 2.5)
        for index in 0..<count {
            let isRed = index.isMultiple(of: 3)
            let radius = scale * (isRed ? 0.13 : 0.18)
            let center = CGPoint(x: random.next() * rect.width, y: random.next() * rect.height)
            let speck = CGRect(x: center.x - radius, y: center.y - radius * 0.8, width: radius * 2, height: radius * 1.6)
            context.fill(Path(ellipseIn: speck), with: .color(isRed ? Color(hex: "#C8473B") : .white))
        }
    }

    /// Orange ground with broken ink lines, like rows of tiny type.
    private func drawNewsprint(in context: inout GraphicsContext, rect: CGRect) {
        context.fill(Path(rect), with: .color(paper.base))
        var random = SeededRandom(seed: 3)
        let ink = GraphicsContext.Shading.color(.ink.opacity(0.5))
        let thickness = scale * 0.14
        for y in stride(from: scale * 0.5, through: rect.maxY, by: scale * 0.7) {
            var x = -random.next() * scale * 2
            while x < rect.maxX {
                let word = scale * (0.8 + random.next() * 2.2)
                context.fill(Path(CGRect(x: x, y: y, width: word, height: thickness)), with: ink)
                x += word + scale * 0.35
            }
        }
    }
}

/// A tiny deterministic random generator (an LCG), so patterns and per-owner
/// choices come out the same on every render and every device.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 6364136223846793005 &+ 1442695040888963407
    }

    /// Seeds from a string (e.g. an owner id) with FNV-1a; Swift's own hashing
    /// changes between launches, so it can't be used here.
    init(_ string: String) {
        var hash: UInt64 = 1469598103934665603
        for byte in string.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1099511628211
        }
        self.init(seed: hash)
    }

    /// The next value in 0..<1.
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

#Preview {
    HStack(spacing: 8) {
        ForEach(Paper.allCases, id: \.self) { paper in
            PaperFill(paper: paper)
                .frame(width: 60, height: 90)
        }
    }
    .padding()
    .background(Color.wall)
}
