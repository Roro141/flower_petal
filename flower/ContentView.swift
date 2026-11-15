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
    /// Refreshes run one at a time. One asked for while another is running (e.g. an
    /// invite link arriving during launch) runs straight after it instead.
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
        VStack(spacing: 32) {
            HStack {
                Spacer()
                if let url = sill?.inviteURL {
                    ShareLink(item: url) {
                        Text("invite")
                            .font(Fonts.button())
                            .foregroundStyle(Color.ink)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                }
            }
            .padding(.horizontal)
            Spacer()
            if let sill {
                // Redrawn every minute so a flower wilts on screen when its time comes.
                TimelineView(.everyMinute) { context in
                    SillView(sill: sill, plantSize: 80, now: context.date)
                }
            }
            TicketButton("cut") { isCutting = true }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.wall)
        .fullScreenCover(isPresented: $isCutting) {
            CutView(owner: sill?.myID ?? "", paper: .dots, onBack: { isCutting = false }, onPlant: { petal in
                isCutting = false
                plant(petal)
            })
        }
    }

    // MARK: - Steps

    /// Works out where we are from the server: signed in? named? on a windowsill?
    /// Joins a pending invite on the way if there is one.
    private func refresh(suggestedName: String = "") async {
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
            sill = try await PetalService.fetchSill(current)
            update()
            stage = sill == nil ? .needsWindowsill : .window
        } catch {
            // Offline or a server hiccup: stay on whatever we were showing.
            PetalService.log.error("refresh failed: \(error.localizedDescription, privacy: .public)")
            if case .loading = stage { stage = sill == nil ? .signedOut : .window }
        }
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
        current.petals[index] = petal
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
