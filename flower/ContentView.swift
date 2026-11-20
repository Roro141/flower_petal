import SwiftUI
import WidgetKit
import os

/// Decides what to show: sign in → pick a name → start or join a windowsill → the window.
/// Opens straight onto the last known window while it checks for updates.
struct ContentView: View {
    private enum Stage {
        case loading
        case signedOut
        case naming(suggested: String)
        case needsWindowsill
        case window
    }

    @State private var stage: Stage = FlowerStore.load() == nil ? .loading : .window
    @State private var session: Session?
    @State private var sill = FlowerStore.load()
    /// An invite link opened before we were ready to join (signed out, or no name yet).
    @State private var pendingInvite: String?
    @State private var isCutting = false
    @State private var isShowingSettings = false
    /// Refreshes run one at a time. One asked for while another is running (e.g. an
    /// invite link arriving during launch) runs straight after it instead.
    /// Bumped to play a gust in the window; see `SillView`.
    @State private var gustPlays = 0
    @State private var gustSpeed = 1.0
    @Environment(\.scenePhase) private var scenePhase
    @State private var isRefreshing = false
    @State private var needsAnotherRefresh = false

    var body: some View {
        Group {
            switch stage {
            case .loading:
                Color.wall.ignoresSafeArea()
            case .signedOut:
                SignInView { newSession, givenName in
                    session = newSession
                    Task { await refresh(suggestedName: givenName ?? "") }
                }
            case .naming(let suggested):
                NameView(name: suggested) { name in
                    Task { await saveName(name) }
                }
            case .needsWindowsill:
                StartWindowsillView {
                    Task { await startWindowsill() }
                }
            case .window:
                window
            }
        }
        .task { await refresh() }
        .onOpenURL { url in
            // windowsill://join/<code>
            guard url.scheme == "windowsill", url.host() == "join", let code = url.pathComponents.last,
                  code != "/" else { return }
            pendingInvite = code
            Task { await refresh() }
        }
    }

