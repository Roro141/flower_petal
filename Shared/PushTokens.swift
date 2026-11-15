import Foundation
import WidgetKit
import os

/// Keeps Supabase up to date with this phone's widget push token, so a friend
/// planting can nudge this widget straight away (see supabase/functions/widget-push).
enum PushTokens {
    /// Builds from Xcode use Apple's development push server; App Store builds use production.
    private static var environment: String {
        #if DEBUG
        "development"
        #else
        "production"
        #endif
    }

    /// Saves `token` for whoever is signed in on this phone. Does nothing when signed out;
    /// the app uploads again after signing in.
    static func upload(_ token: Data) async {
        do {
            guard let session = try await Auth.currentSession() else { return }
            let hex = token.map { String(format: "%02x", $0) }.joined()
            try await PetalService.saveWidgetToken(hex, environment: environment, session)
        } catch {
            PetalService.log.error("saving widget push token failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Uploads the current token, if WidgetKit has made one yet (it needs a widget on the home screen).
    static func uploadCurrent() async {
        guard let info = await WidgetCenter.shared.currentPushInfo else { return }
        await upload(info.token)
    }
}
