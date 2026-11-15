import SwiftUI
import CoreText

/// The bundled Google Fonts (in Shared/Fonts), by PostScript name.
enum Typeface: String, CaseIterable {
    case theGirlNextDoor = "TheGirlNextDoor"
    case specialElite = "SpecialElite-Regular"
    case patrickHand = "PatrickHand-Regular"
    case indieFlower = "IndieFlower-Regular"
    case coveredByYourGrace = "CoveredByYourGrace"
    case atkinson = "AtkinsonHyperlegible-Regular"
    case atkinsonBold = "AtkinsonHyperlegible-Bold"
}

/// Every piece of text in the app and widget gets its font from here.
/// To try a different font, change `handwriting` or `reading`, then rebuild.
enum Fonts {
    /// Names, labels and titles.
    static let handwriting: Typeface = .indieFlower
    /// Body text.
    static let reading: Typeface = .atkinson
    /// Button labels.
    static let buttons: Typeface = .atkinsonBold

    /// Names under the pots and other small labels. Indie Flower runs small, so 16
    /// here reads about like a 13 pt label (never below 12).
    static func label() -> Font { .custom(handwriting.rawValue, size: 16, relativeTo: .caption) }
    static func title() -> Font { .custom(handwriting.rawValue, size: 20, relativeTo: .title3) }
    static func body() -> Font { .custom(reading.rawValue, size: 15, relativeTo: .body) }
    static func button() -> Font { .custom(buttons.rawValue, size: 15, relativeTo: .body) }

    /// Makes the bundled fonts available to this process. Call once at launch,
    /// in the app and in the widget extension.
    static func register() {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) else { return }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }
}
