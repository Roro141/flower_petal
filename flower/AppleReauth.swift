import AuthenticationServices
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Asks Sign in with Apple once more, just for a fresh authorization code. Deleting an
/// account sends it to the server, which uses it to cancel the app's Sign in with Apple
/// link (Apple requires that when an account is deleted).
@MainActor
final class AppleReauth: NSObject, ASAuthorizationControllerDelegate,
                         ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<String?, Never>?
    /// Keeps the helper alive while Apple's sheet is up.
    private static var current: AppleReauth?

    /// The code, or nil if it was cancelled or failed (the account is still deleted).
    static func authorizationCode() async -> String? {
        let helper = AppleReauth()
        current = helper
        defer { current = nil }
        return await withCheckedContinuation { continuation in
            helper.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = helper
            controller.presentationContextProvider = helper
            controller.performRequests()
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithAuthorization authorization: ASAuthorization) {
        let code = (authorization.credential as? ASAuthorizationAppleIDCredential)?
            .authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        Task { @MainActor in self.finish(code) }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            #if os(iOS)
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
            #else
            NSApplication.shared.keyWindow ?? ASPresentationAnchor()
            #endif
        }
    }

    private func finish(_ code: String?) {
        continuation?.resume(returning: code)
        continuation = nil
    }
}
