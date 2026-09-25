import SwiftUI

/// An Internet Archive item (album): loads its tracks on demand.
struct CollectionDetailView: View {
    let collection: RemoteCollection

    @Environment(SourceRegistry.self) private var registry
    @Environment(TrackActions.self) private var actions

    @State private var tracks: [PlayableTrack] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }

            Section {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("正在读取曲目…").foregroundStyle(.secondary)
                    }
                } else if let errorMessage {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                        Button("重试") { Task { await load() } }
                            .buttonStyle(.borderless)
                    }
                } else if tracks.isEmpty {
                    Text("这个条目里没有可以播放的 MP3 文件")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        Button {
                            actions.play(track, in: tracks)
                        } label: {
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 22)
                                TrackRow(track: track, showsSource: false, showsArtwork: false)
                            }
                        }
                        .buttonStyle(.plain)
                        .trackMenu(track, in: tracks)
                    }
                }
            } header: {
                if !tracks.isEmpty {
                    Text("\(tracks.count) 首")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(collection.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let page = collection.webPageURL {
                ToolbarItem(placement: .topBarTrailing) {
                    Link(destination: page) {
                        Image(systemName: "safari")
                    }
                    .accessibilityLabel("在 Internet Archive 打开")
                }
            }
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(spacing: 14) {
            ArtworkView(collection: collection, size: 180, cornerRadius: 12)
                .shadow(radius: 8, y: 4)
            VStack(spacing: 4) {
                Text(collection.title)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                if let subtitle = collection.subtitle {
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    SourceBadge(source: collection.source)
                    if let license = collection.license {
                        LicenseBadge(license: license)
                    }
                    if let year = collection.year {
                        Text(year).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            HStack(spacing: 12) {
                Button {
                    actions.playAll(tracks)
                } label: {
                    Label("播放", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    actions.playAll(tracks, shuffle: true)
                } label: {
                    Label("随机", systemImage: "shuffle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Menu {
                    Button {
                        actions.addToPlaylist(tracks)
                    } label: {
                        Label("全部加入歌单…", systemImage: "text.badge.plus")
                    }
                    Button {
                        actions.addToQueue(tracks)
                    } label: {
                        Label("全部加入播放队列", systemImage: "text.append")
                    }
                    Button {
                        actions.download(tracks)
                    } label: {
                        Label("全部下载", systemImage: "arrow.down.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.bordered)
            }
            .disabled(tracks.isEmpty)
        }
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        guard let source = registry.source(for: collection.source) else {
            errorMessage = "来源不可用"
            return
        }
        do {
            tracks = try await source.tracks(in: collection)
        } catch {
            let wrapped = MusicSourceError.wrap(error)
            if wrapped != .cancelled {
                errorMessage = wrapped.errorDescription
            }
        }
    }
}
