import SwiftData
import SwiftUI

struct PlaylistsView: View {
    @Query(sort: \Playlist.updatedAt, order: .reverse) private var playlists: [Playlist]
    @Environment(LibraryStore.self) private var library

    @State private var showCreate = false
    @State private var newName = ""
    @State private var renaming: Playlist?
    @State private var renameText = ""

    var body: some View {
        List {
            Section {
                Button {
                    newName = ""
                    showCreate = true
                } label: {
                    Label("新建歌单", systemImage: "plus.rectangle.on.rectangle")
                }
            }
            if !playlists.isEmpty {
                Section {
                    ForEach(playlists) { playlist in
                        NavigationLink(value: playlist) {
                            PlaylistRow(playlist: playlist)
                        }
                        .contextMenu {
                            Button {
                                renameText = playlist.name
                                renaming = playlist
                            } label: {
                                Label("重命名", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                library.delete(playlist)
                            } label: {
                                Label("删除歌单", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            library.delete(playlists[index])
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("歌单")
        .overlay {
            if playlists.isEmpty {
                ContentUnavailableView("还没有歌单", systemImage: "music.note.list",
                                       description: Text("新建一个歌单，把喜欢的歌放进去。"))
                    .allowsHitTesting(false)
                    .padding(.top, 120)
            }
        }
        .alert("新建歌单", isPresented: $showCreate) {
            TextField("歌单名称", text: $newName)
            Button("取消", role: .cancel) {}
            Button("创建") {
                library.createPlaylist(name: newName)
            }
        }
        .alert("重命名歌单", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("歌单名称", text: $renameText)
            Button("取消", role: .cancel) { renaming = nil }
            Button("保存") {
                if let renaming {
                    library.rename(renaming, to: renameText)
                }
                renaming = nil
            }
        }
    }
}

struct PlaylistRow: View {
    let playlist: Playlist

    var body: some View {
        HStack(spacing: 12) {
            if let cover = playlist.coverTrack {
                ArtworkView(track: cover, size: 52, cornerRadius: 6)
            } else {
                ArtworkView(url: nil, size: 52, cornerRadius: 6, seed: playlist.name)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name)
                    .lineLimit(1)
                Text("\(playlist.entries.count) 首")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
