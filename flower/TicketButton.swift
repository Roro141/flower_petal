import SwiftUI

/// The app's primary button: a paper ticket with a perforated stub.
///
/// On release the body tilts slightly and the stub tears off and falls, and the
/// action runs in the same frame (no waiting for the animation). The full tear only
/// plays on the first press after the app opens; later presses get a quick tick.
/// With Reduce Motion the stub just dims to 40%.
struct TicketButton: View {
    let title: String
    var isPrimary = true
    let action: () -> Void

    /// Whether any ticket has torn since the app opened.
    private static var hasTorn = false
    private static let stubWidth: CGFloat = 22

    @State private var isTorn = false
    @State private var isDimmed = false
    @State private var ticks = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ title: String, isPrimary: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.isPrimary = isPrimary
        self.action = action
    }

    var body: some View {
        Button(action: press) {
            Text(title)
                .font(Fonts.button())
                .foregroundStyle(isPrimary ? Color.cream : Color.ink)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background { paper(TicketPiece(notchedEdge: .trailing)) }
                .background(alignment: .trailing) {
                    stub
                        .frame(width: Self.stubWidth)
                        .offset(x: Self.stubWidth)
                }
                .rotationEffect(.degrees(isTorn ? -3 : 0), anchor: .bottomLeading)
                .animation(.easeOut(duration: 0.18), value: isTorn)
                .padding(.trailing, Self.stubWidth)
                .keyframeAnimator(initialValue: CGFloat(0), trigger: ticks) { content, y in
                    content.offset(y: y)
                } keyframes: { _ in
                    LinearKeyframe(1.5, duration: 0.06)
                    LinearKeyframe(0, duration: 0.06)
                }
        }
        .buttonStyle(.plain)
    }

    /// The stub: a short piece past the perforation that tears off and drops.
    private var stub: some View {
        paper(TicketPiece(notchedEdge: .leading))
            .overlay(alignment: .leading) {
                Path { path in
                    path.move(to: .zero)
                    path.addLine(to: CGPoint(x: 0, y: 200))
                }
                .stroke(perforation, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .clipped()
            }
            .opacity(isDimmed ? 0.4 : (isTorn ? 0 : 1))
            .rotationEffect(.degrees(isTorn ? 28 : 0), anchor: .topLeading)
            .offset(y: isTorn ? 70 : 0)
            .animation(.timingCurve(0.5, 0, 0.75, 0, duration: 0.35), value: isTorn)
            .accessibilityHidden(true)
    }

    private var perforation: Color {
        isPrimary ? .cream.opacity(0.6) : .ink.opacity(0.4)
    }

    /// A piece of ticket with the same hard shadow as the other paper pieces.
    private func paper(_ shape: TicketPiece) -> some View {
        ZStack {
            shape.fill(Color.ink.opacity(0.35)).offset(x: 2, y: 3)
            shape.fill(isPrimary ? Color.ink : Color.cream)
        }
    }

    private func press() {
        if reduceMotion {
            isDimmed = true
        } else if !Self.hasTorn {
            Self.hasTorn = true
            isTorn = true
            // If this button stays on screen, a fresh stub is back in place after the fall.
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { isTorn = false }
            }
        } else {
            ticks += 1
        }
        action()
    }
}

/// A rectangle with small round notches punched where the body meets the stub.
private struct TicketPiece: Shape {
    let notchedEdge: HorizontalEdge

    func path(in rect: CGRect) -> Path {
        let x = notchedEdge == .trailing ? rect.maxX : rect.minX
        let radius: CGFloat = 4
        var notches = Path()
        for y in [rect.minY, rect.maxY] {
            notches.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        }
        return Path(rect).subtracting(notches)
    }
}

#Preview {
    VStack(spacing: 24) {
        TicketButton("plant it") {}
        TicketButton("recut", isPrimary: false) {}
    }
    .padding(40)
    .background(Color.wall)
}
