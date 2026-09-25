import SwiftData
import SwiftUI

struct PlaylistDetailView: View {
    @Bindable var playlist: Playlist
    @Environment(LibraryStore.self) private var library
    @Environment(TrackActions.self) private var actions
    @Environment(\.dismiss) private var dismiss

    @State private var renameText = ""
    @State private var showRename = false
    @State private var confirmDelete = false

    var body: some View {
        let entries = playlist.orderedEntries
        let list = entries.compactMap { $0.track?.playable }
        List {
            Section {
                VStack(spacing: 12) {
                    if let cover = playlist.coverTrack {
                        ArtworkView(track: cover, size: 160, cornerRadius: 12)
                    } else {
                        ArtworkView(url: nil, size: 160, cornerRadius: 12, seed: playlist.name)
                    }
                    Text(playlist.name)
                        .font(.title3.bold())
                    Text("\(list.count) 首 · 更新于 \(playlist.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                PlayShuffleButtons(tracks: list)
            }

            Section {
                if entries.isEmpty {
                    Text("歌单是空的。在搜索结果或曲库中长按歌曲，选择「添加到歌单」。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    if let track = entry.track?.playable {
                        Button {
                            actions.play(track, in: list)
                        } label: {
                            TrackRow(track: track)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            TrackMenuItems(track: track, list: list)
                        }
                    }
                }
                .onMove { source, destination in
                    library.moveEntries(in: playlist, from: source, to: destination)
                }
                .onDelete { offsets in
                    library.removeEntries(at: offsets, from: playlist)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                EditButton()
                Menu {
                    Button {
                        actions.addToQueue(list)
                    } label: {
                        Label("全部加入播放队列", systemImage: "text.append")
                    }
                    Button {
                        actions.download(list)
                    } label: {
                        Label("下载全部", systemImage: "arrow.down.circle")
                    }
                    Button {
                        renameText = playlist.name
                        showRename = true
                    } label: {
                        Label("重命名", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("删除歌单", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("重命名歌单", isPresented: $showRename) {
            TextField("歌单名称", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("保存") { library.rename(playlist, to: renameText) }
        }
        .confirmationDialog("删除歌单「\(playlist.name)」？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                dismiss()
                library.delete(playlist)
            }
        } message: {
            Text("歌单里的歌曲仍会保留在曲库中。")
        }
    }
}
