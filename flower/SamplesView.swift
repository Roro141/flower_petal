import SwiftUI

/// Design check, previews only (not reachable in the app): the five sample plants,
/// fresh and wilted, and every bundled font for comparing (see `Fonts`).
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

/// For the how-to guide (docs/HOW-TO.md): the main screen as it looks once you're on a
/// windowsill with friends. The real one needs a signed-in session to show.
#Preview("How-to: main screen") {
    VStack(spacing: 0) {
        HStack {
            Spacer()
            TapeLabel(text: "invite", tilt: 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        Spacer()
        SillView(sill: .preview, plantSize: 96)
        Spacer()
        TicketButton("cut") {}
        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background {
        Color.wall.ignoresSafeArea()
        PaperGrain().ignoresSafeArea()
    }
}
