import SwiftUI
import WidgetKit

/// Settings: a kraft paper page of cream cards, each laid down slightly crooked.
/// The top card is a live preview of your window; the rows below open their own pages.
struct SettingsView: View {
    let sill: Sill
    var onBack: () -> Void
    var onRename: (String) -> Void
    var onSignOut: () -> Void
    var onDeleteAccount: () -> Void

    private enum Page { case window, sill, widgets, account }
    @State private var page: Page?
    @State private var showsHowTo = false
    @AppStorage(WindowLook.frameKey, store: WindowLook.store) private var frame: FrameColour = .natural
    @AppStorage(WindowLook.wallKey, store: WindowLook.store) private var wall: WallColour = .cream
    @AppStorage(WindowLook.fabricKey, store: WindowLook.store) private var fabric: FabricColour = .cream

    static let privacyPolicy = URL(string: "https://github.com/Roro141/flower_petal/blob/main/docs/PRIVACY.md")!

    var body: some View {
        Group {
            switch page {
            case nil: main
            case .window: windowPage
            case .sill: sillPage
            case .widgets: widgetsPage
            case .account: AccountPage(name: sill.name(for: sill.myID), onBack: { page = nil },
                                       onRename: onRename, onSignOut: onSignOut,
                                       onDeleteAccount: onDeleteAccount)
            }
        }
        .overlay {
            if showsHowTo {
                HowToCut(isMac: Self.isMac) {
                    withAnimation(.easeOut(duration: 0.2)) { showsHowTo = false }
                }
                .transition(.opacity)
            }
        }
        // The widget draws the same window, so it redraws when the colours change.
        .onChange(of: [frame.rawValue, wall.rawValue, fabric.rawValue]) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            Color.kraft.ignoresSafeArea()
            PaperGrain().ignoresSafeArea()
        }
    }

    // MARK: - Pages

    private var main: some View {
        SettingsPage(title: "settings", onBack: onBack) {
            SettingsCard(tilt: -0.4, hasTape: true) {
                Button { page = .window } label: {
                    HStack(alignment: .top, spacing: 16) {
                        WindowPreview(sill: sill)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("your window")
                                .font(Fonts.title())
                                .foregroundStyle(Color.ink)
                            Text("\(frame.name) frame")
                            Text("\(fabric.name) curtains · \(wall.name) wall")
                        }
                        .font(Fonts.small())
                        .foregroundStyle(Color.grey)
                        Spacer(minLength: 0)
                        Text("›")
                            .font(Fonts.body())
                            .foregroundStyle(Color.grey)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 16)
                    .contentShape(.rect)
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint("change the frame, wall and curtains")
            }
            SettingsCard(tilt: 0.3) {
                Button { page = .sill } label: {
                    SettingsRow(title: "your sill", value: friendNames)
                }
                DashedDivider()
                Button { page = .widgets } label: {
                    SettingsRow(title: "widgets")
                }
                DashedDivider()
                Button { withAnimation(.easeOut(duration: 0.2)) { showsHowTo = true } } label: {
                    SettingsRow(title: "how to cut")
                }
                DashedDivider()
                Button { page = .account } label: {
                    SettingsRow(title: "account & privacy")
                }
            }
            SettingsCard(tilt: -0.2) {
                Link(destination: Self.privacyPolicy) {
                    SettingsRow(title: "privacy policy")
                }
                DashedDivider()
                SettingsRow(title: "about", detail: "fonts: Indie Flower, Special Elite, Atkinson Hyperlegible",
                            value: "windowsill \(Self.version)", showsArrow: false)
                    .accessibilityElement(children: .combine)
            }
        }
        .buttonStyle(.plain)
    }

    /// Pick the frame, wall and curtain colours; the preview at the top changes as you pick.
    private var windowPage: some View {
        SettingsPage(title: "your window", onBack: { page = nil }) {
            SettingsCard(tilt: 0.3, hasTape: true) {
                WindowPreview(sill: sill, scale: 0.9)
                    .padding(.vertical, 16)
            }
            SettingsCard(tilt: -0.3) {
                SwatchRow(title: "frame", selection: $frame)
                DashedDivider()
                SwatchRow(title: "curtains", selection: $fabric)
                DashedDivider()
                SwatchRow(title: "wall", selection: $wall)
            }
        }
    }

    private var sillPage: some View {
        SettingsPage(title: "your sill", onBack: { page = nil }) {
            SettingsCard(tilt: 0.35, hasTape: true) {
                ForEach(Array(sill.members.enumerated()), id: \.element.id) { index, member in
                    if index > 0 { DashedDivider() }
                    HStack(spacing: 12) {
                        PotChip(colour: PotStyle.forSill(sill.joinRank(of: member.id)).colour,
                                tilt: index.isMultiple(of: 2) ? -4 : 3)
                        Text(member.name)
                            .font(Fonts.body())
                            .foregroundStyle(Color.ink)
                        Spacer()
                        if member.id == sill.myID {
                            Text("you")
                                .font(Fonts.small())
                                .foregroundStyle(Color.grey)
                        }
                    }
                    .frame(minHeight: 52)
                    .accessibilityElement(children: .combine)
                }
            }
            // A windowsill holds up to six.
            if sill.members.count < 6, let url = sill.inviteURL {
                SettingsCard(tilt: -0.3) {
                    ShareLink(item: url) {
                        SettingsRow(title: "invite someone", detail: "send a seed packet")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var widgetsPage: some View {
        SettingsPage(title: "widgets", onBack: { page = nil }) {
            SettingsCard(tilt: -0.3, hasTape: true) {
                ForEach(Array(Self.widgetSteps.enumerated()), id: \.offset) { index, step in
                    if index > 0 { DashedDivider() }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(index + 1)")
                            .font(Fonts.controlLabel())
                            .foregroundStyle(Color.grey)
                        Text(step)
                            .font(Fonts.body())
                            .foregroundStyle(Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 14)
                    .frame(minHeight: 52)
                }
            }
        }
    }

    // MARK: - Text

    /// Who else is on the sill, by name.
    private var friendNames: String {
        sill.members.filter { $0.id != sill.myID }.map(\.name).formatted(.list(type: .and))
    }

    private static var isMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    #if os(iOS)
    private static let widgetSteps = [
        "touch and hold an empty spot on your home screen",
        "tap edit, then add widget",
        "find windowsill and pick a size",
    ]
    #else
    private static let widgetSteps = [
        "right-click an empty spot on your desktop",
        "choose edit widgets",
        "find windowsill and pick a size",
    ]
    #endif
}

/// Your name, how you signed in, and signing out.
private struct AccountPage: View {
    @State var name: String
    var onBack: () -> Void
    var onRename: (String) -> Void
    var onSignOut: () -> Void
    var onDeleteAccount: () -> Void

    @State private var savedName: String
    @State private var confirmsDelete = false
    @FocusState private var editingName: Bool

    init(name: String, onBack: @escaping () -> Void, onRename: @escaping (String) -> Void,
         onSignOut: @escaping () -> Void, onDeleteAccount: @escaping () -> Void) {
        _name = State(initialValue: name)
        _savedName = State(initialValue: name)
        self.onBack = onBack
        self.onRename = onRename
        self.onSignOut = onSignOut
        self.onDeleteAccount = onDeleteAccount
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        SettingsPage(title: "account & privacy", onBack: {
            save()
            onBack()
        }) {
            SettingsCard(tilt: 0.3, hasTape: true) {
                nameRow
                DashedDivider()
                SettingsRow(title: "signed in with Apple", showsArrow: false)
            }
            SettingsCard(tilt: -0.35) {
                Button(action: onSignOut) {
                    SettingsRow(title: "sign out", showsArrow: false)
                }
                .buttonStyle(.plain)
                DashedDivider()
                Button { withAnimation(.easeOut(duration: 0.2)) { confirmsDelete = true } } label: {
                    SettingsRow(title: "delete account", detail: "your name, flowers and place on the sill",
                                showsArrow: false, isDanger: true)
                }
                .buttonStyle(.plain)
            }
            // Asked on the page itself, on paper, with both choices in plain sight.
            if confirmsDelete {
                SettingsCard(tilt: 0.25, hasTape: true) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("delete your account?")
                            .font(Fonts.title())
                            .foregroundStyle(Color.danger)
                            .accessibilityAddTraits(.isHeader)
                        Text("your name, your flowers and your place on the windowsill are removed for good. apple will ask you to confirm.")
                            .font(Fonts.body())
                            .foregroundStyle(Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 16) {
                            // The safe choice is the dark one that draws the eye.
                            TicketButton("keep it") {
                                withAnimation(.easeOut(duration: 0.2)) { confirmsDelete = false }
                            }
                            TicketButton("delete account", isPrimary: false, action: onDeleteAccount)
                        }
                    }
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .transition(.opacity)
            }
        }
    }

    private var nameRow: some View {
        HStack(spacing: 12) {
            Text("name")
                .font(Fonts.body())
                .foregroundStyle(Color.ink)
            TextField("name", text: $name)
                .font(Fonts.body())
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .submitLabel(.done)
                .focused($editingName)
                .onSubmit(save)
                .onChange(of: name) { _, newValue in
                    // Fits under a pot.
                    if newValue.count > 24 { name = String(newValue.prefix(24)) }
                }
        }
        .frame(minHeight: 52)
        // The whole row is the target, not just the line of text.
        .contentShape(.rect)
        .onTapGesture { editingName = true }
    }

    /// Saves a changed name; an emptied one goes back to what it was.
    private func save() {
        guard !trimmed.isEmpty else {
            name = savedName
            return
        }
        guard trimmed != savedName else { return }
        savedName = trimmed
        onRename(trimmed)
    }
}

// MARK: - Pieces

/// A settings page: a back button and title, then its cards, scrolling.
private struct SettingsPage<Content: View>: View {
    let title: String
    var onBack: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 22) {
                    content
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Button(action: onBack) {
                Text("‹")
                    .font(Fonts.title())
                    .foregroundStyle(Color.ink)
                    // The glyph at x = 20, inside a 44 × 44 hit area.
                    .padding(.leading, 12)
                    .frame(width: 44, height: 44, alignment: .leading)
                    .contentShape(.rect)
            }
            .padding(.leading, 8)
            .buttonStyle(.plain)
            .accessibilityLabel("back")
            Text(title)
                .font(Fonts.title())
                .foregroundStyle(Color.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
        }
        .padding(.top, 8)
    }
}

/// A cream card, laid down a little crooked, sometimes held on with tape.
/// Only the paper tilts; the text on it stays straight and sharp.
private struct SettingsCard<Content: View>: View {
    var tilt: Double = 0
    var hasTape = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.horizontal, 16)
        .background {
            ZStack {
                Rectangle()
                    .fill(PaperShadow.colour(lift: 1))
                    .offset(PaperShadow.offset(lift: 1, unit: 2.5))
                Rectangle().fill(Color.cream)
            }
            .rotationEffect(.degrees(tilt))
        }
        .overlay(alignment: .top) {
            if hasTape {
                Rectangle()
                    .fill(Color.tape)
                    .frame(width: 54, height: 16)
                    .rotationEffect(.degrees(-3))
                    .offset(x: 40, y: -9)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// One line on a card: a title (and an optional line under it), a grey value, and "›"
/// when it opens another page.
private struct SettingsRow: View {
    let title: String
    var detail: String?
    var value: String?
    var showsArrow = true
    /// Something that can't be undone, like deleting the account.
    var isDanger = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Fonts.body())
                    .foregroundStyle(isDanger ? Color.danger : Color.ink)
                if let detail {
                    Text(detail)
                        .font(Fonts.small())
                        .foregroundStyle(Color.grey)
                }
            }
            Spacer(minLength: 12)
            if let value {
                Text(value)
                    .font(Fonts.body())
                    .foregroundStyle(Color.grey)
                    .lineLimit(1)
            }
            if showsArrow {
                Text("›")
                    .font(Fonts.body())
                    .foregroundStyle(Color.grey)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 12)
        .frame(minHeight: 60)
        .contentShape(.rect)
    }
}

/// One part of the window (frame, curtains, wall) and its colours as paper swatches.
/// The chosen one has an ink edge and a strip of tape.
private struct SwatchRow<Choice: WindowColour>: View {
    let title: String
    @Binding var selection: Choice

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(Fonts.controlLabel())
                    .foregroundStyle(Color.grey)
                Spacer()
                Text(selection.name)
                    .font(Fonts.small())
                    .foregroundStyle(Color.grey)
            }
            .accessibilityHidden(true)
            HStack(spacing: 10) {
                ForEach(Choice.allCases, id: \.self) { choice in
                    let isChosen = choice == selection
                    Button { selection = choice } label: {
                        Rectangle()
                            .fill(choice.colour)
                            .overlay { Rectangle().strokeBorder(Color.ink, lineWidth: isChosen ? 2 : 0.5) }
                            .frame(width: 44, height: 44)
                            .background {
                                Rectangle().fill(PaperShadow.colour(lift: 0.8))
                                    .offset(PaperShadow.offset(lift: 0.8, unit: 2.5))
                            }
                            .overlay(alignment: .top) {
                                if isChosen {
                                    Rectangle().fill(Color.tape.opacity(0.9))
                                        .frame(width: 26, height: 9)
                                        .rotationEffect(.degrees(-6))
                                        .offset(y: -5)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(choice.name) \(title)")
                    .accessibilityAddTraits(isChosen ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 14)
    }
}

/// The dashed line between rows.
private struct DashedDivider: View {
    var body: some View {
        Line()
            .stroke(Color.grey.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}

/// A small scrap of a friend's pot paper, next to their name.
private struct PotChip: View {
    let colour: Color
    let tilt: Double

    var body: some View {
        Rectangle()
            .fill(colour)
            .overlay { Rectangle().stroke(Color.ink.opacity(0.3), lineWidth: 0.75) }
            .frame(width: 20, height: 15)
            .background {
                Rectangle()
                    .fill(PaperShadow.colour(lift: 0.6))
                    .offset(PaperShadow.offset(lift: 0.6, unit: 2.5))
            }
            .rotationEffect(.degrees(tilt))
            .accessibilityHidden(true)
    }
}

/// Your window, live and small: the full-size scene drawn, then scaled down.
private struct WindowPreview: View {
    let sill: Sill
    var scale: CGFloat = 0.44

    private static let drawnWidth: CGFloat = 300

    var body: some View {
        // Small enough that everyone fits across the window.
        let plantSize = min(64, 250 / CGFloat(max(sill.petals.count, 1)) - 12)
        let drawnHeight = plantSize * 2.6 + 26 + 40
        SillView(sill: sill, plantSize: plantSize)
            .frame(width: Self.drawnWidth, height: drawnHeight, alignment: .bottom)
            .background { WallFill() }
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: Self.drawnWidth * scale, height: drawnHeight * scale, alignment: .topLeading)
            .clipShape(.rect(cornerRadius: 3))
            .background {
                RoundedRectangle(cornerRadius: 3)
                    .fill(PaperShadow.colour(lift: 0.8))
                    .offset(PaperShadow.offset(lift: 0.8, unit: 2.5))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#Preview {
    SettingsView(sill: .preview, onBack: {}, onRename: { _ in }, onSignOut: {}, onDeleteAccount: {})
}
