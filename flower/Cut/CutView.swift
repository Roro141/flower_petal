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

    /// Cut started, finger lifted, but not back on the crease yet.
    var isPaused: Bool { !strokes.isEmpty && !isClosed && !isDrawing }

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

    /// Takes off the last stroke (and with it, closing the cut if that stroke did).
    mutating func undo() {
        guard !strokes.isEmpty else { return }
        strokes.removeLast()
        isClosed = false
        isDrawing = false
    }

    mutating func clear() {
        strokes = []
        isClosed = false
        isDrawing = false
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
    /// Whose petal this is (the signed-in person).
    let owner: String
    var onBack: () -> Void
    /// Called with the finished petal when "plant it" is tapped.
    var onPlant: (Petal) -> Void

    /// The paper being cut; picked from the fan.
    @State private var paper: Paper

    init(owner: String, paper: Paper, onBack: @escaping () -> Void, onPlant: @escaping (Petal) -> Void) {
        self.owner = owner
        _paper = State(initialValue: paper)
        self.onBack = onBack
        self.onPlant = onPlant
    }

    private static let sheetSize = CGSize(width: 260, height: 360)
    /// The knife cuts this far above the finger, so the finger never hides the line.
    private static let knifeReach: CGFloat = 44
    /// Cut ⇄ unfold cross-fade; as long as the ticket stub's fall, so it's seen falling.
    private static let pageTurn = Animation.easeOut(duration: 0.35)

    @State private var cut = CutDrawing(size: sheetSize)
    /// Where the knife is while a finger is down, in sheet coordinates.
    @State private var tip: CGPoint?
    /// From the finger to the knife for the current touch; set when the finger comes down.
    @State private var knifeOffset = CGSize(width: 0, height: -knifeReach)
    /// Bumped each time a lift leaves the cut unfinished; drives the sheet's small nudge.
    @State private var nudges = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The cut, opened out into a flower, once "cut" is tapped.
    @State private var unfolding: Petal?
    /// How many petals the flower will have; picked now so the live preview matches
    /// what unfolds. Can be changed after the unfold.
    @State private var count = Int.random(in: 5...8)
    /// The how-to cards: shown the first time this screen opens, and again from "?".
    /// The how-to cards: once, the first time this screen opens. (Kept for a later
    /// setting to bring them back.)
    @AppStorage("hasSeenHowToCut") private var hasSeenHowTo = false
    @State private var showsHowTo = false
    /// The animation on the paper, from "?": the knife traces a cut and the preview
    /// shows the flower it makes, circled.
    @State private var showsGuide = false
    /// Bumped by "?" so the animation plays again from the start.
    @State private var guidePlays = 0

    /// The flower the cut so far would make, rebuilt on every drag update.
    private var preview: Petal? {
        CutShape.previewPoints(from: Array(cut.strokes.joined())).map { points in
            Petal(id: 0, owner: owner, pattern: paper, nPetals: count, points: points)
        }
    }

    private var sheetSize: CGSize { Self.sheetSize }

    var body: some View {
        if let petal = unfolding {
            UnfoldView(
                petal: petal,
                onRecut: {
                    cut.clear()
                    withAnimation(Self.pageTurn) { unfolding = nil }
                },
                onPlant: { flower in onPlant(flower) }
            )
            .transition(.opacity)
        } else {
            cutting
                .transition(.opacity)
                .overlay {
                    if showsHowTo {
                        HowToCut {
                            hasSeenHowTo = true
                            withAnimation(.easeOut(duration: 0.2)) { showsHowTo = false }
                        }
                        .transition(.opacity)
                    }
                }
        }
    }

    private var cutting: some View {
        VStack(spacing: 0) {
            Ruler()
                .frame(height: 28)
            HStack {
                BackArrow(action: onBack)
                    .frame(width: 56, alignment: .leading)
                Spacer()
                PaperFan(selection: $paper)
                Spacer()
                // The flower the cut so far makes (while the animation plays, the one its
                // cut makes, circled). Same width as the back arrow's slot, so the fan
                // stays in the middle.
                ZStack {
                    // Holds the slot open when it's empty, so the fan never shifts.
                    Color.clear
                    if let preview {
                        FlowerView(petal: preview, size: 56)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("your flower so far")
                    } else if showsGuide,
                              let example = CutGuide.flower(owner: owner, paper: paper, count: count, sheet: sheetSize) {
                        FlowerView(petal: example, size: 56)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: 56, height: 56)
                .overlay(alignment: .topTrailing) {
                    if showsGuide {
                        PreviewCallout(width: 74, height: 70)
                            .padding(.top, -7)
                            .padding(.trailing, -9)
                            .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            Spacer()
            sheet
            PresetTiles(paper: paper) { unfold($0) }
                .padding(.top, 24)
            HStack(spacing: 24) {
                UndoTab(isEnabled: !cut.strokes.isEmpty, onUndo: { cut.undo() }, onClear: { cut.clear() })
                if let points = cut.petalPoints {
                    TicketButton("cut") { unfold(points) }
                }
            }
            .padding(.top, 16)
            Spacer()
        }
        .background {
            CuttingMat().ignoresSafeArea()
        }
        // "?" in the bottom corner brings the how-to back.
        .overlay(alignment: .bottomTrailing) {
            HelpTab { playGuide() }
                .padding(.trailing, 16)
                .padding(.bottom, 4)
        }
        .onAppear {
            if !hasSeenHowTo { showHowTo() }
        }
        // Top left, over the back arrow while cutting, so the live preview stays in view.
        .overlay(alignment: .topLeading) {
            if let tip {
                loupe(at: tip)
                    .padding(.top, 36)
                    .padding(.leading, 16)
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
            PaperGrain()
            // Where to start and finish, until the cut is closed.
            if !cut.isClosed {
                FoldMarks(size: sheetSize)
            }
            CutLine(strokes: cut.strokes)
                .stroke(Color.ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            // Unfinished: a faint dashed ghost from the end of the cut back to the crease.
            if cut.isPaused, let end = cut.lastPoint {
                Path { path in
                    path.move(to: end)
                    path.addLine(to: CGPoint(x: 0, y: end.y))
                }
                .stroke(Color.ink.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }
        }
        .frame(width: sheetSize.width, height: sheetSize.height)
    }

    private var sheet: some View {
        sheetLayers
        .overlay(alignment: .topLeading) {
            if showsGuide {
                CutGuide(size: sheetSize)
                    .id(guidePlays)
                    .transition(.opacity)
            }
        }
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("folded \(paper.rawValue) paper")
        .accessibilityHint(CutGuide.spokenHint)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if tip == nil {
                        hideGuide()
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
                    if cut.isPaused, !reduceMotion { nudges += 1 }
                }
        )
        // A small 4 pt nudge towards the crease, then back.
        .keyframeAnimator(initialValue: CGFloat(0), trigger: nudges) { content, x in
            content.offset(x: x)
        } keyframes: { _ in
            CubicKeyframe(-4, duration: 0.08)
            SpringKeyframe(0, duration: 0.3)
        }
    }

    private func showHowTo() {
        withAnimation(.easeOut(duration: 0.2)) { showsHowTo = true }
    }

    private func playGuide() {
        guidePlays += 1
        withAnimation(.easeOut(duration: 0.2)) { showsGuide = true }
    }

    /// The first touch on the paper puts the animation away.
    private func hideGuide() {
        guard showsGuide else { return }
        withAnimation(.easeOut(duration: 0.2)) { showsGuide = false }
    }

    private func unfold(_ points: [[Double]]) {
        let petal = Petal(
            id: 0,
            owner: owner,
            pattern: paper,
            nPetals: count,
            points: points
        )
        withAnimation(Self.pageTurn) { unfolding = petal }
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

/// The five papers as a small fan of sheets; the chosen one sits raised.
/// Used on the cutting screen and again when tweaking the flower.
struct PaperFan: View {
    @Binding var selection: Paper
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: -4) {
            ForEach(Array(Paper.allCases.enumerated()), id: \.element) { index, paper in
                let isSelected = paper == selection
                let spread = Double(index - Paper.allCases.count / 2)
                Button { selection = paper } label: {
                    PaperFill(paper: paper, scale: 6)
                        .frame(width: 40, height: 52)
                        // The chosen sheet gets a cream border, like a photo corner.
                        .overlay { Rectangle().strokeBorder(Color.cream, lineWidth: isSelected ? 2.5 : 0) }
                        .scaleEffect(isSelected ? 1.08 : 1, anchor: .bottom)
                        .background {
                            Rectangle().fill(Color.ink.opacity(0.35)).offset(x: 2, y: 3)
                        }
                        .frame(width: 48, height: 60)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .rotationEffect(.degrees(spread * 9), anchor: .bottom)
                .offset(y: isSelected ? -10 : abs(spread) * 3)
                .zIndex(isSelected ? 1 : 0)
                .accessibilityLabel("\(paper.rawValue) paper")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: selection)
    }
}

/// Four ready-made petals as small cut-paper tiles. Tapping one skips drawing and
/// goes straight to the unfold, so the flow works without a finger cut (and with VoiceOver).
private struct PresetTiles: View {
    let paper: Paper
    var onPick: ([[Double]]) -> Void

    private static let presets: [(name: String, shape: [[Double]])] = [
        ("rounded", Petal.sampleShapes[0]),
        ("pointed", Petal.sampleShapes[1]),
        ("notched", Petal.sampleShapes[2]),
        ("heart", Petal.sampleShapes[4]),
    ]
    /// Each tile sits a little crooked, as if stuck down by hand.
    private static let tilts: [Double] = [-3, 2, -1.5, 3.5]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Array(Self.presets.enumerated()), id: \.element.name) { index, preset in
                Button { onPick(preset.shape) } label: {
                    PaperFill(paper: paper, scale: 5)
                        .clipShape(PetalPath(points: preset.shape))
                        .padding(6)
                        .frame(width: 48, height: 48)
                        .background {
                            Rectangle().fill(Color.ink.opacity(0.35)).offset(x: 2, y: 3)
                            Rectangle().fill(Color.cream)
                        }
                }
                .buttonStyle(.plain)
                .rotationEffect(.degrees(Self.tilts[index]))
                .accessibilityLabel("\(preset.name) petal")
            }
        }
    }
}

/// Back, as a little hand-cut paper arrow with its own shadow.
private struct BackArrow: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                ArrowShape().fill(Color.ink.opacity(0.35)).offset(x: 2, y: 3)
                ArrowShape().fill(Color.cream)
            }
            .frame(width: 36, height: 26)
            .rotationEffect(.degrees(-4))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("back")
    }
}

/// A left-pointing arrow with slightly uneven edges, as if cut with scissors.
private struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [(CGFloat, CGFloat)] = [
            (0, 0.5), (0.38, 0.03), (0.37, 0.31), (0.97, 0.27),
            (1, 0.74), (0.38, 0.69), (0.39, 0.97),
        ]
        var path = Path()
        for (index, point) in points.enumerated() {
            let location = CGPoint(x: rect.minX + point.0 * rect.width, y: rect.minY + point.1 * rect.height)
            index == 0 ? path.move(to: location) : path.addLine(to: location)
        }
        path.closeSubpath()
        return path
    }
}

