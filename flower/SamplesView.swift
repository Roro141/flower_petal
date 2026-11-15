import SwiftUI

/// Check screen: the five sample plants side by side, so the variety can be
/// judged by eye, and every bundled font for comparing (see `Fonts`).
struct SamplesView: View {
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 24) {
                ForEach(Array(Petal.samples.enumerated()), id: \.element.id) { index, petal in
                    PlantView(petal: petal, pot: PotStyle.allCases[index % PotStyle.allCases.count], size: 150)
                }
                // The same plants, wilted.
                ForEach(Array(Petal.samples.enumerated()), id: \.element.id) { index, petal in
                    PlantView(petal: petal, pot: PotStyle.allCases[index % PotStyle.allCases.count], size: 150,
                              isWilted: true)
                }
            }
            .padding(24)
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Typeface.allCases, id: \.self) { typeface in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("roha  junie  plant it")
                            .font(.custom(typeface.rawValue, size: 20))
                        Text(typeface.rawValue)
                            .font(.custom(typeface.rawValue, size: 13))
                            .foregroundStyle(Color.grey)
                    }
                }
            }
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.wall)
    }
}

#Preview {
    SamplesView()
        .onAppear { Fonts.register() }
}
