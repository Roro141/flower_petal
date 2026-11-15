import SwiftUI

/// Someone on the windowsill.
struct Member: Codable, Hashable, Sendable {
    let id: String
    var name: String
    var joinedAt: Date?
}

/// A gust of wind through the windowsill. `seed` decides who loses a petal,
/// which one, and where it lands, so every phone shows the same gust.
struct Gust: Codable, Hashable, Sendable {
    let id: Int
    let seed: Int
    let createdAt: Date
}

extension Gust {
    /// The design's ease-out for the lean: cubic-bezier(.2, .8, .2, 1).
    static let leanCurve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.2, y: 0.8),
                                            endControlPoint: UnitPoint(x: 0.2, y: 1))

    /// The spring back after the hold (response 0.9, damping 0.55), sped up for replays.
    static func springBack(speed: Double) -> Spring {
        Spring(response: 0.9 / speed, dampingRatio: 0.55)
    }

    /// A gust that blew while the app was closed replays once at this speed (about 1.2 s).
    static let catchUpSpeed = 1.8

    /// When the petals let go: at the height of the lean, once every flower has started
    /// leaning (they go 40 ms apart).
    static func releaseDelay(flowers: Int, speed: Double) -> Double {
        (0.45 + Double(flowers) * 0.04) / speed
    }

    /// How long a blown-off petal is in the air, from the flower to the sill.
    static let flightTime = 0.9

    /// How far a flower leans to the right in this gust: 10–22°, different for each.
    func lean(for owner: String) -> Double {
        var random = SeededRandom("\(owner)-\(id)-lean")
        return 10 + random.next() * 12
    }
}

/// Everything the window shows: who is on this windowsill, in sill order (me
/// first, then friends in the order they joined), and each person's latest petal,
/// in the same order, plus the last gust (whose fallen petals lie on the sill).
struct Sill: Codable, Equatable, Sendable {
    var groupID: String
    var inviteCode: String
    var myID: String
    var members: [Member]
    var petals: [Petal]
    /// Recent gusts, oldest first. Petals they blew off stay off (and on the sill)
    /// until the flower's owner plants a new one.
    var gusts: [Gust] = []

    /// The newest gust: the one that plays when it's new to this phone.
    var gust: Gust? { gusts.last }

    func name(for owner: String) -> String {
        members.first { $0.id == owner }?.name ?? ""
    }

    var inviteURL: URL? { URL(string: "windowsill://join/\(inviteCode)") }

    /// Everyone in the order they joined (ties broken by id). The same on every phone.
    static func joinOrder(_ members: [Member]) -> [Member] {
        members.sorted { ($0.joinedAt ?? .distantPast, $0.id) < ($1.joinedAt ?? .distantPast, $1.id) }
    }

    /// Me first, then everyone else in the order they joined.
    static func sillOrder(_ members: [Member], me: String) -> [Member] {
        members.filter { $0.id == me } + joinOrder(members).filter { $0.id != me }
    }

    /// Where someone comes in join order (0 = whoever started the windowsill). It's
    /// the same on every phone, so it picks what should look the same everywhere:
    /// their pot and, until they cut one, their placeholder flower.
    func joinRank(of owner: String) -> Int {
        Self.joinOrder(members).firstIndex { $0.id == owner } ?? 0
    }

    /// Each member's petal, in sill order. Someone who hasn't cut one yet gets a
    /// sample shape (unsaved, so it never wilts) until they do. The sample goes by
    /// join order, so it's the same on every phone and different for each person.
    static func petals(for members: [Member], latest: [Petal]) -> [Petal] {
        let joined = joinOrder(members)
        return members.enumerated().map { index, member in
            if let petal = latest.first(where: { $0.owner == member.id }) { return petal }
            let rank = joined.firstIndex { $0.id == member.id } ?? index
            let sample = Petal.samples[rank % Petal.samples.count]
            return Petal(id: -(index + 1), owner: member.id, pattern: sample.pattern,
                         nPetals: sample.nPetals, points: sample.points)
        }
    }

    /// Whose flowers a gust hits (one or two of them, different people) and which
    /// petal it aims for on each. Picked from the gust's seed, so every phone agrees.
    func aims(of gust: Gust) -> [(owner: String, petal: Int)] {
        var random = SeededRandom(seed: UInt64(truncatingIfNeeded: gust.seed))
        var owners = Self.joinOrder(members).map(\.id)
        let count = min(owners.count, random.next() < 0.5 ? 1 : 2)
        return (0..<count).map { _ in
            let owner = owners.remove(at: Int(random.next() * Double(owners.count)))
            return (owner: owner, petal: Int(random.next() * 8))
        }
    }

    /// A flower never loses more than this many fewer than it was cut with, so it's
    /// always still a flower (at least two petals).
    private static let petalsKept = 2

    /// Every petal the wind has taken from each flower since it was planted, oldest
    /// first, and the gust that took it. Gusts add up: each takes a petal the flower
    /// still has. These are also the petals lying on the sill.
    var windLosses: [String: [(petal: Int, gust: Gust)]] {
        var losses: [String: [(petal: Int, gust: Gust)]] = [:]
        for gust in gusts {
            for aim in aims(of: gust) {
                guard let flower = petals.first(where: { $0.owner == aim.owner }) else { continue }
                // A flower planted after this gust wasn't there to lose anything.
                if let planted = flower.createdAt, planted > gust.createdAt { continue }
                let count = min(max(flower.nPetals, 5), 8)
                let taken = Set((losses[aim.owner] ?? []).map(\.petal))
                guard taken.count < count - Self.petalsKept else { continue }
                // The petal it aimed for, or the next one round that's still there.
                let index = (0..<count).map { (aim.petal + $0) % count }.first { !taken.contains($0) } ?? 0
                losses[aim.owner, default: []].append((petal: index, gust: gust))
            }
        }
        return losses
    }

    /// The petals missing from this flower. `exceptNewest` leaves out the newest gust's,
    /// for while that gust is still blowing.
    func missingPetals(for petal: Petal, exceptNewest: Bool = false) -> Set<Int> {
        let losses = (windLosses[petal.owner] ?? []).filter { !(exceptNewest && $0.gust == gust) }
        return Set(losses.map(\.petal))
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
