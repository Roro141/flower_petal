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
                // Always the paper look (wall, cream, ink), matching the widget, even
                // when the phone or Mac is in dark mode.
                .preferredColorScheme(.light)
        }
        #if os(macOS)
        .defaultSize(width: 520, height: 760)
        #endif
        #if os(macOS)
        // The window scene in the menu bar, with the wind playing in full.
        MenuBarExtra {
            SillPanel()
                .preferredColorScheme(.light)
        } label: {
            Image(nsImage: MenuBarFlower.image)
                .accessibilityLabel("Windowsill")
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}
