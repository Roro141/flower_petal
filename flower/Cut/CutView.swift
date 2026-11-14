import SwiftUI

/// The cut in progress, in the folded sheet's coordinates: the crease is x = 0,
/// y runs down the sheet. A cut is one or more strokes joined end to end.
struct CutDrawing {
    /// A first touch this close to the crease starts the cut on it.
    static let snapDistance: CGFloat = 24
    /// Lifting this close to the crease ends the cut there.
    static let closeDistance: CGFloat = 12
    /// A new touch (finger or knife) this close to the end of the line picks the cut back up.
    static let resumeDistance: CGFloat = 44
    /// How far the cut has to go out from the crease before it can come back and close.
    static let minimumWidth: CGFloat = 40

    /// The folded sheet. The cut stays on it: points past an edge are pulled back onto it.
    let size: CGSize
    private(set) var strokes: [[CGPoint]] = []
    private(set) var isClosed = false
    private var isDrawing = false

    var lastPoint: CGPoint? { strokes.last?.last }

    private var hasLeftCrease: Bool {
        strokes.joined().contains { $0.x >= Self.minimumWidth }
    }

    /// Where the knife goes, relative to a finger that just came down: `reach` above it,
    /// or, if the finger or that spot is near the end of a paused cut, right on the end,
    /// so the cut carries on from there without a jump.
    func knifeOffset(forFingerAt finger: CGPoint, reach: CGFloat) -> CGSize {
        let above = CGPoint(x: finger.x, y: finger.y - reach)
        if !isClosed, let end = lastPoint,
           distance(finger, end) <= Self.resumeDistance || distance(above, end) <= Self.resumeDistance {
            return CGSize(width: end.x - finger.x, height: end.y - finger.y)
        }
        return CGSize(width: 0, height: -reach)
    }

    /// A finger came down: start the cut on the crease, or resume it from its end.
    /// Touches anywhere else are ignored.
    mutating func touchDown(at point: CGPoint) {
        guard !isClosed else { return }
        if let last = lastPoint {
            guard distance(point, last) <= Self.resumeDistance else { return }
            strokes.append([last])
        } else {
            guard point.x <= Self.snapDistance, (0...size.height).contains(point.y) else { return }
            strokes.append([CGPoint(x: 0, y: point.y)])
        }
        isDrawing = true
    }

    mutating func touchMoved(to point: CGPoint) {
        guard isDrawing, let last = lastPoint else { return }
        // The cut can't leave the sheet; reaching the fold closes the shape.
        let point = CGPoint(x: min(max(0, point.x), size.width), y: min(max(0, point.y), size.height))
        guard distance(point, last) >= 2 else { return }
        strokes[strokes.count - 1].append(point)
        if point.x == 0, hasLeftCrease { close() }
    }

    /// Lifting near the crease closes the cut; lifting anywhere else just pauses it.
    mutating func touchUp(at point: CGPoint) {
        guard isDrawing else { return }
        isDrawing = false
        if point.x <= Self.closeDistance, hasLeftCrease { close() }
    }

