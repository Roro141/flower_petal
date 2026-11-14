import SwiftUI

/// After the cut: the folded petal opens out into the whole flower.
/// "recut" goes back to the paper; "plant it" puts the flower on the sill.
struct UnfoldView: View {
    let petal: Petal
    var onRecut: () -> Void
    var onPlant: () -> Void

    @State private var isOpen = false
    @State private var isShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            // With Reduce Motion the flower is open from the start and fades in instead.
            FlowerView(petal: petal, size: 260, isOpen: isOpen || reduceMotion)
                .opacity(isShown || !reduceMotion ? 1 : 0)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(SpikeUsers.name(for: petal.owner))'s flower")
            HStack(spacing: 16) {
                Button("recut", action: onRecut)
                    .buttonStyle(InkButtonStyle(isPrimary: false))
                Button("plant it", action: onPlant)
                    .buttonStyle(InkButtonStyle(isPrimary: true))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.wall)
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

/// Plain dark buttons for the cut flow. Step 6 replaces these with ticket buttons.
struct InkButtonStyle: ButtonStyle {
    var isPrimary = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(isPrimary ? Color.cream : Color.ink)
            .padding(.horizontal, 20)
            .frame(minHeight: 44)
            .background(isPrimary ? Color.ink : Color.cream, in: .rect(cornerRadius: 4))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

#Preview {
    UnfoldView(petal: Petal.samples[4], onRecut: {}, onPlant: {})
}