    private var window: some View {
        VStack(spacing: 0) {
            HStack {
                if sill != nil {
                    Button { isShowingSettings = true } label: {
                        TapeLabel(text: "settings", tilt: -3)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if let url = sill?.inviteURL {
                    ShareLink(item: url) {
                        TapeLabel(text: "invite", tilt: 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            Spacer()
            if let sill {
                // Redrawn every minute so a flower wilts on screen when its time comes.
                TimelineView(.everyMinute) { context in
                    SillView(sill: sill, plantSize: 96, now: context.date, gustPlays: gustPlays, gustSpeed: gustSpeed)
                }
            }
            Spacer()
            TicketButton("cut") { isCutting = true }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // The wall, with the same grain as the window (which has its own).
            WallFill().ignoresSafeArea()
            PaperGrain().ignoresSafeArea()
        }
        // Check for friends' petals and gusts while the window is open, and on coming back to it.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await refresh()
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await refresh() } }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $isShowingSettings) {
            if let sill { settings(sill) }
        }
        .fullScreenCover(isPresented: $isCutting) {
            CutView(owner: sill?.myID ?? "", paper: .dots, onBack: { isCutting = false }, onPlant: { petal in
                isCutting = false
                plant(petal)
            })
        }
        #else
        .sheet(isPresented: $isShowingSettings) {
            if let sill {
                settings(sill)
                    .frame(minWidth: 420, minHeight: 640)
            }
        }
        // On the Mac, cutting is point-and-click in its own window-sized sheet.
        .sheet(isPresented: $isCutting) {
            MacCutView(owner: sill?.myID ?? "", onCancel: { isCutting = false }, onPlant: { petal in
                isCutting = false
                plant(petal)
            })
        }
        #endif
    }

    private func settings(_ sill: Sill) -> some View {
        SettingsView(sill: sill, onBack: { isShowingSettings = false }, onRename: { name in
            Task { await saveName(name) }
        }, onSignOut: {
            isShowingSettings = false
            Auth.signOut()
            // Finds nobody signed in: clears the sill and the widget, and shows sign-in.
            Task { await refresh() }
        }, onDeleteAccount: {
            Task { await deleteAccount() }
        })
    }

    /// Confirms with Apple once more (so the server can cancel Sign in with Apple), deletes
    /// everything on the server, then signs out here. If anything fails, nothing changes
    /// and you can try again.
    private func deleteAccount() async {
        guard let code = await AppleReauth.authorizationCode() else { return }
        do {
            guard let current = try await Auth.currentSession() else { return }
            try await PetalService.deleteAccount(current, appleAuthorizationCode: code)
        } catch {
            PetalService.log.error("delete account failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        isShowingSettings = false
        Auth.signOut()
        await refresh()
    }

    // MARK: - Steps

    /// Works out where we are from the server: signed in? named? on a windowsill?
    /// Joins a pending invite on the way if there is one.
    private func refresh(suggestedName: String = "") async {
        #if DEBUG
        // Launched with -walkthrough (simulator UI checks): a sample windowsill, no
        // sign-in and no network. With no session, planting does nothing.
        if CommandLine.arguments.contains("-walkthrough") {
            sill = .preview
            stage = .window
            return
        }
        #endif
        if isRefreshing {
            needsAnotherRefresh = true
            return
        }
        isRefreshing = true
        repeat {
            needsAnotherRefresh = false
            await refreshOnce(suggestedName: suggestedName)
        } while needsAnotherRefresh
        isRefreshing = false
    }

    private func refreshOnce(suggestedName: String) async {
        do {
            guard let current = try await Auth.currentSession() else {
                session = nil
                sill = nil
                update()
                stage = .signedOut
                return
            }
            session = current
            guard try await PetalService.myName(current) != nil else {
                stage = .naming(suggested: suggestedName)
                return
            }
            if let code = pendingInvite {
                pendingInvite = nil
                try await PetalService.joinGroup(code: code, current)
            }
            let fetched = try await PetalService.fetchSill(current)
            // Only touch the widget when something changed (this runs every minute).
            if fetched != sill {
                sill = fetched
                update()
            }
            stage = sill == nil ? .needsWindowsill : .window
            playNewGust()
            // The widget may have made its push token before anyone signed in.
            await PushTokens.uploadCurrent()
        } catch {
            // Offline or a server hiccup: stay on whatever we were showing.
            PetalService.log.error("refresh failed: \(error.localizedDescription, privacy: .public)")
            if case .loading = stage { stage = sill == nil ? .signedOut : .window }
        }
    }

    /// Plays the last gust if this phone hasn't shown it yet: at full speed if it just
    /// blew, otherwise once, compressed, as a catch-up.
    private func playNewGust() {
        guard let speed = Gust.playbackSpeed(for: sill?.gust, seenKey: "lastPlayedGust") else { return }
        gustSpeed = speed
        gustPlays += 1
    }

    private func saveName(_ name: String) async {
        guard let session else { return }
        do {
            try await PetalService.saveName(name, session)
        } catch {
            PetalService.log.error("save name failed: \(error.localizedDescription, privacy: .public)")
        }
        await refresh()
    }

    private func startWindowsill() async {
        guard let session else { return }
        do {
            try await PetalService.createGroup(session)
        } catch {
            PetalService.log.error("create windowsill failed: \(error.localizedDescription, privacy: .public)")
        }
        await refresh()
    }

    /// Puts my new petal on the sill straight away, saves it to Supabase, then
    /// redraws this phone's widget with the saved copy (which has its real id).
    private func plant(_ petal: Petal) {
        guard let session, var current = sill,
              let index = current.petals.firstIndex(where: { $0.owner == petal.owner }) else { return }
        // Planted now: earlier gusts no longer count against it, so its fallen petals
        // are swept straight away instead of after the server replies.
        var planted = petal
        planted.createdAt = .now
        current.petals[index] = planted
        sill = current
        Task {
            do {
                let stored = try await PetalService.plant(petal, groupID: current.groupID, session)
                sill?.petals[index] = stored
                update()
            } catch {
                PetalService.log.error("plant failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Saves the sill for the widget, redraws its images, and asks it to reload.
    private func update() {
        FlowerStore.save(sill)
        FlowerRenderer.render(sill, onlyMissing: false)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

#Preview {
    ContentView()
}
