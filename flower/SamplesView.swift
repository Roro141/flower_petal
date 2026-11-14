import SwiftUI

/// Milestone 1 check screen: the five sample plants side by side, so the
/// variety can be judged by eye.
struct SamplesView: View {
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 24) {
                ForEach(Array(Petal.samples.enumerated()), id: \.element.id) { index, petal in
                    PlantView(petal: petal, pot: PotStyle.allCases[index % PotStyle.allCases.count], size: 150)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.wall)
    }
}

#Preview {
    SamplesView()
}
