import SwiftUI
import WidgetKit
import os

struct ContentView: View {
    @State private var flowers = FlowerStore.load()
    @State private var myID = SpikeUsers.myID
    @State private var isPlanting = false

    var body: some View {
        VStack(spacing: 40) {
            // Spike-only: tells this phone which of the two users it is.
            Picker("me", selection: $myID) {
                ForEach(SpikeUsers.ids, id: \.self) { id in
                    Text(SpikeUsers.names[id] ?? id).tag(id)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)
            .onChange(of: myID) { _, newValue in
                SpikeUsers.myID = newValue
            }

            Spacer()
            SillView(flowers: flowers, flowerSize: 80)
            Button("plant a random petal", action: plant)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.cream)
                .padding(.horizontal, 20)
                .frame(minHeight: 44)
                .background(Color.ink, in: .rect(cornerRadius: 4))
                .disabled(isPlanting)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.wall)
        .task { await refresh() }
    }

    /// Plants a random flower for me: shows it straight away, writes it to Supabase,
    /// then reloads this phone's widget.
    private func plant() {
        let mine = Flower.random(id: myID, name: SpikeUsers.names[myID] ?? myID)
        if let index = flowers.firstIndex(where: { $0.id == mine.id }) {
            flowers[index] = mine
        } else {
            flowers.append(mine)
        }
        FlowerStore.save(flowers)
        WidgetCenter.shared.reloadAllTimelines()

        isPlanting = true
        Task {
            do {
                try await PetalService.plant(mine)
            } catch {
                PetalService.log.error("plant failed: \(error.localizedDescription, privacy: .public)")
            }
            isPlanting = false
        }
    }

    /// Pulls the latest petals so the friend's flower is current when the app opens.
    private func refresh() async {
        do {
            flowers = try await PetalService.fetchFlowers(fallback: flowers).flowers
            FlowerStore.save(flowers)
        } catch {
            PetalService.log.error("app fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

#Preview {
    ContentView()
}
