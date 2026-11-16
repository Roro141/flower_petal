#if os(macOS)
import SwiftUI

/// The Mac's cutting window: drag to draw half a petal from the crease, like a finger
/// on the phone, or click to place straight points. Bringing the cut back to the
/// crease, clicking the first point, or pressing Return closes it. Delete removes the
/// last point; Esc cancels.
/// Papers sit in a column on the left. The cut becomes a petal exactly like on the
/// phone (`CutShape`) and opens out in the same `UnfoldView`.
struct MacCutView: View {
    let owner: String
    var onCancel: () -> Void
    var onPlant: (Petal) -> Void

    @State private var paper: Paper = .dots
    /// The cut so far in sheet coordinates (crease at x = 0, y down).
    @State private var points: [CGPoint] = []
    @State private var isDragging = false
    /// Set when a press didn't start (or finish) the cut, so the rest of it is ignored.
    @State private var ignoringStroke = false
    @State private var unfolding: Petal?

    private let sheetSize = CGSize(width: 300, height: 400)
    /// A first press this close to the crease starts the cut on it.
    private let snapDistance: CGFloat = 24
    /// Letting go this close to the crease closes the cut there.
    private let closeDistance: CGFloat = 12
    /// How far out the cut must go before coming back can close it.
    private let minimumWidth: CGFloat = 40

    private var hasLeftCrease: Bool { points.contains { $0.x >= minimumWidth } }

    var body: some View {
        if let petal = unfolding {
            UnfoldView(petal: petal, onRecut: {
                points = []
                unfolding = nil
            }, onPlant: onPlant)
        } else {
            cutting
        }
    }

    private var cutting: some View {
        HStack(spacing: 28) {
            // Paper choices.
            VStack(spacing: 14) {
                ForEach(Paper.allCases, id: \.self) { option in
                    Button { paper = option } label: {
                        PaperFill(paper: option, scale: 6)
                            .frame(width: 48, height: 60)
                            .overlay { Rectangle().stroke(Color.cream, lineWidth: option == paper ? 2 : 0) }
                            .background { Rectangle().fill(Color.ink.opacity(0.35)).offset(x: 2, y: 3) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(option.rawValue) paper")
                    .accessibilityAddTraits(option == paper ? .isSelected : [])
                }
            }
            sheet
            VStack(spacing: 16) {
                TicketButton("cut") { finish() }
                    .disabled(points.count < 2)
                    .opacity(points.count < 2 ? 0.5 : 1)
                TicketButton("cancel", isPrimary: false, action: onCancel)
            }
        }
        .padding(32)
        .frame(minWidth: 680, minHeight: 500)
        .background(Color.mat)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.return) { finish(); return .handled }
        .onKeyPress(.delete) { if !points.isEmpty { points.removeLast() }; return .handled }
        .onKeyPress(.escape) { onCancel(); return .handled }
    }

    private var sheet: some View {
        ZStack(alignment: .topLeading) {
            PaperFill(paper: paper, scale: 14)
            Rectangle().fill(Color.ink.opacity(0.25)).frame(width: 1.5)
            PaperGrain()
            // The cut so far, and the first point (click it to close).
            Path { path in path.addLines(points) }
                .stroke(Color.ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            if let first = points.first {
                Circle()
                    .fill(Color.cream)
                    .overlay { Circle().stroke(Color.ink, lineWidth: 1) }
                    .frame(width: 10, height: 10)
                    .position(first)
            }
        }
        .frame(width: sheetSize.width, height: sheetSize.height)
        .background { Rectangle().fill(Color.ink.opacity(0.35)).offset(x: 4, y: 6) }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        begin(at: clamp(value.startLocation))
                    }
                    extend(to: clamp(value.location))
                }
                .onEnded { value in
                    isDragging = false
                    end(at: clamp(value.location))
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("folded \(paper.rawValue) paper")
    }

    // MARK: - Drawing and placing points

    /// The mouse went down: starts the cut on the crease, closes it if it's on the first
    /// point, or otherwise joins the cut to here with a straight snip (a click).
    private func begin(at point: CGPoint) {
        ignoringStroke = false
        guard let first = points.first else {
            guard point.x <= snapDistance else { ignoringStroke = true; return }
            points = [CGPoint(x: 0, y: point.y)]
            return
        }
        if points.count > 1, hypot(point.x - first.x, point.y - first.y) < 10 {
            ignoringStroke = true
            finish()
            return
        }
        points.append(point)
    }

    /// The mouse moved with the button down: the cut follows it. Reaching the crease closes it.
    private func extend(to point: CGPoint) {
        guard !ignoringStroke, let last = points.last, hypot(point.x - last.x, point.y - last.y) >= 2 else { return }
        points.append(point)
        if point.x == 0, hasLeftCrease {
            ignoringStroke = true
            finish()
        }
    }

    /// Letting go close to the crease closes the cut there.
    private func end(at point: CGPoint) {
        if !ignoringStroke, point.x <= closeDistance, hasLeftCrease { finish() }
        ignoringStroke = false
    }

    private func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(0, point.x), sheetSize.width), y: min(max(0, point.y), sheetSize.height))
    }

    /// Closes the cut back onto the crease and opens it out into a flower.
    private func finish() {
        guard let last = points.last, points.count > 1 else { return }
        var cut = points
        if last.x != 0 { cut.append(CGPoint(x: 0, y: last.y)) }
        guard let shape = CutShape.petalPoints(from: cut) else { return }
        unfolding = Petal(id: 0, owner: owner, pattern: paper, nPetals: Int.random(in: 5...8), points: shape)
    }
}

#Preview {
    MacCutView(owner: "a", onCancel: {}, onPlant: { _ in })
}
#endif
