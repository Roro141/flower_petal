import SwiftUI

/// How your own window looks: frame, wall and curtain colours, picked in settings.
/// Only on this device (friends see their own windows), saved in the App Group so the
/// widget draws the same window. Views read it with `@AppStorage(..., store: WindowLook.store)`.
enum WindowLook {
    static let store = UserDefaults(suiteName: FlowerStore.appGroup)
    static let frameKey = "windowFrame"
    static let wallKey = "windowWall"
    static let fabricKey = "windowFabric"
}

/// A colour you can pick for part of the window. `name` is shown and spoken.
protocol WindowColour: RawRepresentable<String>, CaseIterable, Hashable where AllCases == [Self] {
    var colour: Color { get }
}

extension WindowColour {
    var name: String { rawValue.replacingOccurrences(of: "-", with: " ") }
}

enum FrameColour: String, WindowColour {
    case natural, white, sage, navy, cherry

    var colour: Color {
        switch self {
        case .natural: .wood
        case .white: Color(hex: "#F3EFE6")
        case .sage: Color(hex: "#8FA08A")
        case .navy: Color(hex: "#3E4C6B")
        case .cherry: Color(hex: "#8E3B34")
        }
    }
}

enum WallColour: String, WindowColour {
    case cream, blush, olive, inkBlue = "ink-blue", linen

    var colour: Color {
        switch self {
        case .cream: .wall
        case .blush: Color(hex: "#EFD9CF")
        case .olive: Color(hex: "#C9C7A2")
        case .inkBlue: Color(hex: "#C7D0D8")
        case .linen: Color(hex: "#E6E1D3")
        }
    }
}

enum FabricColour: String, WindowColour {
    case cream, sage, apricot, rose, slate, navy

    var colour: Color {
        switch self {
        case .cream: .cream
        case .sage: Color(hex: "#B9C4AE")
        case .apricot: Color(hex: "#E8C9A0")
        case .rose: Color(hex: "#D9A5A0")
        case .slate: Color(hex: "#5E7A8C")
        case .navy: Color(hex: "#3E4C6B")
        }
    }
}

/// The wall behind the window, in your chosen colour.
struct WallFill: View {
    @AppStorage(WindowLook.wallKey, store: WindowLook.store) private var wall: WallColour = .cream

    var body: some View {
        wall.colour
    }
}
