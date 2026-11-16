import Foundation
import Security
import os

/// A signed-in Supabase session. Kept in the App Group's keychain so the widget
/// signs in as the same person and only ever sees their own windowsill.
struct Session: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let userID: String
}

/// Sign in with Apple → Supabase Auth, over plain URLSession (no SDK, so the
/// widget can use it too).
enum Auth {
    enum AuthError: Error {
        case badStatus(Int)
    }

    /// Exchanges the identity token from Sign in with Apple for a Supabase session.
    /// `nonce` is the raw nonce whose SHA-256 was sent to Apple.
    static func signInWithApple(idToken: String, nonce: String) async throws -> Session {
        let session = try await token(grant: "id_token", body: ["provider": "apple", "id_token": idToken, "nonce": nonce])
        SessionKeychain.save(session)
        return session
    }

    /// TEMPORARY, for testing while Sign in with Apple isn't working yet: a Supabase
    /// anonymous account (needs "Allow anonymous sign-ins" on in the dashboard).
    /// Remove before real use.
    static func signInAnonymously() async throws -> Session {
        let session = try await post(path: "auth/v1/signup", query: nil, body: [:])
        SessionKeychain.save(session)
        return session
    }

    /// The saved session, refreshed first if it expires within a minute.
    /// nil when nobody is signed in on this phone.
    static func currentSession() async throws -> Session? {
        guard let saved = SessionKeychain.load() else { return nil }
        if saved.expiresAt > Date.now.addingTimeInterval(60) { return saved }
        do {
            let fresh = try await token(grant: "refresh_token", body: ["refresh_token": saved.refreshToken])
            SessionKeychain.save(fresh)
            return fresh
        } catch AuthError.badStatus(let status) where (400..<500).contains(status) {
            // The app and the widget can both try to refresh; if the other one won,
            // its new session is already in the keychain.
            if let other = SessionKeychain.load(), other.refreshToken != saved.refreshToken { return other }
            SessionKeychain.delete()
            return nil
        }
    }

    static func signOut() {
        SessionKeychain.delete()
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_in: Double
        let user: User
        struct User: Decodable { let id: String }
    }

    private static func token(grant: String, body: [String: String]) async throws -> Session {
        try await post(path: "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: grant)], body: body)
    }

    private static func post(path: String, query: [URLQueryItem]?, body: [String: String]) async throws -> Session {
        var components = URLComponents(url: PetalService.projectURL.appending(path: path),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = query
        var request = URLRequest(url: components?.url ?? PetalService.projectURL)
        request.httpMethod = "POST"
        request.setValue(PetalService.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? ""
            PetalService.log.error("auth \(path, privacy: .public) failed: \(http.statusCode) \(message, privacy: .public)")
            throw AuthError.badStatus(http.statusCode)
        }
        let reply = try JSONDecoder().decode(TokenResponse.self, from: data)
        return Session(accessToken: reply.access_token, refreshToken: reply.refresh_token,
                       expiresAt: Date.now.addingTimeInterval(reply.expires_in), userID: reply.user.id)
    }
}

/// One keychain item in the App Group's access group, readable after first unlock
/// (so the widget can refresh while the phone is locked).
private enum SessionKeychain {
    private static var query: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "windowsill.session",
            kSecAttrAccount as String: "supabase",
            kSecAttrAccessGroup as String: FlowerStore.appGroup,
        ]
        #if os(macOS)
        // The Mac only shares keychain items through an access group in the
        // iOS-style (data protection) keychain.
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    static func load() -> Session? {
        var request = query
        request[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    static func save(_ session: Session) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            SecItemAdd(query.merging(update) { $1 } as CFDictionary, nil)
        }
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
