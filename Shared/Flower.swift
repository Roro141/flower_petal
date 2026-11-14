import SwiftUI

/// One friend's flower, as stored locally and shown on the sill.
/// For the spike a flower is just a petal count and a solid colour; the real
/// version will carry the half-petal polygon and a paper pattern.
struct Flower: Codable, Hashable, Identifiable, Sendable {
    let id: String          // profile id
    var name: String
    var petalCount: Int     // 5–8
    var colorHex: String

    static let palette = ["#C8473B", "#4A6FA5", "#9C88B8", "#E2B53E", "#D9793A"]

    static func random(id: String, name: String) -> Flower {
        Flower(
            id: id,
            name: name,
            petalCount: Int.random(in: 5...8),
            colorHex: palette.randomElement() ?? "#C8473B"
        )
    }
}

/// The two hard-coded friends for the spike.
enum SpikeUsers {
    static let names = ["a": "roha", "b": "junie"]
    static let ids = ["a", "b"]

    /// Which user this phone is. Set once per device in the app; the widget reads it too.
    static var myID: String {
        get { UserDefaults(suiteName: FlowerStore.appGroup)?.string(forKey: "myID") ?? "a" }
        set { UserDefaults(suiteName: FlowerStore.appGroup)?.set(newValue, forKey: "myID") }
    }
}

/// Reads and writes the sill's flowers in the App Group container so the app
/// and the widget see the same data.
enum FlowerStore {
    static let appGroup = "group.com.RohaF.windowsill"
    private static let fileName = "flowers.json"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(fileName)
    }

    static func load() -> [Flower] {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let flowers = try? JSONDecoder().decode([Flower].self, from: data)
        else { return defaultFlowers }
        return flowers
    }

    static func save(_ flowers: [Flower]) {
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(flowers) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static var defaultFlowers: [Flower] {
        [
            Flower(id: "a", name: SpikeUsers.names["a"] ?? "a", petalCount: 6, colorHex: "#C8473B"),
            Flower(id: "b", name: SpikeUsers.names["b"] ?? "b", petalCount: 5, colorHex: "#4A6FA5"),
        ]
    }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    static let ink = Color(hex: "#2B211A")
    static let grey = Color(hex: "#5A5249")
    static let sky = Color(hex: "#DCE4E1")
    static let cream = Color(hex: "#FBF6EC")
    static let wall = Color(hex: "#F1E7D5")
    static let wood = Color(hex: "#C29A6B")
    static let sill = Color(hex: "#B98E62")
}
