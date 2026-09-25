import AVKit
import SwiftUI

/// Full-screen player: artwork and lyrics pages, progress, controls, queue.
struct NowPlayingView: View {
    @Environment(PlayerManager.self) private var player
    @Environment(LyricsService.self) private var lyrics
    @Environment(TrackActions.self) private var actions
    @Environment(\.dismiss) private var dismiss

    @State private var page = Page.artwork
    @State private var showQueue = false

    enum Page: Hashable {
        case artwork
        case lyrics
    }

    var body: some View {
        Group {
            if let track = player.currentTrack {
                content(track)
                    .task(id: track.id) {
                        await lyrics.load(for: track)
                    }
            } else {
                ContentUnavailableView("没有正在播放的歌曲", systemImage: "music.note")
            }
        }
        .background { background }
        .sheet(isPresented: $showQueue) {
            QueueView()
        }
        .trackActionSheets(enabled: true)
        .onAppear { actions.isNowPlayingPresented = true }
        .onDisappear { actions.isNowPlayingPresented = false }
    }

    private func content(_ track: PlayableTrack) -> some View {
        VStack(spacing: 0) {
            header(track)

            TabView(selection: $page) {
                artworkPage(track)
                    .tag(Page.artwork)
                LyricsView(track: track)
                    .tag(Page.lyrics)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack(spacing: 18) {
                titleRow(track)
                if track.isPreview {
                    Label("iTunes 30 秒试听片段", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ProgressSliderView()
                PlaybackControlsView()
                bottomBar
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }

    private func header(_ track: PlayableTrack) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("收起")
            Spacer()
            VStack(spacing: 2) {
                Text("正在播放")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    SourceBadge(source: track.source, isPreview: track.isPreview)
                    if let license = track.license, !track.isPreview {
                        LicenseBadge(license: license)
                    }
                }
            }
            Spacer()
            Menu {
                TrackMenuItems(track: track)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("更多")
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private func artworkPage(_ track: PlayableTrack) -> some View {
        ArtworkView(track: track, cornerRadius: 16)
            .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
            .scaleEffect(player.isPlaying ? 1 : 0.88)
            .animation(.spring(response: 0.45, dampingFraction: 0.75), value: player.isPlaying)
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation { page = .lyrics }
            }
    }

    private func titleRow(_ track: PlayableTrack) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.title3.bold())
                    .lineLimit(1)
                Text(track.album.map { "\(track.artist) — \($0)" } ?? track.artist)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                actions.toggleFavorite(track)
            } label: {
                Image(systemName: actions.isFavorite(track) ? "heart.fill" : "heart")
                    .font(.title2)
                    .foregroundStyle(actions.isFavorite(track) ? Color.pink : Color.primary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(actions.isFavorite(track) ? "取消收藏" : "收藏")
        }
    }

    private var bottomBar: some View {
        HStack {
            Button {
                withAnimation { page = page == .lyrics ? .artwork : .lyrics }
            } label: {
                Image(systemName: "quote.bubble")
                    .font(.title3)
                    .foregroundStyle(page == .lyrics ? Color.accentColor : Color.secondary)
            }
            .accessibilityLabel(page == .lyrics ? "显示封面" : "显示歌词")
            Spacer()
            RoutePickerView()
                .frame(width: 32, height: 32)
                .accessibilityLabel("隔空播放")
            Spacer()
            Button {
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("播放队列")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private var background: some View {
        ZStack {
            Color(.systemBackground)
            if let track = player.currentTrack {
                ArtworkView(track: track, cornerRadius: 0)
                    .scaledToFill()
                    .blur(radius: 60)
                    .opacity(0.45)
                    .clipped()
            }
            LinearGradient(
                colors: [Color(.systemBackground).opacity(0.1), Color(.systemBackground).opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

/// AirPlay / Bluetooth output picker.
struct RoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .secondaryLabel
        view.activeTintColor = .tintColor
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
