import SwiftUI

/// Milestone 1 check screen: the five sample flowers side by side, so the
/// variety can be judged by eye.
struct SamplesView: View {
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 24) {
                ForEach(Petal.samples) { petal in
                    FlowerView(petal: petal, size: 160)
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