/// Undo, as a strip of masking tape: tap takes off the last stroke, long-press clears the cut.
private struct UndoTab: View {
    let isEnabled: Bool
    var onUndo: () -> Void
    var onClear: () -> Void

    var body: some View {
        Button(action: onUndo) {
            TapeLabel(text: "undo")
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .disabled(!isEnabled)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in onClear() })
        .accessibilityAction(named: "clear", onClear)
    }
}

/// A strip of tape with torn zigzag ends.
/// A word on a strip of masking tape (undo, invite).
struct TapeLabel: View {
    let text: String
    var tilt: Double = -3

    var body: some View {
        Text(text)
            .font(Fonts.button())
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 22)
            .frame(minHeight: 44)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                TapeShape().fill(Color.ink.opacity(0.35)).offset(x: 2, y: 3)
                TapeShape().fill(Color.wall)
            }
            .rotationEffect(.degrees(tilt))
    }
}

struct TapeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let teeth = 5
        let depth: CGFloat = 4
        let step = rect.height / CGFloat(teeth)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        for index in 0..<teeth {
            path.addLine(to: CGPoint(x: rect.maxX - depth, y: rect.minY + step * (CGFloat(index) + 0.5)))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + step * CGFloat(index + 1)))
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        for index in (0..<teeth).reversed() {
            path.addLine(to: CGPoint(x: rect.minX + depth, y: rect.minY + step * (CGFloat(index) + 0.5)))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + step * CGFloat(index)))
        }
        path.closeSubpath()
        return path
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

