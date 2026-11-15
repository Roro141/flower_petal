import SwiftUI

/// Hand-cut edges. Each edge of a shape is broken into short runs and every point
/// along it is nudged 0.5–1.5 px (0.25–0.75 pt on a 2x screen) off the line, so no
/// piece has a machine-perfect edge. Only the outline moves; whatever is clipped to
/// it (the paper pattern) doesn't.
enum RoughEdge {
    /// Roughly how far apart the nudged points are, in points.
    private static let step: CGFloat = 6
    /// The wobble, in points: 0.5–1.5 px at 2x.
    private static let minimumWobble: CGFloat = 0.25
    private static let wobbleRange: CGFloat = 0.5

    /// A closed outline through `points`. The corners stay where they are; the
    /// points in between wobble. `random` should be seeded per shape so the same
    /// shape always gets the same edge.
    static func path(through points: [CGPoint], random: inout SeededRandom) -> Path {
        guard points.count > 2 else { return Path() }
        var path = Path()
        path.move(to: points[0])
        for index in points.indices {
            let start = points[index]
            let end = points[(index + 1) % points.count]
            let length = hypot(end.x - start.x, end.y - start.y)
            let pieces = max(1, Int(length / step))
            if pieces > 1 {
                // Unit normal to the edge: the direction the wobble pushes in.
                let normal = CGPoint(x: -(end.y - start.y) / length, y: (end.x - start.x) / length)
                for piece in 1..<pieces {
                    let t = CGFloat(piece) / CGFloat(pieces)
                    let amount = (Self.minimumWobble + random.next() * Self.wobbleRange) * (random.next() < 0.5 ? -1 : 1)
                    path.addLine(to: CGPoint(x: start.x + (end.x - start.x) * t + normal.x * amount,
                                             y: start.y + (end.y - start.y) * t + normal.y * amount))
                }
            }
            path.addLine(to: end)
        }
        path.closeSubpath()
        return path
    }
}
