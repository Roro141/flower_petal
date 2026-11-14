import WidgetKit
import SwiftUI
import os

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SillEntry {
        SillEntry(date: .now, petals: FlowerStore.defaultPetals)
    }

    func getSnapshot(in context: Context, completion: @escaping (SillEntry) -> ()) {
        Task {
            let petals = FlowerStore.load()
            await FlowerRenderer.render(petals, onlyMissing: true)
            completion(SillEntry(date: .now, petals: petals))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SillEntry>) -> ()) {
        Task {
            // Fetch the latest petals; on failure, show whatever was cached last.
            var petals = FlowerStore.load()
            do {
                petals = try await PetalService.fetchPetals(fallback: petals)
                FlowerStore.save(petals)
                logFriendLatency(petals: petals)
            } catch {
                PetalService.log.error("widget fetch failed: \(error.localizedDescription, privacy: .public)")
            }
            // Only new petals need drawing; the view just shows the files.
            await FlowerRenderer.render(petals, onlyMissing: true)
            // Ask WidgetKit to come back in 15 minutes; pushes can wake it sooner.
            let next = Date.now.addingTimeInterval(15 * 60)
            completion(Timeline(entries: [SillEntry(date: .now, petals: petals)], policy: .after(next)))
        }
    }

    /// Spike measurement: the first time the widget sees a new petal from the other
    /// person, log how long after planting it arrived. Console only, never in the UI.
    private func logFriendLatency(petals: [Petal]) {
        let defaults = UserDefaults(suiteName: FlowerStore.appGroup)
        let friendID = SpikeUsers.ids.first { $0 != SpikeUsers.myID } ?? "b"
        guard let plantedAt = petals.first(where: { $0.owner == friendID })?.createdAt else { return }

        let lastSeen = defaults?.object(forKey: "lastSeenFriendPetal") as? Date
        if let lastSeen, plantedAt <= lastSeen { return }
        defaults?.set(plantedAt, forKey: "lastSeenFriendPetal")

        let seconds = Date.now.timeIntervalSince(plantedAt)
        PetalService.log.notice("widget saw friend's petal after \(String(format: "%.1f", seconds), privacy: .public)s")
    }
}

struct SillEntry: TimelineEntry {
    let date: Date
    let petals: [Petal]
}

/// The sill as static images: each plant is a PNG drawn by `FlowerRenderer`.
struct WindowsillWidgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(entry.petals.enumerated()), id: \.element.id) { index, petal in
                    VStack(spacing: 2) {
                        if let image = FlowerRenderer.image(for: petal, sillIndex: index) {
                            Image(decorative: image, scale: FlowerRenderer.scale)
                                .resizable()
                                .scaledToFit()
                        } else {
                            Color.clear
                        }
                        NameLabel(owner: petal.owner)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(SpikeUsers.name(for: petal.owner))'s flower")
                }
            }
            Rectangle()
                .fill(Color.sill)
                .frame(height: 6)
        }
    }
}

struct WindowsillWidget: Widget {
    let kind: String = "WindowsillWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            WindowsillWidgetEntryView(entry: entry)
                .containerBackground(Color.wall, for: .widget)
        }
        .configurationDisplayName("Windowsill")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemMedium) {
    WindowsillWidget()
} timeline: {
    SillEntry(date: .now, petals: FlowerStore.defaultPetals)
}