/// The how-to, drawn on the folded sheet with no words: a mark at the bottom corner
/// of the fold (start) and one at the top corner (end), a dashed pencil line out
/// between them in a petal shape, and the knife tracing it twice before resting on
/// the start. With Reduce Motion the knife just rests on the start.
struct CutGuide: View {
    /// The folded sheet; the fold is its left edge.
    let size: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// What VoiceOver says about the paper, in place of the drawing.
    static let spokenHint = "Start at the bottom of the fold, cut out and around, and come back to the top of the fold."

    /// In the how-to cards it keeps tracing, with a short rest at the start each time.
    var loops = false

    private static let passDuration = 1.5
    private static let passes = 2.0
    private static let rest = 0.8

    @State private var start = Date.now

    /// Where the cut starts (bottom of the fold) and finishes (top of the fold).
    static func startPoint(in size: CGSize) -> CGPoint { curves(in: size)[0][0] }
    static func endPoint(in size: CGSize) -> CGPoint { curves(in: size)[1][3] }

    private var startMark: CGPoint { Self.startPoint(in: size) }

    /// The guide's cut as two cubic curves (start, control, control, end): out from the
    /// bottom of the fold, round in a petal's curve, and back to the fold near the top.
    private static func curves(in size: CGSize) -> [[CGPoint]] {
        let w = size.width, h = size.height
        let middle = CGPoint(x: w * 0.52, y: h * 0.5)
        return [
            [CGPoint(x: 0, y: h * 0.8), CGPoint(x: w * 0.3, y: h * 0.8), CGPoint(x: w * 0.54, y: h * 0.66), middle],
            [middle, CGPoint(x: w * 0.5, y: h * 0.32), CGPoint(x: w * 0.2, y: h * 0.16), CGPoint(x: 0, y: h * 0.14)],
        ]
    }

