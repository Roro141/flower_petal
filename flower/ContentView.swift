import SwiftUI
import WidgetKit
import os

struct ContentView: View {
    @State private var petals = FlowerStore.load()
    @State private var myID = SpikeUsers.myID
    @State private var isPlanting = false
    @State private var showingSamples = false
    @State private var isCutting = false

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

            // Milestone 1 only: opens the sample petals for checking by eye.
            Button("samples") { showingSamples = true }
                .frame(minHeight: 44)

            Spacer()
            SillView(petals: petals, plantSize: 80)
            Button("plant a random petal", action: plant)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.cream)
                .padding(.horizontal, 20)
                .frame(minHeight: 44)
                .background(Color.ink, in: .rect(cornerRadius: 4))
                .disabled(isPlanting)
            Button("cut", action: { isCutting = true })
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.cream)
                .padding(.horizontal, 20)
                .frame(minHeight: 44)
                .background(Color.ink, in: .rect(cornerRadius: 4))
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.wall)
        .task { await refresh() }
        .sheet(isPresented: $showingSamples) { SamplesView() }
        .fullScreenCover(isPresented: $isCutting) {
            CutView(paper: .dots, onBack: { isCutting = false })
        }
    }

    /// Plants a random sample petal for me, then shows it here and on this phone's widget.
    private func plant() {
        isPlanting = true
        Task {
            do {
                let mine = try await PetalService.plant(Petal.random(owner: myID))
                if let index = petals.firstIndex(where: { $0.owner == mine.owner }) {
                    petals[index] = mine
                }
                update()
            } catch {
                PetalService.log.error("plant failed: \(error.localizedDescription, privacy: .public)")
            }
            isPlanting = false
        }
    }

    /// Pulls the latest petals so the friend's flower is current when the app opens.
    private func refresh() async {
        do {
            petals = try await PetalService.fetchPetals(fallback: petals)
        } catch {
            PetalService.log.error("app fetch failed: \(error.localizedDescription, privacy: .public)")
        }
        update()
    }

    /// Saves the sill for the widget, redraws its images, and asks it to reload.
    private func update() {
        FlowerStore.save(petals)
        FlowerRenderer.render(petals, onlyMissing: false)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

#Preview {
    ContentView()
}
