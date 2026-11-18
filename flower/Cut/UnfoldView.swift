import SwiftUI

/// After the cut: the folded petal opens out into the whole flower, then the tweaks
/// come up underneath (petal count, fullness, centre and paper). Every tweak shows
/// on the flower straight away, with no recut. "recut" goes back to the paper and
/// "plant it" puts the flower on the sill.
struct UnfoldView: View {
    let petal: Petal
    var onRecut: () -> Void
    var onPlant: (Petal) -> Void

    @State private var count: Int
    /// Scales the petal's width: 0.8 slim to 1.2 full.
    @State private var fullness = 1.0
    @State private var centre: FlowerCentre
    @State private var paper: Paper
    @State private var isOpen = false
    @State private var isShown = false
    /// The tweaks appear once the flower has opened.
    @State private var showsTweaks = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(petal: Petal, onRecut: @escaping () -> Void, onPlant: @escaping (Petal) -> Void) {
        self.petal = petal
        self.onRecut = onRecut
        self.onPlant = onPlant
        _count = State(initialValue: min(max(petal.nPetals, 5), 8))
        _centre = State(initialValue: petal.centre ?? FlowerCentre.for(owner: petal.owner))
        _paper = State(initialValue: petal.pattern)
    }

    /// The flower as it stands, with every tweak applied.
    private var flower: Petal {
        var flower = petal
        flower.nPetals = count
        flower.points = CutShape.widened(petal.points, by: fullness)
        flower.centre = centre
        flower.pattern = paper
        return flower
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    // With Reduce Motion the flower is open from the start and fades in instead.
                    FlowerView(petal: flower, size: 220, isOpen: isOpen || reduceMotion)
                        .opacity(isShown || !reduceMotion ? 1 : 0)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: count)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("your flower")
                        .accessibilityValue("\(count) petals, \(paper.rawValue) paper, \(centre.name) centre")
                    tweaks
                        .opacity(showsTweaks ? 1 : 0)
                        .disabled(!showsTweaks)
                        .accessibilityHidden(!showsTweaks)
                    HStack(spacing: 16) {
                        TicketButton("recut", isPrimary: false, action: onRecut)
                        TicketButton("plant it") { onPlant(flower) }
                    }
                }
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color.wall)
        .overlay { PaperGrain().ignoresSafeArea().allowsHitTesting(false) }
        #if os(macOS)
        .frame(minWidth: 680, minHeight: 720)
        #endif
        .task {
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.2)) {
                    isShown = true
                    showsTweaks = true
                }
            } else {
                // A short beat on the folded petal, then it opens, then the tweaks come up.
                try? await Task.sleep(for: .milliseconds(250))
                isOpen = true
                try? await Task.sleep(for: .seconds(1))
                withAnimation(.easeOut(duration: 0.2)) { showsTweaks = true }
            }
        }
    }

    private var tweaks: some View {
        VStack(spacing: 18) {
            TweakRow("petals") { PetalCountTiles(petal: flower, count: $count) }
            TweakRow("fullness") { FullnessSlider(value: $fullness, petal: petal.points) }
            TweakRow("centre") { CentreTiles(selection: $centre) }
            // The chosen paper sits raised 10 pt; room for it under the label.
            TweakRow("paper") { PaperFan(selection: $paper).padding(.top, 10) }
        }
    }
}

/// One tweak: a small typewritten label over its control. The label is for the eye;
/// each control says what it is to VoiceOver itself.
private struct TweakRow<Control: View>: View {
    let label: String
    @ViewBuilder var control: Control

    init(_ label: String, @ViewBuilder control: () -> Control) {
        self.label = label
        self.control = control()
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(Fonts.controlLabel())
                .foregroundStyle(Color.grey)
                .accessibilityHidden(true)
            control
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
                        .chosenTile(isChosen)
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

/// The five centres on little tiles, picked the same way as the petal count.
private struct CentreTiles: View {
    @Binding var selection: FlowerCentre
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            ForEach(FlowerCentre.pickerOrder, id: \.self) { style in
                let isChosen = style == selection
                Button { selection = style } label: {
                    CentreView(style: style, diameter: 24, turn: 8)
                        .frame(width: 48, height: 48)
                        .chosenTile(isChosen)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(style.name) centre")
                .accessibilityAddTraits(isChosen ? .isSelected : [])
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: selection)
    }
}

/// How full the petals are, from slim (0.8) to full (1.2): a strip of kraft paper
/// with a tab you slide along it, between a slim and a full petal. The whole strip
/// is 44 pt tall to touch; VoiceOver adjusts it in steps.
private struct FullnessSlider: View {
    @Binding var value: Double
    /// The cut petal, drawn slim and full at the two ends.
    let petal: [[Double]]

    private static let range = 0.8...1.2
    private static let step = 0.05
    private let trackWidth: CGFloat = 200
    /// Where the strip starts in the row: after the slim petal (20) and the gap (12).
    private let trackStart: CGFloat = 32

    private var fraction: CGFloat {
        (value - Self.range.lowerBound) / (Self.range.upperBound - Self.range.lowerBound)
    }

    var body: some View {
        HStack(spacing: 12) {
            end(0.55)
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.wood)
                    .frame(height: 6)
                    .background { Rectangle().fill(Color.ink.opacity(0.3)).offset(x: 1, y: 2) }
                Rectangle()
                    .fill(Color.ink)
                    .frame(width: 14, height: 30)
                    .background { Rectangle().fill(Color.ink.opacity(0.3)).offset(x: 2, y: 3) }
                    .offset(x: fraction * (trackWidth - 14))
            }
            .frame(width: trackWidth, height: 44)
            end(1.6)
        }
        // The whole row slides it, petals too: the slim one is 0.8, the full one 1.2.
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0).onChanged { drag in
                let x = min(max(0, drag.location.x - trackStart - 7), trackWidth - 14) / (trackWidth - 14)
                let raw = Self.range.lowerBound + x * (Self.range.upperBound - Self.range.lowerBound)
                value = (raw * 100).rounded() / 100
            }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("fullness")
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + Self.step, Self.range.upperBound)
            case .decrement: value = max(value - Self.step, Self.range.lowerBound)
            @unknown default: break
            }
        }
    }

    /// A tiny ink petal at one end of the strip, slim or full; exaggerated past the
    /// real range so the two ends read as different at this size.
    private func end(_ factor: Double) -> some View {
        PetalPath(points: CutShape.widened(petal, by: factor))
            .fill(Color.ink.opacity(0.6))
            .frame(width: 20, height: 20)
    }
}

private extension View {
    /// A cream tile; the chosen one sits raised with an ink edge.
    func chosenTile(_ isChosen: Bool) -> some View {
        self
            .background {
                Rectangle().fill(Color.ink.opacity(0.3)).offset(x: 2, y: isChosen ? 4 : 2)
                Rectangle().fill(Color.cream)
            }
            .overlay {
                Rectangle().stroke(Color.ink, lineWidth: isChosen ? 1.5 : 0)
            }
            .offset(y: isChosen ? -4 : 0)
    }
}

#Preview {
    UnfoldView(petal: Petal.samples[4], onRecut: {}, onPlant: { _ in })
}