    private var path: Path {
        var path = Path()
        let curves = Self.curves(in: size)
        path.move(to: curves[0][0])
        for curve in curves {
            path.addCurve(to: curve[3], control1: curve[1], control2: curve[2])
        }
        return path
    }

    /// The flower the guide's cut makes, shown as the preview while the guide plays.
    static func flower(owner: String, paper: Paper, count: Int, sheet: CGSize) -> Petal? {
        let points = curves(in: sheet).flatMap { curve in
            (0...12).map { step -> CGPoint in
                let t = CGFloat(step) / 12, u = 1 - t
                let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
                return CGPoint(x: a * curve[0].x + b * curve[1].x + c * curve[2].x + d * curve[3].x,
                               y: a * curve[0].y + b * curve[1].y + c * curve[2].y + d * curve[3].y)
            }
        }
        return CutShape.petalPoints(from: points).map {
            Petal(id: 0, owner: owner, pattern: paper, nPetals: count, points: $0)
        }
    }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let elapsed = context.date.timeIntervalSince(start)
            // 0…1 along the line on each pass; after the last pass (or between passes,
            // when looping) it rests at the start.
            let cycle = Self.passDuration + Self.rest
            let looped = elapsed.truncatingRemainder(dividingBy: cycle)
            let progress = reduceMotion ? 0
                : loops ? min(looped / Self.passDuration, 1) * (looped < Self.passDuration ? 1 : 0)
                : elapsed >= Self.passDuration * Self.passes ? 0
                : (elapsed / Self.passDuration).truncatingRemainder(dividingBy: 1)
            ZStack(alignment: .topLeading) {
                path.stroke(Color.ink.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                // The part the knife has been along so far, like a light pencil line.
                path.trimmedPath(from: 0, to: progress)
                    .stroke(Color.ink.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                FoldMarks(size: size)
                Knife(tip: progress > 0 ? (path.trimmedPath(from: 0, to: progress).currentPoint ?? startMark) : startMark)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

}

/// The two cream paper dots stuck on the fold: start at the bottom, finish at the top.
struct FoldMarks: View {
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            mark(at: CutGuide.endPoint(in: size))
            mark(at: CutGuide.startPoint(in: size))
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func mark(at point: CGPoint) -> some View {
        Circle()
            .fill(Color.cream)
            .overlay { Circle().stroke(Color.ink, lineWidth: 1) }
            .frame(width: 12, height: 12)
            .background { Circle().fill(Color.ink.opacity(0.3)).offset(x: 1.5, y: 2) }
            .position(x: point.x + 6, y: point.y)
    }
}

/// A typewritten "?" straight on the mat, to bring the how-to back.
struct HelpTab: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("?")
                .font(.custom(Typeface.specialElite.rawValue, size: 28, relativeTo: .title2))
                .foregroundStyle(Color.cream)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("how to cut")
    }
}

/// While the animation plays: a pencil loop drawn round the preview, with a note under it.
struct PreviewCallout: View {
    var width: CGFloat
    var height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0

