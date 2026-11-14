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
            // Mirrored halves: as far left of the fold as right of it.
            #expect(abs((bounds.midX) - rect.midX) < 0.5)
        }
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

    private func decodeRows(_ json: String) throws -> [PetalService.PetalRow] {
        try PetalService.decoder.decode([PetalService.PetalRow].self, from: Data(json.utf8))
    }
}
