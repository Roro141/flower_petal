import Foundation
import os

/// Talks to Supabase's REST API (PostgREST) directly with URLSession, so the
/// widget extension doesn't need the Supabase SDK.
enum PetalService {
    static let projectURL = URL(string: "https://zqhoiapbpdjwikrllehz.supabase.co")!
    // Publishable key: safe to ship in the app; row-level security does the gatekeeping.
    static let publishableKey = "sb_publishable_uERgWLl-Sa5cxxaerN3lSQ_g5QlyYob"

    static let log = Logger(subsystem: "windowsill.spike", category: "petals")

    /// A row in `petals_v2` / `latest_petals_v2`. `points` is null on spike rows.
    struct PetalRow: Codable, Sendable {
        var id: Int?
        let profile_id: String
        let pattern: String
        let n_petals: Int
        var points: [[Double]]?
        var created_at: Date?
    }

    enum ServiceError: Error {
        case badStatus(Int)
        case emptyResponse
    }

    /// Inserts `petal` and returns it as stored, with the id Supabase gave it.
    static func plant(_ petal: Petal) async throws -> Petal {
        var request = makeRequest(path: "petals_v2")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        let row = PetalRow(profile_id: petal.owner, pattern: petal.pattern.rawValue,
                           n_petals: petal.nPetals, points: petal.points)
        request.httpBody = try JSONEncoder().encode(row)

        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response)
        guard let stored = try decoder.decode([PetalRow].self, from: data).first else {
            throw ServiceError.emptyResponse
        }
        return Petal(row: stored)
    }

    /// Fetches each person's latest petal, in `SpikeUsers.ids` order.
    /// Anyone who hasn't planted yet keeps their cached (or default) petal.
    static func fetchPetals(fallback: [Petal]) async throws -> [Petal] {
        let request = makeRequest(path: "latest_petals_v2",
                                  query: "select=id,profile_id,pattern,n_petals,points,created_at")
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response)

        let rows = try decoder.decode([PetalRow].self, from: data)
        return SpikeUsers.ids.enumerated().map { index, id in
            if let row = rows.first(where: { $0.profile_id == id }) {
                return Petal(row: row)
            }
            return fallback.first(where: { $0.owner == id }) ?? FlowerStore.defaultPetals[index]
        }
    }

    // MARK: - Helpers

    private static func makeRequest(path: String, query: String? = nil) -> URLRequest {
        var components = URLComponents(url: projectURL.appending(path: "rest/v1/\(path)"), resolvingAgainstBaseURL: false)
        components?.query = query
        var request = URLRequest(url: components?.url ?? projectURL)
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        return request
    }

    private static func check(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ServiceError.badStatus(http.statusCode)
        }
    }

    /// Postgres timestamptz comes back with fractional seconds, which the default
    /// ISO 8601 strategy rejects.
    private static let decoder: JSONDecoder = {
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
    /// Builds a petal from a stored row. Spike rows have no points, so they get
    /// one of the sample shapes, picked from the row id.
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
