import SwiftData
import SwiftUI

enum LibraryDestination: Hashable {
    case playlists
    case songs
    case favorites
    case local
    case downloaded
}

struct LibraryView: View {
    @Query(sort: \Track.dateAdded, order: .reverse) private var tracks: [Track]
    @Query private var playlists: [Playlist]
    @Environment(TrackActions.self) private var actions

    var body: some View {
        List {
            Section {
                link(.playlists, "歌单", "music.note.list", .pink, count: playlists.count)
                link(.songs, "歌曲", "music.note", .red, count: tracks.count)
                link(.favorites, "收藏", "heart.fill", .pink, count: tracks.filter(\.isFavorite).count)
                link(.local, "本地音乐", "folder.fill", .green, count: tracks.filter { $0.source == .local }.count)
                link(.downloaded, "已下载", "arrow.down.circle.fill", .blue,
                     count: tracks.filter { $0.localFilename != nil && $0.source != .local }.count)
            }

            let recent = Array(tracks.prefix(12))
            if !recent.isEmpty {
                Section("最近添加") {
                    let list = recent.map(\.playable)
                    ForEach(list) { track in
                        Button {
                            actions.play(track, in: list)
                        } label: {
                            TrackRow(track: track)
                        }
                        .buttonStyle(.plain)
                        .trackMenu(track, in: list)
                    }
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("曲库还是空的").font(.headline)
                        Text("在搜索结果上长按或左右滑动，可以收藏、加入歌单或下载；也可以在「本地音乐」里导入手机上的音乐文件。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("曲库")
        .navigationDestination(for: LibraryDestination.self) { destination in
            switch destination {
            case .playlists: PlaylistsView()
            case .songs: SongsListView()
            case .favorites: FavoritesView()
            case .local: LocalMusicView()
            case .downloaded: DownloadedView()
            }
        }
        .navigationDestination(for: Playlist.self) { playlist in
            PlaylistDetailView(playlist: playlist)
        }
    }

    private func link(_ destination: LibraryDestination, _ title: String, _ icon: String, _ color: Color, count: Int) -> some View {
        NavigationLink(value: destination) {
            HStack {
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: icon).foregroundStyle(color)
                }
                Spacer()
                Text("\(count)")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A plain list of stored tracks with play-all / shuffle header, search and delete.
struct TrackListView: View {
    let title: String
    let tracks: [Track]
    var emptyTitle = "没有歌曲"
    var emptyMessage = ""
    var emptySystemImage = "music.note"
    var deleteLabel = "从曲库删除"
    var onDelete: ((Track) -> Void)?

    @Environment(TrackActions.self) private var actions
    @State private var searchText = ""

    var body: some View {
        let filtered = filter(tracks)
        let list = filtered.map(\.playable)
        Group {
            if tracks.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: emptySystemImage, description: Text(emptyMessage))
            } else {
                List {
                    Section {
                        PlayShuffleButtons(tracks: list)
                    }
                    Section {
                        ForEach(filtered) { stored in
                            let track = stored.playable
                            Button {
                                actions.play(track, in: list)
                            } label: {
                                TrackRow(track: track)
                            }
                            .buttonStyle(.plain)
                            .trackMenu(track, in: list)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    if let onDelete {
                                        onDelete(stored)
                                    } else {
                                        actions.delete(stored)
                                    }
                                } label: {
                                    Label(deleteLabel, systemImage: "trash")
                                }
                            }
                        }
                    } footer: {
                        Text("\(filtered.count) 首歌曲")
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $searchText, prompt: "在\(title)中搜索")
            }
        }
        .navigationTitle(title)
    }

    private func filter(_ tracks: [Track]) -> [Track] {
        let term = searchText.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return tracks }
        return tracks.filter {
            $0.title.localizedStandardContains(term)
                || $0.artist.localizedStandardContains(term)
                || ($0.album ?? "").localizedStandardContains(term)
        }
    }
}

struct PlayShuffleButtons: View {
    let tracks: [PlayableTrack]
    @Environment(TrackActions.self) private var actions

    var body: some View {
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
                Label("随机播放", systemImage: "shuffle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .disabled(tracks.isEmpty)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }
}
