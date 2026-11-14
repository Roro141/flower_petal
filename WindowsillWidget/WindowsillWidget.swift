import WidgetKit
import SwiftUI
import os

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SillEntry {
        SillEntry(date: .now, flowers: FlowerStore.defaultFlowers)
    }

    func getSnapshot(in context: Context, completion: @escaping (SillEntry) -> ()) {
        completion(SillEntry(date: .now, flowers: FlowerStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SillEntry>) -> ()) {
        Task {
            // Fetch the latest petals; on failure, show whatever was cached last.
            let cached = FlowerStore.load()
            var flowers = cached
            do {
                let result = try await PetalService.fetchFlowers(fallback: cached)
                flowers = result.flowers
                FlowerStore.save(flowers)
                logFriendLatency(rows: result.rows)
            } catch {
                PetalService.log.error("widget fetch failed: \(error.localizedDescription, privacy: .public)")
            }
            // Ask WidgetKit to come back in 15 minutes; pushes can wake it sooner.
            let next = Date.now.addingTimeInterval(15 * 60)
            completion(Timeline(entries: [SillEntry(date: .now, flowers: flowers)], policy: .after(next)))
        }
    }

    /// Spike measurement: the first time the widget sees a new petal from the other
    /// person, log how long after planting it arrived. Console only, never in the UI.
    private func logFriendLatency(rows: [PetalService.PetalRow]) {
        let defaults = UserDefaults(suiteName: FlowerStore.appGroup)
        let friendID = SpikeUsers.ids.first { $0 != SpikeUsers.myID } ?? "b"
        guard let plantedAt = rows.first(where: { $0.profile_id == friendID })?.created_at else { return }

        let lastSeen = defaults?.object(forKey: "lastSeenFriendPetal") as? Date
        if let lastSeen, plantedAt <= lastSeen { return }
        defaults?.set(plantedAt, forKey: "lastSeenFriendPetal")

        let seconds = Date.now.timeIntervalSince(plantedAt)
        PetalService.log.notice("widget saw friend's petal after \(seconds, format: .fixed(precision: 1), privacy: .public)s")
    }
}

struct SillEntry: TimelineEntry {
    let date: Date
    let flowers: [Flower]
}

struct WindowsillWidgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        SillView(flowers: entry.flowers, flowerSize: 44)
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
    SillEntry(date: .now, flowers: FlowerStore.defaultFlowers)
}
