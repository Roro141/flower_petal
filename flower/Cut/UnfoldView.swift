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
                .accessibilityLabel("your flower")
            HStack(spacing: 16) {
                TicketButton("recut", isPrimary: false, action: onRecut)
                TicketButton("plant it", action: onPlant)
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

#Preview {
    UnfoldView(petal: Petal.samples[4], onRecut: {}, onPlant: {})
}
