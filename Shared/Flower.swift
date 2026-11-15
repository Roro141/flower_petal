import SwiftUI

/// Someone on the windowsill.
struct Member: Codable, Hashable, Sendable {
    let id: String
    var name: String
    var joinedAt: Date?
}

/// Everything the window shows: who is on this windowsill, in sill order (me
/// first, then friends in the order they joined), and each person's latest petal,
/// in the same order.
struct Sill: Codable, Sendable {
    var groupID: String
    var inviteCode: String
    var myID: String
    var members: [Member]
    var petals: [Petal]

    func name(for owner: String) -> String {
        members.first { $0.id == owner }?.name ?? ""
    }

    var inviteURL: URL? { URL(string: "windowsill://join/\(inviteCode)") }

    /// Me first, then everyone else in the order they joined.
    static func sillOrder(_ members: [Member], me: String) -> [Member] {
        let mine = members.filter { $0.id == me }
        let others = members.filter { $0.id != me }
            .sorted { ($0.joinedAt ?? .distantPast) < ($1.joinedAt ?? .distantPast) }
        return mine + others
    }

    /// Each member's petal, in sill order. Someone who hasn't cut one yet gets a
    /// sample shape (unsaved, so it never wilts) until they do.
    static func petals(for members: [Member], latest: [Petal]) -> [Petal] {
        members.enumerated().map { index, member in
            if let petal = latest.first(where: { $0.owner == member.id }) { return petal }
            let sample = Petal.samples[index % Petal.samples.count]
            return Petal(id: -(index + 1), owner: member.id, pattern: sample.pattern,
                         nPetals: sample.nPetals, points: sample.points)
        }
    }

    /// Two made-up friends, for previews and the widget gallery.
    static let preview: Sill = {
        let members = [Member(id: "a", name: "roha"), Member(id: "b", name: "junie")]
        return Sill(groupID: "", inviteCode: "", myID: "a", members: members,
                    petals: petals(for: members, latest: []))
    }()
}

/// Keeps the last known sill in the App Group container, so the app opens
/// straight onto it and the widget can show it without the network.
enum FlowerStore {
    static let appGroup = "group.com.RohaF.windowsill"
    private static let fileName = "sill.json"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    private static var fileURL: URL? {
        containerURL?.appendingPathComponent(fileName)
    }

    static func load() -> Sill? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Sill.self, from: data)
    }

    static func save(_ sill: Sill?) {
        guard let url = fileURL else { return }
        guard let sill, let data = try? JSONEncoder().encode(sill) else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? data.write(to: url, options: .atomic)
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
