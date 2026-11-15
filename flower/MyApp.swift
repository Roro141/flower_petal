import SwiftUI

@main struct MyApp: App {
    init() {
        Fonts.register()
        // The keychain outlives the app, so a sign-in from before it was deleted would
        // still be there. A fresh install should start signed out. (The app's own
        // defaults are wiped on delete, so a missing flag means a fresh install.)
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            Auth.signOut()
            FlowerStore.save(nil)
            UserDefaults.standard.set(true, forKey: "hasLaunched")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
