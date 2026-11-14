import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import os

/// Renders each friend's plant to a PNG in the App Group container, so the
/// widget only ever shows images and never draws a flower itself.
enum FlowerRenderer {
    /// Flower-head width the PNGs are drawn at; the widget scales them to fit.
    static let plantSize: CGFloat = 60
    static let scale: CGFloat = 3
    private static let prefix = "plant-"

    /// One file per petal and sill place (the place picks the pot).
    static func imageURL(for petal: Petal, sillIndex: Int) -> URL? {
        FlowerStore.containerURL?.appendingPathComponent("\(prefix)\(petal.id)-\(sillIndex).png")
    }

    /// Renders the sill's plants and deletes images that are no longer on it.
    /// With `onlyMissing`, existing files are kept as they are, which keeps widget reloads cheap.
    /// The app passes `false` so a change to the drawing code shows up on the next launch.
    @MainActor
    static func render(_ petals: [Petal], onlyMissing: Bool) {
        var keep = Set<String>()
        for (index, petal) in petals.enumerated() {
            guard let url = imageURL(for: petal, sillIndex: index) else { continue }
            keep.insert(url.lastPathComponent)
            if onlyMissing, FileManager.default.fileExists(atPath: url.path) { continue }

            let renderer = ImageRenderer(content: PlantView(petal: petal, pot: .forSill(index), size: plantSize))
            renderer.scale = scale
            guard let image = renderer.cgImage,
                  let file = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
            else {
                PetalService.log.error("could not render plant \(petal.id, privacy: .public)")
                continue
            }
            CGImageDestinationAddImage(file, image, nil)
            CGImageDestinationFinalize(file)
        }
        removeImages(except: keep)
    }

    /// Loads a rendered plant. Reads a local file only, so it's safe in a widget view.
    static func image(for petal: Petal, sillIndex: Int) -> CGImage? {
        guard let url = imageURL(for: petal, sillIndex: sillIndex),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func removeImages(except keep: Set<String>) {
        guard let folder = FlowerStore.containerURL,
              let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for file in files where file.hasPrefix(prefix) && !keep.contains(file) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
        }
    }
}
