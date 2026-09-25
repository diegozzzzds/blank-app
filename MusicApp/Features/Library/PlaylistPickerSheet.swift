import SwiftData
import SwiftUI

/// "Add to playlist" sheet.
struct PlaylistPickerSheet: View {
    let tracks: [PlayableTrack]

    @Query(sort: \Playlist.updatedAt, order: .reverse) private var playlists: [Playlist]
    @Environment(LibraryStore.self) private var library
    @Environment(TrackActions.self) private var actions
    @Environment(\.dismiss) private var dismiss

    @State private var showCreate = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        newName = ""
                        showCreate = true
                    } label: {
                        Label("新建歌单…", systemImage: "plus")
                    }
                }
                Section {
                    ForEach(playlists) { playlist in
                        Button {
                            add(to: playlist)
                        } label: {
                            PlaylistRow(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(tracks.count == 1 ? "添加到歌单" : "添加 \(tracks.count) 首到歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .alert("新建歌单", isPresented: $showCreate) {
                TextField("歌单名称", text: $newName)
                Button("取消", role: .cancel) {}
                Button("创建并添加") {
                    add(to: library.createPlaylist(name: newName))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func add(to playlist: Playlist) {
        library.add(tracks, to: playlist)
        actions.showToast("已添加到「\(playlist.name)」")
        dismiss()
    }
}
