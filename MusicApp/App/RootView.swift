import SwiftUI

enum AppTab: Hashable {
    case search
    case library
    case settings
}

struct RootView: View {
    @Environment(PlayerManager.self) private var player
    @Environment(TrackActions.self) private var actions

    @State private var selectedTab = AppTab.search
    @State private var showNowPlaying = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                SearchView()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { miniPlayer }
            .tabItem { Label("搜索", systemImage: "magnifyingglass") }
            .tag(AppTab.search)

            NavigationStack {
                LibraryView()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { miniPlayer }
            .tabItem { Label("曲库", systemImage: "music.note.house") }
            .tag(AppTab.library)

            NavigationStack {
                SettingsView()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { miniPlayer }
            .tabItem { Label("设置", systemImage: "gearshape") }
            .tag(AppTab.settings)
        }
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingView()
                .presentationDragIndicator(.visible)
        }
        .trackActionSheets(enabled: !actions.isNowPlayingPresented)
        .overlay(alignment: .top) {
            ToastView(message: actions.toast)
        }
        .onChange(of: player.errorMessage) { _, message in
            if let message {
                actions.showToast(message)
            }
        }
    }

    private var miniPlayer: some View {
        MiniPlayerView { showNowPlaying = true }
    }
}

/// Presents the "add to playlist" and "track info" sheets from whichever screen is on top.
struct TrackActionSheets: ViewModifier {
    let enabled: Bool
    @Environment(TrackActions.self) private var actions

    func body(content: Content) -> some View {
        @Bindable var actions = actions
        return content
            .sheet(item: enabled ? $actions.playlistPicker : .constant(nil)) { selection in
                PlaylistPickerSheet(tracks: selection.tracks)
            }
            .sheet(item: enabled ? $actions.infoTrack : .constant(nil)) { track in
                TrackInfoSheet(track: track)
            }
    }
}

extension View {
    func trackActionSheets(enabled: Bool) -> some View {
        modifier(TrackActionSheets(enabled: enabled))
    }
}

struct ToastView: View {
    let message: String?

    var body: some View {
        Group {
            if let message {
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: message)
        .allowsHitTesting(false)
    }
}
