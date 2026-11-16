import SwiftUI
import AuthenticationServices
import CryptoKit
import os

/// Sign in with Apple. Hands back a Supabase session.
struct SignInView: View {
    var onSignedIn: (Session, String?) -> Void

    /// Every raw nonce handed out, keyed by the SHA-256 that Apple was given. The
    /// button can ask for a new request more than once per tap (it does on the Mac),
    /// so the right one is looked up from Apple's reply rather than assumed.
    @State private var nonces = Nonces()

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("windowsill")
                .font(Fonts.title())
                .foregroundStyle(Color.ink)
            SignInWithAppleButton(.signIn) { request in
                // Supabase needs an email to create the account (Apple may hand over a private relay one).
                request.requestedScopes = [.fullName, .email]
                request.nonce = nonces.issue()
            } onCompletion: { result in
                handle(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(maxWidth: 280, minHeight: 50, maxHeight: 50)
            // TEMPORARY: a test account while Sign in with Apple isn't set up. Remove before real use.
            Button {
                Task {
                    do {
                        onSignedIn(try await Auth.signInAnonymously(), nil)
                    } catch {
                        PetalService.log.error("anonymous sign in failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            } label: {
                Text("try without apple")
                    .font(Fonts.body())
                    .foregroundStyle(Color.grey)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.wall)
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            if case .failure(let error) = result {
                PetalService.log.error("sign in with apple failed: \(error.localizedDescription, privacy: .public)")
            }
            return
        }
        // Apple only shares the name the first time someone signs in.
        let givenName = credential.fullName?.givenName
        guard let rawNonce = nonces.raw(for: idToken) else {
            PetalService.log.error("sign in with apple: no matching nonce")
            return
        }
        Task {
            do {
                let session = try await Auth.signInWithApple(idToken: idToken, nonce: rawNonce)
                onSignedIn(session, givenName)
            } catch {
                PetalService.log.error("supabase sign in failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

}

/// One-time codes for Sign in with Apple. Apple gets the SHA-256 of a random code;
/// Supabase gets the code itself and checks it matches what Apple signed.
final class Nonces {
    private var issued: [String: String] = [:]

    /// A fresh code: returns the hash to give Apple, and remembers the code.
    func issue() -> String {
        let characters = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let raw = String((0..<32).compactMap { _ in characters.randomElement() })
        let hash = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
        issued[hash] = raw
        return hash
    }

    /// The code behind the hash in Apple's identity token (its `nonce` claim).
    func raw(for idToken: String) -> String? {
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        // The token's middle part is base64url JSON.
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hash = claims["nonce"] as? String else { return nil }
        return issued[hash]
    }
}

/// The name that goes under your pot.
struct NameView: View {
    @State var name: String
    var onDone: (String) -> Void

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            TextField("name", text: $name)
                .font(Fonts.body())
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .submitLabel(.done)
                .padding(.horizontal, 16)
                .frame(maxWidth: 240, minHeight: 44)
                .background(Color.cream, in: .rect(cornerRadius: 2))
                .onChange(of: name) { _, newValue in
                    // Fits under a pot.
                    if newValue.count > 24 { name = String(newValue.prefix(24)) }
                }
            TicketButton("that's me") { onDone(trimmed) }
                .disabled(trimmed.isEmpty)
                .opacity(trimmed.isEmpty ? 0.5 : 1)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.wall)
    }
}

/// Signed in and named, but not on a windowsill yet: start one, or open a friend's invite link.
struct StartWindowsillView: View {
    var onStart: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            WindowScene(sill: Sill(groupID: "", inviteCode: "", myID: "", members: [], petals: [])) { _, _ in
                EmptyView()
            }
            .frame(height: 220)
            TicketButton("start a windowsill", action: onStart)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.wall)
    }
}

#Preview("Sign in") {
    SignInView { _, _ in }
}

#Preview("Name") {
    NameView(name: "roha") { _ in }
}

#Preview("Start") {
    StartWindowsillView {}
}
