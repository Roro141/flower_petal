import SwiftUI

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

#Preview {
    SillView(flowers: FlowerStore.defaultFlowers)
        .padding()
        .background(Color.wall)
}
