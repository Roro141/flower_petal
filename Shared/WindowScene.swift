import SwiftUI

/// The window everyone's plants sit in, as cut-paper pieces: wall, sky, a wooden
/// frame whose strips don't quite line up, two curtains of different lengths, and
/// the sill board the pots stand on, with each friend's name on its front.
///
/// Used by both the app and the widget, so they always match. `plant` draws one
/// friend's plant: live in the app, a pre-rendered PNG in the widget.
struct WindowScene<Plant: View>: View {
    let sill: Sill
    /// The moment being shown; decides who has wilted (for VoiceOver).
    var now = Date.now
    var boardHeight: CGFloat = 26
    var plantSpacing: CGFloat = 12
    /// Keeps plants that size themselves to fit (the widget's images) below the top of the frame.
    var plantsTopInset: CGFloat = 0
    /// Whether the newest gust's fallen petals are on the sill yet (false while it's still
    /// blowing). Petals from earlier gusts are always there.
    var showFallen = true
    var fallenPetalSize: CGFloat = 28
    /// Bumped to play a gust: the curtains billow. The widget never sets it, so it never moves.
    var gustPlays = 0
    /// 1 for a live gust; higher plays a missed gust faster.
    var gustSpeed = 1.0
    /// How far above the bottom of a plant its flower head sits, so a blown-off petal
    /// can fly from there to the sill. Only used while a gust plays.
    var flowerHeadHeight: CGFloat = 0
    @ViewBuilder var plant: (_ index: Int, _ petal: Petal) -> Plant

    var body: some View {
        ZStack(alignment: .bottom) {
            KeyframeAnimator(initialValue: CGFloat(0), trigger: gustPlays) { billow in
                WindowBackdrop(boardHeight: boardHeight, billow: billow)
            } keyframes: { _ in
                // Out with the gust, held, then falling back with a little sway.
                LinearKeyframe(1, duration: 0.45 / gustSpeed, timingCurve: Gust.leanCurve)
                LinearKeyframe(1, duration: 0.45 / gustSpeed)
                SpringKeyframe(0, duration: 1.4 / gustSpeed, spring: Gust.springBack(speed: gustSpeed))
            }
            HStack(alignment: .bottom, spacing: plantSpacing) {
                ForEach(Array(sill.petals.enumerated()), id: \.element.id) { index, petal in
                    VStack(spacing: 0) {
                        plant(index, petal)
                            .overlay(alignment: .bottom) {
                                // Every petal this flower has lost since it was planted.
                                ZStack {
                                    ForEach(sill.windLosses[petal.owner] ?? [], id: \.gust.id) { loss in
                                        if loss.gust != sill.gust {
                                            // From an earlier gust: lying where it landed.
                                            FallenPetal(petal: petal, gust: loss.gust, size: fallenPetalSize)
                                        } else if showFallen {
                                            // The newest gust's petal flies from the flower to the sill
                                            // as the gust plays.
                                            KeyframeAnimator(initialValue: CGFloat(0), trigger: gustPlays) { flight in
                                                FallenPetal(petal: petal, gust: loss.gust, size: fallenPetalSize,
                                                            flight: flight, headHeight: flowerHeadHeight)
                                            } keyframes: { _ in
                                                MoveKeyframe(1)
                                                LinearKeyframe(1, duration: Gust.releaseDelay(flowers: sill.petals.count,
                                                                                              speed: gustSpeed))
                                                LinearKeyframe(0, duration: Gust.flightTime / gustSpeed, timingCurve: .easeIn)
                                            }
                                            .transition(.opacity)
                                        }
                                    }
                                }
                            }
                        // The pot stands on the board; the name sits on its front.
                        NameLabel(name: sill.name(for: petal.owner))
                            .frame(height: boardHeight)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(petal.isWilted(at: now)
                        ? "\(sill.name(for: petal.owner))'s flower, resting"
                        : "\(sill.name(for: petal.owner))'s flower")
                    // Nameless flowers (the sign-in and name screens) are decoration, not friends.
                    .accessibilityHidden(sill.name(for: petal.owner).isEmpty)
                }
            }
            .padding(.top, plantsTopInset)
            PaperGrain()
        }
    }
}

/// A petal the wind blew off, lying on the sill board by its pot. Where it lands and
/// how it's turned come from the gust, so it's the same on every phone.
private struct FallenPetal: View {
    let petal: Petal
    let gust: Gust
    let size: CGFloat
    /// 0 = lying on the sill. 1 = still on the flower, `headHeight` above. In between,
    /// it's in the air: carried right by the wind in an arc, tumbling, then dropping.
    var flight: CGFloat = 0
    var headHeight: CGFloat = 0

