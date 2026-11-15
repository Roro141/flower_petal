import WidgetKit
import SwiftUI
import os

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SillEntry {
        SillEntry(date: .now, sill: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (SillEntry) -> ()) {
        Task {
            let sill = FlowerStore.load() ?? .preview
            await FlowerRenderer.render(sill, onlyMissing: true)
            completion(SillEntry(date: .now, sill: sill))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SillEntry>) -> ()) {
        Task {
            // Fetch my windowsill as the signed-in person; on failure, show the last one saved.
            var sill = FlowerStore.load()
            do {
                if let session = try await Auth.currentSession() {
                    sill = try await PetalService.fetchSill(session)
                    FlowerStore.save(sill)
                    if let sill { logFriendLatency(sill) }
                }
            } catch {
                PetalService.log.error("widget fetch failed: \(error.localizedDescription, privacy: .public)")
            }
            let shown = sill ?? .preview
            // Only new petals need drawing; the view just shows the files.
            await FlowerRenderer.render(shown, onlyMissing: true)
            // One entry now, plus one for each moment a flower is due to wilt, so the
            // widget droops on time even without a reload or a network connection.
            let now = Date.now
            let wiltDates = shown.petals.compactMap(\.wiltDate).filter { $0 > now }.sorted()
            let entries = ([now] + wiltDates).map { SillEntry(date: $0, sill: shown) }
            // Ask WidgetKit to come back in 15 minutes; pushes can wake it sooner.
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
        }
    }

    /// Measurement: the first time the widget sees a newer petal from a friend, log
    /// how long after planting it arrived. Console only, never in the UI.
    private func logFriendLatency(_ sill: Sill) {
        let defaults = UserDefaults(suiteName: FlowerStore.appGroup)
        guard let plantedAt = sill.petals.filter({ $0.owner != sill.myID }).compactMap(\.createdAt).max() else { return }

        let lastSeen = defaults?.object(forKey: "lastSeenFriendPetal") as? Date
        if let lastSeen, plantedAt <= lastSeen { return }
        defaults?.set(plantedAt, forKey: "lastSeenFriendPetal")

        let seconds = Date.now.timeIntervalSince(plantedAt)
        PetalService.log.notice("widget saw friend's petal after \(String(format: "%.1f", seconds), privacy: .public)s")
    }
}

struct SillEntry: TimelineEntry {
    let date: Date
    let sill: Sill
}

/// The window as a static snapshot: the scene is drawn here, but every plant is
/// a PNG drawn earlier by `FlowerRenderer`.
struct WindowsillWidgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        WindowScene(sill: entry.sill, now: entry.date, boardHeight: 20, plantSpacing: 6, plantsTopInset: 22) { index, petal in
            if let image = FlowerRenderer.image(for: petal, in: entry.sill, wilted: petal.isWilted(at: entry.date)) {
                Image(decorative: image, scale: FlowerRenderer.scale)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear
            }
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
        // The window runs to the widget's edges.
        .contentMarginsDisabled()
        .configurationDisplayName("Windowsill")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemMedium) {
    WindowsillWidget()
} timeline: {
    SillEntry(date: .now, sill: .preview)
}
