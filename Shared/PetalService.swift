import Foundation
import os

/// Talks to Supabase's REST API (PostgREST) directly with URLSession, so the
/// widget extension doesn't need the Supabase SDK. Every call is made as the
/// signed-in person; row-level security only lets them see their own windowsill.
enum PetalService {
    static let projectURL = URL(string: "https://zqhoiapbpdjwikrllehz.supabase.co")!
    // Publishable key: safe to ship in the app; row-level security does the gatekeeping.
    static let publishableKey = "sb_publishable_uERgWLl-Sa5cxxaerN3lSQ_g5QlyYob"

    static let log = Logger(subsystem: "windowsill", category: "petals")

    /// A row in `petals` / `latest_petals`.
    struct PetalRow: Codable, Sendable {
        var id: Int?
        let profile_id: String
        let pattern: String
        let n_petals: Int
        var points: [[Double]]?
        var created_at: Date?
    }

    /// What the app sends when planting; the server fills in id, owner and time.
    struct NewPetal: Encodable {
        let group_id: String
        let points: [[Double]]
        let pattern: String
        let n_petals: Int
    }

    private struct MemberRow: Decodable {
        let group_id: String
        let profile_id: String
        let joined_at: Date?
        let profiles: ProfileName?
        let groups: GroupRow?
    }

    private struct GustRow: Decodable {
        let id: Int
        let seed: Int
        let created_at: Date
    }

    private struct ProfileName: Decodable {
        let name: String
    }

    private struct GroupRow: Decodable {
        let id: String?
        let invite_code: String
    }

    enum ServiceError: Error {
        case badStatus(Int)
        case emptyResponse
    }

    // MARK: - Profile and windowsill

    /// My name, or nil if I haven't picked one yet.
    static func myName(_ session: Session) async throws -> String? {
        let request = makeRequest(path: "profiles", query: "select=name&id=eq.\(session.userID)", session: session)
        let rows: [ProfileName] = try await send(request)
        return rows.first?.name
    }

    static func saveName(_ name: String, _ session: Session) async throws {
        var request = makeRequest(path: "profiles", query: "on_conflict=id", session: session)
        request.httpMethod = "POST"
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode(["id": session.userID, "name": name])
        try await sendIgnoringBody(request)
    }

    /// Starts a new windowsill with me on it.
    static func createGroup(_ session: Session) async throws {
        var request = makeRequest(path: "rpc/create_group", session: session)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        try await sendIgnoringBody(request)
    }

    /// Joins the windowsill from an invite link's code.
    static func joinGroup(code: String, _ session: Session) async throws {
        var request = makeRequest(path: "rpc/join_group", session: session)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(["code": code])
        try await sendIgnoringBody(request)
    }

    /// My windowsill: its members in sill order and each one's latest petal.
    /// nil if I'm not on one yet.
    static func fetchSill(_ session: Session) async throws -> Sill? {
        let memberRequest = makeRequest(
            path: "members",
            query: "select=group_id,profile_id,joined_at,profiles(name),groups(id,invite_code)&order=joined_at.asc",
            session: session
        )
        let rows: [MemberRow] = try await send(memberRequest)
        // The windowsill I joined most recently, so opening a friend's invite takes me
        // to theirs even if I'd already started my own. (rows are oldest first.)
        guard let mine = rows.last(where: { $0.profile_id == session.userID }),
              let inviteCode = mine.groups?.invite_code else { return nil }

        let members = rows
            .filter { $0.group_id == mine.group_id }
            .map { Member(id: $0.profile_id, name: $0.profiles?.name ?? "", joinedAt: $0.joined_at) }
        let ordered = Sill.sillOrder(members, me: session.userID)

        let petalRequest = makeRequest(
            path: "latest_petals",
            query: "select=id,profile_id,pattern,n_petals,points,created_at&group_id=eq.\(mine.group_id)",
            session: session
        )
        let latest: [PetalRow] = try await send(petalRequest)

        let gustRequest = makeRequest(
            path: "gusts",
            // The last 30 gusts are plenty: petals lost before a flower was planted don't count.
            query: "select=id,seed,created_at&group_id=eq.\(mine.group_id)&order=created_at.desc&limit=30",
            session: session
        )
        let gusts: [GustRow] = try await send(gustRequest)

        return Sill(groupID: mine.group_id, inviteCode: inviteCode, myID: session.userID,
                    members: ordered, petals: Sill.petals(for: ordered, latest: latest.map(Petal.init(row:))),
                    gusts: gusts.reversed().map { Gust(id: $0.id, seed: $0.seed, createdAt: $0.created_at) })
    }

    /// TEMPORARY, for testing: blows a gust through my windowsill right now.
    static func testGust(_ session: Session) async throws {
        var request = makeRequest(path: "rpc/test_gust", session: session)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        try await sendIgnoringBody(request)
    }

    /// Saves this phone's widget push token for me, so friends' new petals can nudge my widget.
    static func saveWidgetToken(_ token: String, environment: String, _ session: Session) async throws {
        var request = makeRequest(path: "rpc/save_widget_token", session: session)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(["token": token, "environment": environment])
        try await sendIgnoringBody(request)
    }

    /// Plants `petal` on the windowsill and returns it as stored, with its id and time.
    static func plant(_ petal: Petal, groupID: String, _ session: Session) async throws -> Petal {
        var request = makeRequest(path: "petals", session: session)
        request.httpMethod = "POST"
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode(
            NewPetal(group_id: groupID, points: petal.points, pattern: petal.pattern.rawValue, n_petals: petal.nPetals)
        )
        let rows: [PetalRow] = try await send(request)
        guard let stored = rows.first else { throw ServiceError.emptyResponse }
        return Petal(row: stored)
    }

    // MARK: - Helpers

    private static func makeRequest(path: String, query: String? = nil, session: Session) -> URLRequest {
        var components = URLComponents(url: projectURL.appending(path: "rest/v1/\(path)"), resolvingAgainstBaseURL: false)
        components?.query = query
        var request = URLRequest(url: components?.url ?? projectURL)
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private static func send<Value: Decodable>(_ request: URLRequest) async throws -> Value {
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data: data)
        return try decoder.decode(Value.self, from: data)
    }

    private static func sendIgnoringBody(_ request: URLRequest) async throws {
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data: data)
    }

    private static func check(_ response: URLResponse, data: Data) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? ""
            log.error("\(http.url?.path ?? "", privacy: .public) → \(http.statusCode): \(message, privacy: .public)")
            throw ServiceError.badStatus(http.statusCode)
        }
    }

    /// Postgres timestamptz comes back with fractional seconds, which the default
    /// ISO 8601 strategy rejects.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFraction.date(from: string) ?? ISO8601DateFormatter().date(from: string) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: string))
        }
        return decoder
    }()
}

extension Petal {
    /// Builds a petal from a stored row. Rows without a usable shape get one of
    /// the sample shapes, picked from the row id; spike-era colour patterns map
    /// to the nearest paper.
    init(row: PetalService.PetalRow) {
        let id = row.id ?? 0
        let points = row.points ?? []
        let shapes = Petal.sampleShapes
        self.init(
            id: id,
            owner: row.profile_id,
            pattern: Paper(stored: row.pattern),
            nPetals: row.n_petals,
            points: points.count >= 3 ? points : shapes[abs(id) % shapes.count],
            createdAt: row.created_at
        )
    }
}
