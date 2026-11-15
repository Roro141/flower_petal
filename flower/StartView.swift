import SwiftUI
import AuthenticationServices
import CryptoKit
import os

/// Sign in with Apple. Hands back a Supabase session.
struct SignInView: View {
    var onSignedIn: (Session, String?) -> Void

    /// The raw nonce for the request in flight; Apple gets its SHA-256.
    @State private var nonce = ""

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("windowsill")
                .font(Fonts.title())
                .foregroundStyle(Color.ink)
            SignInWithAppleButton(.signIn) { request in
                nonce = Self.randomNonce()
                request.requestedScopes = [.fullName]
                request.nonce = Self.sha256(nonce)
            } onCompletion: { result in
                handle(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(maxWidth: 280, minHeight: 50, maxHeight: 50)
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
        let rawNonce = nonce
        Task {
            do {
                let session = try await Auth.signInWithApple(idToken: idToken, nonce: rawNonce)
                onSignedIn(session, givenName)
            } catch {
                PetalService.log.error("supabase sign in failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func randomNonce() -> String {
        let characters = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return String((0..<32).compactMap { _ in characters.randomElement() })
    }

    private static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
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
                .textInputAutocapitalization(.never)
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
