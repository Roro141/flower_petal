import SwiftUI

extension CutDrawing {
    /// The finished cut as a petal's half-polygon (see `Petal.points`), or nil
    /// while the cut isn't closed yet.
    var petalPoints: [[Double]]? {
        guard isClosed else { return nil }
        return CutShape.petalPoints(from: Array(strokes.joined()))
    }
}

/// Turns a cut drawn on the folded sheet into the stored petal format.
enum CutShape {
    static let pointCount = 5...12

    /// `cut` is in sheet coordinates (crease at x = 0, y down) and starts and ends
    /// on the crease. Returns [x, y] pairs normalized 0–1, from the base [0, 0]
    /// to the tip, with 5–12 points.
    static func petalPoints(from cut: [CGPoint]) -> [[Double]]? {
        var points = removingRepeats(cut)
        guard points.count >= 3 else { return nil }

        // Petals grow upwards, so the base is whichever end sits lower on the sheet.
        if let first = points.first, let last = points.last, first.y < last.y {
            points.reverse()
        }

        // Base to [0, 0]; flip y so it points up; scale so the shape fits in 0–1
        // without being stretched.
        let base = points[0]
        let height = points.map { base.y - $0.y }.max() ?? 0
        let width = points.map(\.x).max() ?? 0
        let size = max(height, width)
        guard size > 0 else { return nil }
        let normalized = points.map { point in
            CGPoint(x: min(max(point.x / size, 0), 1), y: min(max((base.y - point.y) / size, 0), 1))
        }

        var simple = simplified(normalized)
        if simple.count < pointCount.lowerBound {
            simple = resampled(normalized, count: pointCount.lowerBound)
        }
        // Both ends sit exactly on the fold.
        simple[0].x = 0
        simple[simple.count - 1].x = 0
        return simple.map { [rounded($0.x), rounded($0.y)] }
    }

    /// The petal made fuller (factor > 1) or slimmer (< 1) by scaling its width,
    /// kept within the petal's square.
    static func widened(_ points: [[Double]], by factor: Double) -> [[Double]] {
        points.map { pair in
            guard pair.count == 2 else { return pair }
            return [rounded(CGFloat(min(pair[0] * factor, 1))), pair[1]]
        }
    }

    /// The cut so far as a petal, closed straight back to the crease, for the live
    /// preview while it's still being cut. nil until there's enough of a line.
    static func previewPoints(from cut: [CGPoint]) -> [[Double]]? {
        var points = removingRepeats(cut)
        guard let last = points.last, points.count >= 2 else { return nil }
        if last.x != 0 { points.append(CGPoint(x: 0, y: last.y)) }
        guard points.contains(where: { $0.x > 1 }) else { return nil }
        return petalPoints(from: points)
    }

    /// Fewest points that keep the shape: Ramer–Douglas–Peucker, loosening the
    /// tolerance until there are at most 12.
    private static func simplified(_ points: [CGPoint]) -> [CGPoint] {
        var tolerance: CGFloat = 0.01
        var result = douglasPeucker(points, tolerance: tolerance)
        while result.count > pointCount.upperBound {
            tolerance *= 1.4
            result = douglasPeucker(points, tolerance: tolerance)
        }
        return result
    }

    private static func douglasPeucker(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var keep = Array(repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var spans = [(0, points.count - 1)]
        while let (start, end) = spans.popLast() {
            var farthest = start
            var farthestDistance: CGFloat = 0
            for index in (start + 1)..<max(start + 1, end) {
                let distance = distanceFromSegment(points[index], points[start], points[end])
                if distance > farthestDistance {
                    farthest = index
                    farthestDistance = distance
                }
            }
            if farthestDistance > tolerance {
                keep[farthest] = true
                spans.append((start, farthest))
                spans.append((farthest, end))
            }
        }
        return points.indices.filter { keep[$0] }.map { points[$0] }
    }

    /// `count` points evenly spaced along the line, for cuts too plain to keep 5 corners.
    private static func resampled(_ points: [CGPoint], count: Int) -> [CGPoint] {
        let lengths = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        let total = lengths.reduce(0, +)
        guard total > 0 else { return points }
        var result = [points[0]]
        var segment = 0
        var walked: CGFloat = 0
        for step in 1..<(count - 1) {
            let target = total * CGFloat(step) / CGFloat(count - 1)
            while segment < lengths.count - 1, walked + lengths[segment] < target {
                walked += lengths[segment]
                segment += 1
            }
            let t = lengths[segment] > 0 ? (target - walked) / lengths[segment] : 0
            let a = points[segment]
            let b = points[segment + 1]
            result.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
        result.append(points[points.count - 1])
        return result
    }

    private static func distanceFromSegment(_ point: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        let t = min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared, 0), 1)
        return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
    }

    /// Resuming a cut repeats the point it resumed from; drop those.
    private static func removingRepeats(_ points: [CGPoint]) -> [CGPoint] {
        points.reduce(into: []) { result, point in
            if result.last != point { result.append(point) }
        }
    }

    /// Three decimals is far finer than a finger, and keeps the stored row small.
    private static func rounded(_ value: CGFloat) -> Double {
        (Double(value) * 1000).rounded() / 1000
    }
}

#Preview {
    // A hand-drawn-ish wobbly cut, cut from the notch up and back, turned into a flower.
    let cut: [CGPoint] = (0...40).map { step in
        let t = Double(step) / 40
        let angle = t * .pi
        return CGPoint(x: sin(angle) * 90 + sin(t * 37) * 3, y: 300 - t * 230 - sin(angle * 2) * 12)
    }
    let points = CutShape.petalPoints(from: cut) ?? []
    return FlowerView(
        petal: Petal(id: 0, owner: "a", pattern: .dots, nPetals: 6, points: points),
        size: 240
    )
    .padding()
    .background(Color.wall)
}
