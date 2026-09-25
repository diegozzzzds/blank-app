import SwiftUI

/// The bar above the tab bar. Tapping it opens Now Playing.
struct MiniPlayerView: View {
    var onTap: () -> Void

    @Environment(PlayerManager.self) private var player

    var body: some View {
        if let track = player.currentTrack {
            HStack(spacing: 12) {
                ArtworkView(track: track, size: 44, cornerRadius: 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if track.isPreview {
                            SourceBadge(source: track.source, isPreview: true)
                        }
                        Text(track.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(player.isPlaying ? "暂停" : "播放")
                Button {
                    player.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                }
                .disabled(!player.queue.hasNext)
                .accessibilityLabel("下一首")
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .bottom) {
                MiniProgressLine()
                    .padding(.horizontal, 14)
            }
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("打开正在播放")
        }
    }
}

/// Separate view so only this line re-renders on every time tick.
private struct MiniProgressLine: View {
    @Environment(PlayerManager.self) private var player

    var body: some View {
        GeometryReader { proxy in
            let fraction = player.duration > 0 ? min(max(player.currentTime / player.duration, 0), 1) : 0
            Capsule()
                .fill(Color.accentColor)
                .frame(width: proxy.size.width * fraction, height: 2)
        }
        .frame(height: 2)
    }
}
