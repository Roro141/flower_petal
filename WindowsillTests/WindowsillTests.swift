import Foundation
import SwiftUI
import Testing
@testable import flower

/// Checks for the milestone 1 pieces: petal geometry, stored rows, seeded
/// randomness and the widget's PNG renderer.
struct WindowsillTests {

    @Test func petalPathIsMirroredAcrossTheFold() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        for shape in Petal.sampleShapes {
            let bounds = PetalPath(points: shape).path(in: rect).boundingRect
            #expect(!bounds.isEmpty)
            // Mirrored halves: as far left of the fold as right of it (give or
            // take the hand-cut wobble, which is at most 0.75 pt).
            #expect(abs(bounds.midX - rect.midX) < 2)
        }
    }

    @Test func roughEdgeStaysCloseToTheLineAndRepeats() {
        let square = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)]
        var first = SeededRandom(seed: 4)
        var second = SeededRandom(seed: 4)
        let path = RoughEdge.path(through: square, random: &first)
        #expect(path == RoughEdge.path(through: square, random: &second))
        // Never more than 0.75 pt off the square's edges.
        #expect(CGRect(x: -0.75, y: -0.75, width: 101.5, height: 101.5).contains(path.boundingRect))
        #expect(path.boundingRect.contains(CGRect(x: 0.75, y: 0.75, width: 98.5, height: 98.5)))
    }

    @Test func petalPathIgnoresTooFewPoints() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(PetalPath(points: [[0, 0], [0.2, 0.5]]).path(in: rect).isEmpty)
        #expect(PetalPath(points: [[0, 0], [0.2], [0.3, 0.6]]).path(in: rect).isEmpty)
    }

    @Test(arguments: [
        ("dots", Paper.dots), ("gingham", .gingham), ("newsprint", .newsprint),
        ("#C8473B", .dots), ("#9C88B8", .stripe), ("#E2B53E", .ditsy), ("nonsense", .dots),
    ])
    func storedPatternsMapToPapers(stored: String, paper: Paper) {
        #expect(Paper(stored: stored) == paper)
    }

    @Test func rowWithPointsKeepsThem() throws {
        let json = #"[{"id":31,"profile_id":"b","pattern":"gingham","n_petals":5,"points":[[0,0],[0.2,0.12],[0.36,0.34],[0,0.78]],"created_at":"2026-11-14T22:46:11.61449+00:00"}]"#
        let row = try decodeRows(json)[0]
        let petal = Petal(row: row)
        #expect(petal.id == 31)
        #expect(petal.owner == "b")
        #expect(petal.pattern == .gingham)
        #expect(petal.nPetals == 5)
        #expect(petal.points.count == 4)
        #expect(petal.createdAt != nil)
    }

    @Test func spikeRowWithoutPointsGetsASampleShape() throws {
        let json = ##"[{"id":20,"profile_id":"b","pattern":"#E2B53E","n_petals":8,"points":null}]"##
        let petal = Petal(row: try decodeRows(json)[0])
        #expect(petal.pattern == .ditsy)
        #expect(Petal.sampleShapes.contains(petal.points))
    }

    @Test func insertRowLeavesOutServerColumns() throws {
        let row = PetalService.PetalRow(profile_id: "a", pattern: "dots", n_petals: 6, points: [[0, 0], [0.3, 0.5], [0, 1]])
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String: Any]
        #expect(object?["id"] == nil)
        #expect(object?["created_at"] == nil)
        #expect(object?["pattern"] as? String == "dots")
    }

    @Test func seededRandomRepeatsPerOwnerAndDiffersBetweenOwners() {
        var first = SeededRandom("junie")
        var again = SeededRandom("junie")
        var other = SeededRandom("roha")
        let a = (0..<5).map { _ in first.next() }
        #expect(a == (0..<5).map { _ in again.next() })
        #expect(a != (0..<5).map { _ in other.next() })
        #expect(a.allSatisfy { (0..<1).contains($0) })
    }

    @Test func samplesShowAllFiveCentresAndPots() {
        let centres = Set(Petal.samples.map { FlowerCentre.for(owner: $0.owner) })
        #expect(centres.count == FlowerCentre.allCases.count)
        let pots = Set((0..<5).map { PotStyle.forSill($0) })
        #expect(pots.count == PotStyle.allCases.count)
    }

    @Test func randomPetalIsAValidSample() {
        let petal = Petal.random(owner: "a")
        #expect((5...8).contains(petal.nPetals))
        #expect(Petal.sampleShapes.contains(petal.points))
    }

    @MainActor
    @Test func rendererWritesAndReloadsPlantImages() throws {
        try #require(FlowerStore.containerURL != nil, "App Group container is missing")
        let petals = FlowerStore.defaultPetals
        FlowerRenderer.render(petals, onlyMissing: false)
        for (index, petal) in petals.enumerated() {
            let image = try #require(FlowerRenderer.image(for: petal, sillIndex: index))
            #expect(image.width == Int(FlowerRenderer.plantSize * FlowerRenderer.scale))
        }
    }

    // MARK: - Cutting

    private let sheet = CGSize(width: 260, height: 360)

    @Test func cutStaysOnTheSheet() {
        var cut = CutDrawing(size: sheet)
        cut.touchDown(at: CGPoint(x: 0, y: 300))
        cut.touchMoved(to: CGPoint(x: 500, y: -80))
        cut.touchMoved(to: CGPoint(x: 120, y: 900))
        for point in cut.strokes.joined() {
            #expect((0...sheet.width).contains(point.x))
            #expect((0...sheet.height).contains(point.y))
        }

        var below = CutDrawing(size: sheet)
        below.touchDown(at: CGPoint(x: 5, y: 420))   // on the crease line but past the paper
        #expect(below.strokes.isEmpty)
    }

    @Test func cutStartSnapsToCreaseAndIgnoresFarTouches() {
        var far = CutDrawing(size: sheet)
        far.touchDown(at: CGPoint(x: 100, y: 200))
        #expect(far.strokes.isEmpty)

        var near = CutDrawing(size: sheet)
        near.touchDown(at: CGPoint(x: 18, y: 200))
        #expect(near.strokes.first?.first == CGPoint(x: 0, y: 200))
    }

    @Test func liftPausesAndNearbyTouchResumes() {
        var cut = CutDrawing(size: sheet)
        cut.touchDown(at: CGPoint(x: 5, y: 300))
        cut.touchMoved(to: CGPoint(x: 60, y: 250))
        cut.touchUp(at: CGPoint(x: 60, y: 250))
        #expect(!cut.isClosed)

        cut.touchDown(at: CGPoint(x: 200, y: 50))   // far from the end: ignored
        #expect(cut.strokes.count == 1)
        cut.touchDown(at: CGPoint(x: 70, y: 245))   // near the end: resumes
        #expect(cut.strokes.count == 2)
        #expect(cut.strokes[1].first == CGPoint(x: 60, y: 250))
    }

    @Test func fingerOnTheEndOfAPausedCutResumesIt() {
        var cut = CutDrawing(size: sheet)
        let reach: CGFloat = 44
        // A fresh touch puts the knife straight above the finger.
        #expect(cut.knifeOffset(forFingerAt: CGPoint(x: 10, y: 300), reach: reach) == CGSize(width: 0, height: -reach))

        cut.touchDown(at: CGPoint(x: 0, y: 300))
        cut.touchMoved(to: CGPoint(x: 80, y: 220))
        cut.touchUp(at: CGPoint(x: 80, y: 220))

        // Finger lands right on the end of the line: the knife moves onto the end.
        let finger = CGPoint(x: 84, y: 226)
        let offset = cut.knifeOffset(forFingerAt: finger, reach: reach)
        let knife = CGPoint(x: finger.x + offset.width, y: finger.y + offset.height)
        #expect(knife == CGPoint(x: 80, y: 220))
        cut.touchDown(at: knife)
        #expect(cut.strokes.count == 2)

        // Far from the end: back to the usual knife above the finger.
        #expect(cut.knifeOffset(forFingerAt: CGPoint(x: 200, y: 40), reach: reach) == CGSize(width: 0, height: -reach))
    }

    @Test func pausingCloseToTheCreaseDoesNotEndTheCut() {
        var cut = CutDrawing(size: sheet)
        cut.touchDown(at: CGPoint(x: 0, y: 300))
        cut.touchMoved(to: CGPoint(x: 80, y: 200))
        cut.touchMoved(to: CGPoint(x: 20, y: 120))
        cut.touchUp(at: CGPoint(x: 20, y: 120))
        #expect(!cut.isClosed)
    }

    @Test func undoTakesOffTheLastStrokeAndClearEmptiesTheCut() {
        var cut = CutDrawing(size: sheet)
        cut.touchDown(at: CGPoint(x: 0, y: 300))
        cut.touchMoved(to: CGPoint(x: 80, y: 220))
        cut.touchUp(at: CGPoint(x: 80, y: 220))
        #expect(cut.isPaused)
        cut.touchDown(at: CGPoint(x: 80, y: 220))
        cut.touchMoved(to: CGPoint(x: 0, y: 100))      // crosses the fold: closed
        #expect(cut.isClosed)
        #expect(!cut.isPaused)

        cut.undo()
        #expect(!cut.isClosed)
        #expect(cut.strokes.count == 1)
        #expect(cut.lastPoint == CGPoint(x: 80, y: 220))

        cut.clear()
        #expect(cut.strokes.isEmpty)
        #expect(!cut.isPaused)
    }

    @Test func cutClosesBackOnTheCrease() {
        var cut = CutDrawing(size: sheet)
        cut.touchDown(at: CGPoint(x: 0, y: 300))
        cut.touchMoved(to: CGPoint(x: 80, y: 200))
        cut.touchMoved(to: CGPoint(x: 10, y: 60))
        cut.touchUp(at: CGPoint(x: 10, y: 60))
        #expect(cut.isClosed)
        #expect(cut.lastPoint == CGPoint(x: 0, y: 60))

        cut.touchDown(at: CGPoint(x: 0, y: 60))      // closed: no more cutting
        #expect(cut.strokes.count == 1)
    }

    @Test func lingeringNearTheCreaseDoesNotClose() {
        var cut = CutDrawing(size: sheet)
        cut.touchDown(at: CGPoint(x: 0, y: 300))
        cut.touchMoved(to: CGPoint(x: 15, y: 290))
        cut.touchUp(at: CGPoint(x: 15, y: 290))
        #expect(!cut.isClosed)
    }

    // MARK: - Cut to petal

    /// A dense, wobbly cut from the crease at y = 300 out and back to it at y = 70.
    private var wobblyCut: [CGPoint] {
        (0...120).map { step in
            let t = Double(step) / 120
            return CGPoint(x: sin(t * .pi) * 90 + sin(t * 41) * 2, y: 300 - t * 230)
        }
    }

    @Test func cutBecomesANormalizedPetal() throws {
        let points = try #require(CutShape.petalPoints(from: wobblyCut))
        #expect(CutShape.pointCount.contains(points.count))
        #expect(points.first == [0, 0])
        #expect(points.last?.first == 0)
        for point in points {
            #expect(point.count == 2)
            #expect((0...1).contains(point[0]) && (0...1).contains(point[1]))
        }
        // The tallest point reaches 1, and the shape isn't stretched sideways.
        #expect(points.map { $0[1] }.max() == 1)
        let widest = try #require(points.map { $0[0] }.max())
        #expect(abs(widest - 90.0 / 230.0) < 0.03)
    }

    @Test func cutFromTheTipDownGivesTheSamePetal() {
        #expect(CutShape.petalPoints(from: wobblyCut.reversed()) == CutShape.petalPoints(from: wobblyCut))
    }

    @Test func plainCutStillGetsFivePoints() throws {
        let triangle = [CGPoint(x: 0, y: 300), CGPoint(x: 80, y: 200), CGPoint(x: 0, y: 100)]
        let points = try #require(CutShape.petalPoints(from: triangle))
        #expect(points.count == 5)
    }

    @Test func resumedCutRepeatsAreIgnored() throws {
        let cut = [CGPoint(x: 0, y: 300), CGPoint(x: 60, y: 240), CGPoint(x: 60, y: 240),
                   CGPoint(x: 90, y: 150), CGPoint(x: 0, y: 80)]
        let points = try #require(CutShape.petalPoints(from: cut))
        #expect(Set(points).count == points.count)
    }

    @Test func onlyAClosedCutHasPetalPoints() {
        var cut = CutDrawing(size: sheet)
        cut.touchDown(at: CGPoint(x: 0, y: 300))
        cut.touchMoved(to: CGPoint(x: 80, y: 200))
        cut.touchUp(at: CGPoint(x: 80, y: 200))
        #expect(cut.petalPoints == nil)
        cut.touchDown(at: CGPoint(x: 80, y: 200))
        cut.touchMoved(to: CGPoint(x: 0, y: 90))
        #expect(cut.petalPoints?.first == [0, 0])
    }

    private func decodeRows(_ json: String) throws -> [PetalService.PetalRow] {
        try PetalService.decoder.decode([PetalService.PetalRow].self, from: Data(json.utf8))
    }
}
