#if os(macOS)
import SwiftUI
import AppKit
import os

/// The Mac's menu-bar panel: the whole window scene, kept up to date on its own, with
/// gusts playing in full (or once, compressed, if one blew while it was closed).
struct SillPanel: View {
    @State private var sill = FlowerStore.load()
    @State private var gustPlays = 0
    @State private var gustSpeed = 1.0

    var body: some View {
        Group {
            if let sill {
                TimelineView(.everyMinute) { context in
                    SillView(sill: sill, plantSize: 64, now: context.date, gustPlays: gustPlays, gustSpeed: gustSpeed)
                }
            } else {
                // Not signed in on this Mac yet: an empty window.
                WindowScene(sill: Sill(groupID: "", inviteCode: "", myID: "", members: [], petals: [])) { _, _ in
                    EmptyView()
                }
                .frame(height: 190)
            }
        }
        .frame(width: 420)
        .background { WallFill() }
        .task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func refresh() async {
        do {
            guard let session = try await Auth.currentSession(),
                  let fetched = try await PetalService.fetchSill(session) else { return }
            if fetched != sill { sill = fetched }
            if let speed = Gust.playbackSpeed(for: fetched.gust, seenKey: "lastPlayedGustPanel") {
                gustSpeed = speed
                gustPlays += 1
            }
        } catch {
            PetalService.log.error("panel refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// The menu-bar icon: a little cut-paper flower, drawn from a petal shape and used
/// as a template image so it matches the menu bar's light or dark look.
enum MenuBarFlower {
    @MainActor static let image: NSImage = {
        let renderer = ImageRenderer(content:
            ZStack {
                ForEach(0..<6, id: \.self) { index in
                    PetalPath(points: Petal.sampleShapes[0])
                        .fill(Color.black)
                        .frame(width: 8, height: 8)
                        .offset(y: -4)
                        .rotationEffect(.degrees(Double(index) * 60 + 8))
                }
                Circle().fill(Color.black).frame(width: 4, height: 4)
            }
            .frame(width: 18, height: 18)
        )
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        return image
    }()
}
#endif
