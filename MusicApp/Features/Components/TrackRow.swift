import SwiftUI

/// A list row for a track: artwork, title, subtitle, badges and download/favorite state.
struct TrackRow: View {
    let track: PlayableTrack
    var showsSource = true
    var showsArtwork = true

    @Environment(PlayerManager.self) private var player
    @Environment(DownloadManager.self) private var downloads
    @Environment(TrackActions.self) private var actions

    var body: some View {
        HStack(spacing: 12) {
            if showsArtwork {
                ArtworkView(track: track, size: 48, cornerRadius: 6)
                    .overlay(alignment: .bottomTrailing) {
                        if isCurrent {
                            Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(3)
                                .background(Color.accentColor, in: Circle())
                                .offset(x: 4, y: 4)
                        }
                    }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.body)
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if showsSource {
                        SourceBadge(source: track.source, isPreview: track.isPreview)
                    }
                    if let license = track.license, !track.isPreview {
                        LicenseBadge(license: license)
                    }
                    Text(track.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            trailing
        }
        .contentShape(Rectangle())
    }

    private var isCurrent: Bool {
        player.currentTrack?.id == track.id
    }

    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: 6) {
            if actions.isFavorite(track) {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.pink)
                    .accessibilityLabel("已收藏")
            }
            switch downloads.status(for: track) {
            case .downloading(let fraction):
                ProgressView(value: fraction)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            case .downloaded:
                Image(systemName: "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("已下载")
            case .failed:
                Image(systemName: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("下载失败")
            case .notDownloaded:
                EmptyView()
            }
            if let duration = TimeFormatting.clock(track.isPreview ? nil : track.duration) {
                Text(duration)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A row for an Internet Archive item (album).
struct CollectionRow: View {
    let collection: RemoteCollection

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(collection: collection, size: 48, cornerRadius: 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(collection.title)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    SourceBadge(source: collection.source)
                    if let license = collection.license {
                        LicenseBadge(license: license)
                    }
                    Text([collection.subtitle, collection.year].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "square.stack")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