    var body: some View {
        var random = SeededRandom("\(petal.owner)-\(gust.id)-fallen")
        let turn = 70 + random.next() * 50
        // Blown to the right of its pot, the way the wind goes; each gust's lands somewhere else.
        let drift = (0.2 + random.next() * 1.6) * size
        let t = flight
        let x = drift * (1 - t) + size * 0.6 * t + sin(.pi * (1 - t)) * size * 1.4
        let y = size * 0.35 * (1 - t) - headHeight * t
        return PaperFill(paper: petal.pattern, scale: size * 0.12)
            .clipShape(PetalPath(points: petal.points))
            .frame(width: size, height: size)
            .background {
                PetalPath(points: petal.points).fill(PaperShadow.colour(lift: 0.5))
                    .offset(PaperShadow.offset(lift: 0.5, unit: size * 0.06))
            }
            .rotationEffect(.degrees(turn + Double(t) * 400))
            .offset(x: x, y: y)
            // Until it lets go, it's still part of the flower.
            .opacity(t > 0.999 ? 0 : 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Everything in the window except the plants, drawn as layered paper pieces.
private struct WindowBackdrop: View {
    let boardHeight: CGFloat
    /// 0 = curtains hanging still, 1 = blown in by a gust.
    var billow: CGFloat = 0

    var body: some View {
        Canvas { context, size in
            // A fixed seed: the same small misalignments on every render and device.
            var random = SeededRandom(seed: 21)
            // Edge wobble gets its own numbers, so it never moves the pieces themselves.
            var edges = SeededRandom(seed: 22)
            func jitter(_ amount: CGFloat) -> CGFloat { (random.next() - 0.5) * 2 * amount }

            /// A rectangle cut by hand: each corner nudged a little.
            func cut(_ rect: CGRect, wobble: CGFloat = 1.5) -> Path {
                let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                               CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
                let nudged = corners.map { CGPoint(x: $0.x + jitter(wobble), y: $0.y + jitter(wobble)) }
                return RoughEdge.path(through: nudged, random: &edges)
            }

            /// A paper piece with a hard shadow; `lift` is how far it sits off what's behind.
            func piece(_ path: Path, _ colour: Color, lift: CGFloat = 1) {
                let shadow = PaperShadow.offset(lift: lift, unit: 2.5)
                context.fill(path.offsetBy(dx: shadow.width, dy: shadow.height), with: .color(PaperShadow.colour(lift: lift)))
                context.fill(path, with: .color(colour))
            }

            let width = size.width
            let height = size.height
            let boardTop = height - boardHeight
            let strip = max(5, min(width, height) * 0.035)
            let window = CGRect(x: width * 0.08, y: height * 0.07,
                                width: width * 0.84, height: boardTop - height * 0.07)

            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.wall))

            // Sky, then the frame on top of it. The strips are cut separately and
            // laid down slightly off, the way real paper strips would be.
            piece(cut(window), .sky, lift: 0.4)
            piece(cut(CGRect(x: window.midX - strip * 0.4 + jitter(2), y: window.minY,
                             width: strip * 0.8, height: window.height)), .wood, lift: 0.6)
            piece(cut(CGRect(x: window.minX, y: window.minY + window.height * 0.42 + jitter(2),
                             width: window.width, height: strip * 0.8)), .wood, lift: 0.6)
            piece(cut(CGRect(x: window.minX - strip * 0.6, y: window.minY - strip * 0.3,
                             width: strip, height: window.height + strip * 0.3)), .wood)
            piece(cut(CGRect(x: window.maxX - strip * 0.4, y: window.minY - strip * 0.3,
                             width: strip, height: window.height + strip * 0.3)), .wood)
            piece(cut(CGRect(x: window.minX - strip, y: window.minY - strip * 0.7,
                             width: window.width + strip * 2, height: strip)), .wood)

            // Curtains: the left one hangs longer than the right.
            // In a small window (the small widget) they're tied back narrower and shorter,
            // so they frame the flowers instead of covering them.
            let tieBack: CGFloat = window.width < 260 ? 0.6 : 1
            let leftWidth = window.width * 0.24 * tieBack, rightWidth = window.width * 0.2 * tieBack
            let leftLength = window.height * 0.74 * (tieBack < 1 ? 0.8 : 1)
            let rightLength = window.height * 0.56 * (tieBack < 1 ? 0.8 : 1)
            let top = window.minY - strip * 0.2
            piece(RoughEdge.path(through: curtain(x: window.minX - strip * 0.8, top: top, width: leftWidth,
                                                  length: leftLength, flaresLeft: true, billow: billow),
                                 random: &edges),
                  .cream, lift: 1.4)
            piece(RoughEdge.path(through: curtain(x: window.maxX + strip * 0.8 - rightWidth, top: top,
                                                  width: rightWidth, length: rightLength,
                                                  flaresLeft: false, billow: billow), random: &edges),
                  .cream, lift: 1.4)
            for line in curtainFolds(x: window.minX - strip * 0.8, top: top, width: leftWidth, length: leftLength) +
                        curtainFolds(x: window.maxX + strip * 0.8 - rightWidth, top: top,
                                     width: rightWidth, length: rightLength) {
                context.stroke(line, with: .color(.ink.opacity(0.08)), lineWidth: 1)
            }
            piece(cut(CGRect(x: window.minX - strip * 1.6, y: top - strip * 0.35,
                             width: window.width + strip * 3.2, height: strip * 0.55)), .sill, lift: 1.4)

            // The sill board: a top lip a little wider than the window, and its front face.
            piece(cut(CGRect(x: window.minX - strip * 1.8, y: boardTop + strip * 0.25,
                             width: window.width + strip * 3.6, height: boardHeight - strip * 0.25)), .sill, lift: 1.2)
            piece(cut(CGRect(x: window.minX - strip * 2, y: boardTop - strip * 0.35,
                             width: window.width + strip * 4, height: strip * 0.75)), .wood, lift: 1.2)
        }
        .accessibilityHidden(true)
    }

    /// A hanging curtain: straight along the rod, flaring a little towards the wall,
    /// with a snipped zigzag hem.
    /// `billow` swings the hem to the right, the way the wind blows (the same way the
    /// flowers lean), and lifts it a little. The right curtain, sheltered by the frame, moves less.
    private func curtain(x: CGFloat, top: CGFloat, width: CGFloat, length: CGFloat, flaresLeft: Bool,
                         billow: CGFloat = 0) -> [CGPoint] {
        let flare = width * 0.12
        let swing = billow * width * (flaresLeft ? 0.55 : 0.35)
        let length = length * (1 - billow * 0.12)
        let bottomLeft = x - (flaresLeft ? flare : -flare * 0.3) + swing
        let bottomRight = x + width + (flaresLeft ? -flare * 0.3 : flare) + swing
        var points = [CGPoint(x: x, y: top), CGPoint(x: x + width, y: top), CGPoint(x: bottomRight, y: top + length)]
        // Hem: right to left, every other point snipped 4 pt lower.
        let hemPoints = 12
        for index in 1...hemPoints {
            let t = CGFloat(index) / CGFloat(hemPoints)
            let dip: CGFloat = index.isMultiple(of: 2) ? 0 : 4
            points.append(CGPoint(x: bottomRight + (bottomLeft - bottomRight) * t, y: top + length + dip))
        }
        return points
    }

    /// Faint vertical folds down a curtain.
    private func curtainFolds(x: CGFloat, top: CGFloat, width: CGFloat, length: CGFloat) -> [Path] {
        [0.3, 0.55, 0.8].map { position in
            var path = Path()
            path.move(to: CGPoint(x: x + width * position, y: top + 4))
            path.addLine(to: CGPoint(x: x + width * position, y: top + length - 6))
            return path
        }
    }
}

#Preview("After a gust") {
    var sill = Sill.preview
    sill.gusts = (1...4).map { Gust(id: $0, seed: $0 * 7, createdAt: .now) }
    return SillView(sill: sill, plantSize: 90)
}

#Preview {
    WindowScene(sill: .preview) { index, petal in
        PlantView(petal: petal, pot: .forSill(index), size: 80)  // preview only
    }
    .frame(height: 260)
}