    private mutating func close() {
        if let last = lastPoint, last.x != 0 {
            strokes[strokes.count - 1].append(CGPoint(x: 0, y: last.y))
        }
        isDrawing = false
        isClosed = true
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

/// The cutting screen: a folded sheet of paper on a cutting mat. You cut half a
/// petal with your finger, starting and ending on the crease (the sheet's left edge).
struct CutView: View {
    let paper: Paper
    var onBack: () -> Void

    private static let sheetSize = CGSize(width: 260, height: 360)
    /// The knife cuts this far above the finger, so the finger never hides the line.
    private static let knifeReach: CGFloat = 44

    @State private var cut = CutDrawing(size: sheetSize)
    /// Where the knife is while a finger is down, in sheet coordinates.
    @State private var tip: CGPoint?
    /// From the finger to the knife for the current touch; set when the finger comes down.
    @State private var knifeOffset = CGSize(width: 0, height: -knifeReach)

    private var sheetSize: CGSize { Self.sheetSize }

    var body: some View {
        VStack(spacing: 0) {
            Ruler()
                .frame(height: 28)
            HStack {
                Button("back") { onBack() }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.cream)
                    .frame(minWidth: 44, minHeight: 44)
                Spacer()
            }
            .padding(.horizontal)
            Spacer()
            sheet
            Spacer()
        }
        .background {
            CuttingMat().ignoresSafeArea()
        }
        .overlay(alignment: .topTrailing) {
            if let tip {
                loupe(at: tip)
                    .padding(.top, 36)
                    .padding(.trailing, 16)
            }
        }
    }

    /// The paper and the cut so far. Drawn once on the mat and again, magnified, in the loupe.
    private var sheetLayers: some View {
        ZStack(alignment: .topLeading) {
            PaperFill(paper: paper, scale: 14)
            // The fold: a faint line along the left edge.
            Rectangle()
                .fill(Color.ink.opacity(0.25))
                .frame(width: 1.5)
            notch
            CutLine(strokes: cut.strokes)
                .stroke(Color.ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
        .frame(width: sheetSize.width, height: sheetSize.height)
    }

    private var sheet: some View {
        sheetLayers
        .overlay(alignment: .topLeading) {
            if let tip {
                Knife(tip: tip)
                    .allowsHitTesting(false)
            }
        }
        .background {
            // Hard paper shadow on the mat.
            Rectangle()
                .fill(Color.ink.opacity(0.35))
                .offset(x: 4, y: 6)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if tip == nil {
                        knifeOffset = cut.knifeOffset(forFingerAt: value.startLocation, reach: Self.knifeReach)
                        cut.touchDown(at: knifeTip(for: value.startLocation))
                    }
                    let point = knifeTip(for: value.location)
                    cut.touchMoved(to: point)
                    tip = point
                }
                .onEnded { value in
                    cut.touchUp(at: knifeTip(for: value.location))
                    tip = nil
                }
        )
    }

    /// The knife point for a finger position, kept on the sheet.
    private func knifeTip(for finger: CGPoint) -> CGPoint {
        CGPoint(x: min(max(0, finger.x + knifeOffset.width), sheetSize.width),
                y: min(max(0, finger.y + knifeOffset.height), sheetSize.height))
    }

    /// The paper around the knife tip, magnified, in a round lens.
    private func loupe(at tip: CGPoint) -> some View {
        let zoom: CGFloat = 2.5
        let diameter: CGFloat = 96
        return sheetLayers
            .scaleEffect(zoom, anchor: .topLeading)
            .offset(x: diameter / 2 - tip.x * zoom, y: diameter / 2 - tip.y * zoom)
            .frame(width: diameter, height: diameter, alignment: .topLeading)
            .background(Color.mat)
            .clipShape(Circle())
            .overlay {
                Circle().stroke(Color.cream, lineWidth: 3)
                Circle().fill(Color.ink).frame(width: 4, height: 4)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// A small V snipped into the crease, marking where the cut starts.
    private var notch: some View {
        Path { path in
            let y = sheetSize.height * 0.8
            path.move(to: CGPoint(x: 0, y: y - 6))
            path.addLine(to: CGPoint(x: 7, y: y))
            path.addLine(to: CGPoint(x: 0, y: y + 6))
            path.closeSubpath()
        }
        .fill(Color.mat)
    }
}

/// A small craft knife: a pale blade whose point sits on the cut, with the
/// handle running down towards the finger.
private struct Knife: View {
    let tip: CGPoint

    var body: some View {
        let blade = Path { path in
            path.move(to: tip)
            path.addLine(to: CGPoint(x: tip.x + 6, y: tip.y + 16))
            path.addLine(to: CGPoint(x: tip.x - 1, y: tip.y + 18))
            path.closeSubpath()
        }
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: tip.x + 3, y: tip.y + 17))
                path.addLine(to: CGPoint(x: tip.x + 8, y: tip.y + 40))
            }
            .stroke(Color.ink, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            blade.fill(Color.sky)
            blade.stroke(Color.ink, lineWidth: 1)
        }
    }
}

/// The cut so far, drawn as one joined line.
private struct CutLine: Shape {
    let strokes: [[CGPoint]]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for stroke in strokes {
            path.addLines(stroke)
        }
        return path
    }
}

/// Dark green self-healing mat with a faint grid.
private struct CuttingMat: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.mat))
            let step: CGFloat = 24
            var index = 0
            for x in stride(from: 0, through: size.width, by: step) {
                context.fill(Path(CGRect(x: x, y: 0, width: 0.5, height: size.height)),
                             with: .color(.cream.opacity(index % 5 == 0 ? 0.16 : 0.07)))
                index += 1
            }
            index = 0
            for y in stride(from: 0, through: size.height, by: step) {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.5)),
                             with: .color(.cream.opacity(index % 5 == 0 ? 0.16 : 0.07)))
                index += 1
            }
        }
    }
}

/// A plain ruler strip along the top of the mat, with ticks but no numbers.
private struct Ruler: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.cream))
            var index = 0
            for x in stride(from: CGFloat(8), through: size.width, by: 6) {
                let length = index % 10 == 0 ? size.height * 0.55 : (index % 5 == 0 ? size.height * 0.38 : size.height * 0.22)
                context.fill(Path(CGRect(x: x, y: size.height - length, width: 1, height: length)),
                             with: .color(.ink.opacity(0.6)))
                index += 1
            }
        }
    }
}

#Preview {
    CutView(paper: .dots, onBack: {})
}
