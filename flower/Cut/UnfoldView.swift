import SwiftUI

/// After the cut: the folded petal opens out into the whole flower. Four small
/// flower tiles underneath pick how many petals it has; "recut" goes back to the
/// paper and "plant it" puts the flower on the sill.
struct UnfoldView: View {
    let petal: Petal
    var onRecut: () -> Void
    var onPlant: (Petal) -> Void

    @State private var count: Int
    @State private var isOpen = false
    @State private var isShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(petal: Petal, onRecut: @escaping () -> Void, onPlant: @escaping (Petal) -> Void) {
        self.petal = petal
        self.onRecut = onRecut
        self.onPlant = onPlant
        _count = State(initialValue: min(max(petal.nPetals, 5), 8))
    }

    /// The flower as it stands, with the chosen number of petals.
    private var flower: Petal {
        var flower = petal
        flower.nPetals = count
        return flower
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            // With Reduce Motion the flower is open from the start and fades in instead.
            FlowerView(petal: flower, size: 260, isOpen: isOpen || reduceMotion)
                .opacity(isShown || !reduceMotion ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: count)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("your flower, \(count) petals")
            PetalCountTiles(petal: petal, count: $count)
            HStack(spacing: 16) {
                TicketButton("recut", isPrimary: false, action: onRecut)
                TicketButton("plant it") { onPlant(flower) }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.wall)
        .overlay { PaperGrain().ignoresSafeArea() }
        .task {
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.4)) { isShown = true }
            } else {
                // A short beat on the folded petal, then it opens.
                try? await Task.sleep(for: .milliseconds(250))
                isOpen = true
            }
        }
    }
}

/// Four little flowers cut from the same petal, with 5, 6, 7 and 8 petals. Tap one
/// to give your flower that many. The chosen tile sits raised with an ink edge.
private struct PetalCountTiles: View {
    let petal: Petal
    @Binding var count: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 14) {
            ForEach(5...8, id: \.self) { option in
                let isChosen = option == count
                Button { count = option } label: {
                    FlowerView(petal: tilePetal(option), size: 40)
                        .frame(width: 48, height: 48)
                        .background {
                            Rectangle().fill(Color.ink.opacity(0.3)).offset(x: 2, y: isChosen ? 4 : 2)
                            Rectangle().fill(Color.cream)
                        }
                        .overlay {
                            Rectangle().stroke(Color.ink, lineWidth: isChosen ? 1.5 : 0)
                        }
                        .offset(y: isChosen ? -4 : 0)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(option) petals")
                .accessibilityAddTraits(isChosen ? .isSelected : [])
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: count)
    }

    private func tilePetal(_ option: Int) -> Petal {
        var tile = petal
        tile.nPetals = option
        return tile
    }
}

#Preview {
    UnfoldView(petal: Petal.samples[4], onRecut: {}, onPlant: { _ in })
}
