import Foundation
import os

/// Talks to Supabase's REST API (PostgREST) directly with URLSession, so the
/// widget extension doesn't need the Supabase SDK.
enum PetalService {
    static let projectURL = URL(string: "https://zqhoiapbpdjwikrllehz.supabase.co")!
    // Publishable key: safe to ship in the app; row-level security does the gatekeeping.
    static let publishableKey = "sb_publishable_uERgWLl-Sa5cxxaerN3lSQ_g5QlyYob"

    static let log = Logger(subsystem: "windowsill.spike", category: "petals")

    /// A row in `petals_v2` / `latest_petals_v2`.
    struct PetalRow: Codable, Sendable {
        let profile_id: String
        let pattern: String
        let n_petals: Int
        var created_at: Date?
    }

    enum ServiceError: Error {
        case badStatus(Int)
    }

    /// Inserts a new petal for `flower`'s owner.
    static func plant(_ flower: Flower) async throws {
        var request = makeRequest(path: "petals_v2")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        let row = PetalRow(profile_id: flower.id, pattern: flower.colorHex, n_petals: flower.petalCount)
        request.httpBody = try JSONEncoder().encode(row)

        let (_, response) = try await URLSession.shared.data(for: request)
        try check(response)
    }

    /// Fetches each person's latest petal and turns them into flowers, in a stable order.
    /// Anyone who hasn't planted yet keeps their cached (or default) flower.
    static func fetchFlowers(fallback: [Flower]) async throws -> (flowers: [Flower], rows: [PetalRow]) {
        let request = makeRequest(path: "latest_petals_v2", query: "select=profile_id,pattern,n_petals,created_at")
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response)

        let rows = try decoder.decode([PetalRow].self, from: data)
        let flowers = SpikeUsers.ids.map { id -> Flower in
            if let row = rows.first(where: { $0.profile_id == id }) {
                return Flower(id: id, name: SpikeUsers.names[id] ?? id, petalCount: row.n_petals, colorHex: row.pattern)
            }
            return fallback.first(where: { $0.id == id })
                ?? Flower(id: id, name: SpikeUsers.names[id] ?? id, petalCount: 5, colorHex: "#4A6FA5")
        }
        return (flowers, rows)
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