    var body: some View {
        PencilLoop()
            .trim(from: 0, to: reduceMotion ? 1 : drawn)
            .stroke(Color.cream, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: width, height: height)
            .overlay(alignment: .topTrailing) {
                Text("this is the preview")
                    .font(Fonts.controlLabel())
                    .foregroundStyle(Color.cream)
                    .fixedSize()
                    .offset(y: height + 4)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.5).delay(0.3)) { drawn = 1 }
            }
    }
}

/// A quick pencil circle: a bit over one turn, not quite round.
struct PencilLoop: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let rx = rect.width / 2, ry = rect.height / 2
        // A bit over one turn, the radius drifting so the ends overlap off-centre.
        for step in 0...60 {
            let t = Double(step) / 60
            let angle = -2.2 + t * 2.15 * .pi
            let wobble = 1 + 0.06 * sin(t * 9) - 0.05 * t
            let point = CGPoint(x: c.x + cos(angle) * rx * wobble, y: c.y + sin(angle) * ry * wobble)
            step == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        return path
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
struct CuttingMat: View {
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
    CutView(owner: "a", paper: .dots, onBack: {}, onPlant: { _ in })
}

#Preview("cut in progress") {
    // An open cut, out from the crease and up, as it looks mid-drag, and the live
    // flower it would make.
    let line = (0...24).map { step in
        let t = Double(step) / 24
        return CGPoint(x: sin(t * .pi * 0.85) * 95, y: 290 - t * 210)
    }
    let points = CutShape.previewPoints(from: line) ?? []
    return HStack(alignment: .top, spacing: 24) {
        ZStack(alignment: .topLeading) {
            PaperFill(paper: .gingham, scale: 14)
            CutLine(strokes: [line])
                .stroke(Color.ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 260, height: 360)
        FlowerView(petal: Petal(id: 0, owner: "a", pattern: .gingham, nPetals: 6, points: points), size: 56)
    }
    .padding()
    .background(Color.mat)
}
