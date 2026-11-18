import SwiftUI

/// The how-to for cutting: six paper cards, one at a time, in the middle of the mat.
/// Shown the first time the cutting screen opens and again from "?". "next" moves on,
/// the last card's "let's cut" or the × in the corner closes it.
struct HowToCut: View {
    /// The Mac says click and drag instead of tap and finger.
    var isMac = false
    var onClose: () -> Void

    @State private var page: Int

    /// `startPage` is for previews.
    init(isMac: Bool = false, startPage: Int = 0, onClose: @escaping () -> Void) {
        self.isMac = isMac
        self.onClose = onClose
        _page = State(initialValue: startPage)
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Card {
        let title: String
        let lines: [String]
    }

    private var cards: [Card] {
        let tap = isMac ? "Click" : "Tap"
        return [
            Card(title: "Pick your paper",
                 lines: ["\(tap) a paper at the top.",
                         "This is your paper, folded in half. The left edge is the fold."]),
            Card(title: "Start at the bottom",
                 lines: [isMac ? "Click on the dot at the bottom of the fold."
                               : "Put your finger on the dot at the bottom of the fold."]),
            Card(title: "Cut out and around",
                 lines: [isMac ? "Drag a bump out to the right, like half a leaf."
                               : "Draw a bump out to the right, like half a leaf.",
                         "Come back to the dot at the top of the fold."]),
            Card(title: "Watch your flower grow",
                 lines: ["This is the preview. It shows your flower while you cut."]),
            Card(title: "Oops?",
                 lines: ["\(tap) undo to take back the last bit.",
                         isMac ? "Let go too soon? Click the end of the line and keep going."
                               : "Lifted your finger? Put it back on the end of the line and keep going.",
                         "No time to cut? \(tap) a ready-made petal."]),
            Card(title: "Make it yours",
                 lines: ["When it's cut, \(tap.lowercased()) cut.",
                         "Edit the details, then \(tap.lowercased()) plant it."]),
        ]
    }

    private let pictureSize = CGSize(width: 260, height: 150)

    var body: some View {
        ZStack {
            CuttingMat().ignoresSafeArea()
            card
                .id(page)
                .transition(.opacity)
        }
        // One modal container, so VoiceOver reads the whole card and nothing behind it.
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var card: some View {
        let current = cards[page]
        let isLast = page == cards.count - 1
        return VStack(spacing: 16) {
            picture(page)
                .frame(width: pictureSize.width, height: pictureSize.height)
                .accessibilityHidden(true)
            Text(current.title)
                .font(Fonts.title())
                .foregroundStyle(Color.ink)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 8) {
                ForEach(current.lines, id: \.self) { line in
                    Text(line)
                        .font(Fonts.body())
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            PageDots(count: cards.count, current: page)
            TicketButton(isLast ? "let's cut" : "next") {
                if isLast { onClose() } else { turn(to: page + 1) }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 24)
        // Every card the same size (the longest one's), so "next" stays put.
        .frame(width: 320, height: 450)
        .background {
            Rectangle().fill(Color.ink.opacity(0.35)).offset(x: 4, y: 6)
            Rectangle().fill(Color.cream)
        }
        .overlay { PaperGrain().allowsHitTesting(false) }
        .overlay(alignment: .topTrailing) {
            CloseCross(action: onClose)
        }
    }

    private func turn(to next: Int) {
        if reduceMotion {
            page = next
        } else {
            withAnimation(.easeOut(duration: 0.2)) { page = next }
        }
    }

    // MARK: - The pictures, made from the cutting screen's own pieces

    @ViewBuilder
    private func picture(_ index: Int) -> some View {
        let sheet = CGSize(width: 108, height: 150)
        switch index {
        case 0:
            // The fan of papers over a folded sheet, its fold edge marked.
            VStack(spacing: 10) {
                PaperFan(selection: .constant(.dots))
                    .scaleEffect(0.8)
                    .frame(height: 56)
                    .allowsHitTesting(false)
                    // Its papers are real buttons; hide them here, it's only a picture.
                    .accessibilityHidden(true)
                ZStack(alignment: .leading) {
                    PaperFill(paper: .dots, scale: 8)
                    Rectangle().fill(Color.ink).frame(width: 3)
                }
                .frame(width: 60, height: 80)
                .background { Rectangle().fill(Color.ink.opacity(0.35)).offset(x: 2, y: 3) }
            }
        case 1:
            // The sheet with its two dots, the start one circled in pencil.
            ZStack(alignment: .topLeading) {
                MiniSheet(size: sheet)
                FoldMarks(size: sheet)
                PencilLoop()
                    .stroke(Color.ink, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 30, height: 30)
                    .position(x: CutGuide.startPoint(in: sheet).x + 6, y: CutGuide.startPoint(in: sheet).y)
            }
            .frame(width: sheet.width, height: sheet.height)
        case 2:
            // The knife tracing the cut, over and over.
            ZStack(alignment: .topLeading) {
                MiniSheet(size: sheet)
                CutGuide(size: sheet, loops: true)
            }
            .frame(width: sheet.width, height: sheet.height)
        case 3:
            // The cut on the sheet, and the flower it makes, circled.
            HStack(spacing: 28) {
                ZStack(alignment: .topLeading) {
                    MiniSheet(size: sheet)
                    CutGuide(size: sheet, loops: true)
                }
                .frame(width: sheet.width, height: sheet.height)
                if let flower = CutGuide.flower(owner: "how-to", paper: .dots, count: 6, sheet: sheet) {
                    FlowerView(petal: flower, size: 64)
                        .overlay {
                            PencilLoop()
                                .stroke(Color.ink, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                                .frame(width: 92, height: 88)
                        }
                }
            }
        case 4:
            // Undo, and the ready-made petals.
            VStack(spacing: 18) {
                TapeLabel(text: "undo", tilt: -3)
                HStack(spacing: 10) {
                    ForEach([0, 1, 2, 4], id: \.self) { shape in
                        PaperFill(paper: .dots, scale: 4)
                            .clipShape(PetalPath(points: Petal.sampleShapes[shape]))
                            .padding(5)
                            .frame(width: 40, height: 40)
                            .background {
                                Rectangle().fill(Color.ink.opacity(0.3)).offset(x: 2, y: 2)
                                Rectangle().fill(Color.wall)
                            }
                            .rotationEffect(.degrees([-3, 2, -1.5, 3.5][min(shape, 3)]))
                    }
                }
            }
        default:
            // A finished flower and its "plant it" ticket.
            HStack(spacing: 20) {
                FlowerView(petal: Petal.samples[2], size: 110)
                TicketButton("plant it") {}
                    .allowsHitTesting(false)
            }
        }
    }
}

/// A small folded sheet for the pictures: paper, the fold line and grain.
private struct MiniSheet: View {
    let size: CGSize

    var body: some View {
        ZStack(alignment: .leading) {
            PaperFill(paper: .dots, scale: 8)
            Rectangle().fill(Color.ink.opacity(0.25)).frame(width: 1.5)
            PaperGrain()
        }
        .frame(width: size.width, height: size.height)
        .background { Rectangle().fill(Color.ink.opacity(0.35)).offset(x: 3, y: 4) }
    }
}

/// Little paper dots, one per card; the current one is ink.
private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? Color.ink : Color.ink.opacity(0.2))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("card \(current + 1) of \(count)")
    }
}

/// An ink × drawn as two short strokes, in a 44 pt corner.
private struct CloseCross: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Path { path in
                path.move(to: CGPoint(x: 16, y: 16))
                path.addLine(to: CGPoint(x: 28, y: 28))
                path.move(to: CGPoint(x: 28.5, y: 15.5))
                path.addLine(to: CGPoint(x: 15.5, y: 28.5))
            }
            .stroke(Color.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("close")
    }
}

#Preview("Card 1") { HowToCut(onClose: {}) }
#Preview("Card 2") { HowToCut(startPage: 1, onClose: {}) }
#Preview("Card 3") { HowToCut(startPage: 2, onClose: {}) }
#Preview("Card 4") { HowToCut(startPage: 3, onClose: {}) }
#Preview("Card 5") { HowToCut(startPage: 4, onClose: {}) }
#Preview("Card 6") { HowToCut(startPage: 5, onClose: {}) }
