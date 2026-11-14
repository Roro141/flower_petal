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
            TicketButton("plant a random petal") { plant(Petal.random(owner: myID)) }
                .disabled(isPlanting)
            TicketButton("cut") { isCutting = true }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.wall)
        .task { await refresh() }
        .sheet(isPresented: $showingSamples) { SamplesView() }
        .fullScreenCover(isPresented: $isCutting) {
            CutView(paper: .dots, onBack: { isCutting = false }, onPlant: { petal in
                isCutting = false
                plant(petal)
            })
        }
    }

    /// Puts my new petal on the sill straight away, saves it to Supabase, then
    /// redraws this phone's widget with the saved copy (which has its real id).
    private func plant(_ petal: Petal) {
        guard let index = petals.firstIndex(where: { $0.owner == petal.owner }) else { return }
        petals[index] = petal
        isPlanting = true
        Task {
            do {
                petals[index] = try await PetalService.plant(petal)
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
