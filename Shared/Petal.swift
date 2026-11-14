import SwiftUI

/// The five papers a petal can be cut from.
enum Paper: String, Codable, CaseIterable, Sendable {
    case dots, gingham, stripe, ditsy, newsprint

    /// The paper's ground colour.
    var base: Color {
        switch self {
        case .dots: Color(hex: "#D9574C")
        case .gingham: Color(hex: "#3A6EA5")
        case .stripe: Color(hex: "#A77AA5")
        case .ditsy: Color(hex: "#EDB93F")
        case .newsprint: Color(hex: "#EE8A4E")
        }
    }
}

/// One friend's cut petal. `points` is the right half of a single petal,
/// normalized 0–1, from the base [0, 0] on the fold (x = 0) up to the tip near [0, 1].
struct Petal: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    var owner: String
    var pattern: Paper
    var nPetals: Int        // 5–8
    var points: [[Double]]
    var createdAt: Date?
}

/// A whole petal: the half-polygon mirrored across the fold, with corners
/// softened a little so it reads as scissor cuts rather than perfect curves.
///
/// Fills its rect with the base at bottom-centre and the tip at the top.
/// x = ±1 reaches the rect's left/right edges.
struct PetalPath: Shape {
    let points: [[Double]]

    /// How far along each edge the corner rounding starts (0 = sharp corners).
    private let softness = 0.18

    func path(in rect: CGRect) -> Path {
        let half = points.compactMap { pair -> CGPoint? in
            guard pair.count == 2 else { return nil }
            return CGPoint(x: pair[0], y: pair[1])
        }
        guard half.count >= 3 else { return Path() }

        // Right half base → tip, then the mirror image tip → base. Points that sit
        // on the fold are shared by both halves, so don't repeat them.
        var mirrored = half.reversed().map { CGPoint(x: -$0.x, y: $0.y) }
        if let last = half.last, last.x == 0 { mirrored.removeFirst() }
        if let first = half.first, first.x == 0, !mirrored.isEmpty { mirrored.removeLast() }

        let polygon = (half + mirrored).map { point in
            CGPoint(
                x: rect.midX + point.x * rect.width / 2,
                y: rect.maxY - point.y * rect.height
            )
        }
        return softenedPolygon(polygon)
    }

    /// Straight edges, with each corner replaced by a short quadratic curve.
    private func softenedPolygon(_ vertices: [CGPoint]) -> Path {
        let count = vertices.count
        func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        // For each corner: where the curve enters (on the incoming edge) and leaves.
        let entries = vertices.indices.map { lerp(vertices[$0], vertices[($0 + count - 1) % count], softness) }
        let exits = vertices.indices.map { lerp(vertices[$0], vertices[($0 + 1) % count], softness) }

        var path = Path()
        path.move(to: entries[0])
        for index in vertices.indices {
            path.addQuadCurve(to: exits[index], control: vertices[index])
            path.addLine(to: entries[(index + 1) % count])
        }
        path.closeSubpath()
        return path
    }
}

extension Petal {
    /// Five hand-made half-petals, for the sample screen and for spike rows with no points.
    static let sampleShapes: [[[Double]]] = [
        // rounded
        [[0, 0], [0.18, 0.08], [0.32, 0.25], [0.38, 0.48], [0.34, 0.7], [0.22, 0.88], [0.08, 0.97], [0, 1]],
        // pointed
        [[0, 0], [0.14, 0.12], [0.26, 0.32], [0.29, 0.52], [0.2, 0.72], [0.09, 0.88], [0, 1]],
        // notched tip
        [[0, 0], [0.16, 0.1], [0.3, 0.3], [0.36, 0.55], [0.34, 0.78], [0.26, 0.96], [0.15, 0.93], [0.07, 0.85], [0, 0.88]],
        // slim
        [[0, 0], [0.07, 0.15], [0.12, 0.4], [0.13, 0.65], [0.09, 0.86], [0, 1]],
        // heart notch
        [[0, 0], [0.2, 0.12], [0.36, 0.34], [0.42, 0.6], [0.37, 0.84], [0.23, 0.95], [0.09, 0.9], [0, 0.78]],
    ]

    /// One sample petal per shape, each on a different paper with a different count.
    /// The owner ids are picked so the five samples get five different centres.
    static let samples: [Petal] = sampleShapes.enumerated().map { index, shape in
        Petal(
            id: -(index + 1),
            owner: ["sample-0", "sample-2", "sample-3", "sample-5", "sample-7"][index],
            pattern: Paper.allCases[index % Paper.allCases.count],
            nPetals: [6, 5, 7, 8, 5][index],
            points: shape
        )
    }
}
