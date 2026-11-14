import SwiftUI

/// The two hard-coded friends for the spike.
enum SpikeUsers {
    static let names = ["a": "roha", "b": "junie"]
    static let ids = ["a", "b"]

    static func name(for id: String) -> String {
        names[id] ?? id
    }

    /// Which user this phone is. Set once per device in the app; the widget reads it too.
    static var myID: String {
        get { UserDefaults(suiteName: FlowerStore.appGroup)?.string(forKey: "myID") ?? "a" }
        set { UserDefaults(suiteName: FlowerStore.appGroup)?.set(newValue, forKey: "myID") }
    }
}

/// Reads and writes the sill's petals in the App Group container so the app
/// and the widget see the same data.
enum FlowerStore {
    static let appGroup = "group.com.RohaF.windowsill"
    private static let fileName = "petals.json"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    private static var fileURL: URL? {
        containerURL?.appendingPathComponent(fileName)
    }

    /// The sill's petals, one per friend in `SpikeUsers.ids` order.
    static func load() -> [Petal] {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let petals = try? JSONDecoder().decode([Petal].self, from: data)
        else { return defaultPetals }
        return petals
    }

    static func save(_ petals: [Petal]) {
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(petals) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Shown until a friend's first petal arrives.
    static var defaultPetals: [Petal] {
        SpikeUsers.ids.enumerated().map { index, id in
            var petal = Petal.samples[index]
            petal.owner = id
            return petal
        }
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
    static let mat = Color(hex: "#3E5747")
}
