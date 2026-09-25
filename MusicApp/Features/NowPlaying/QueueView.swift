import SwiftUI

struct QueueView: View {
    @Environment(PlayerManager.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let current = player.queue.current {
                    Section("正在播放") {
                        TrackRow(track: current.track)
                    }
                }

                Section {
                    HStack(spacing: 12) {
                        Button {
                            player.toggleShuffle()
                        } label: {
                            Label("随机", systemImage: "shuffle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(player.isShuffled ? Color.accentColor : Color.secondary)
                        Button {
                            player.cycleRepeatMode()
                        } label: {
                            Label(player.repeatMode.title, systemImage: player.repeatMode.systemImage)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(player.repeatMode == .off ? Color.secondary : Color.accentColor)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    let upNext = player.queue.upNext
                    if upNext.isEmpty {
                        Text(player.repeatMode == .all ? "列表循环：播完后从头开始" : "播放队列里没有更多歌曲")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(upNext.enumerated()), id: \.element.id) { index, entry in
                        Button {
                            player.jump(toUpNext: index)
                        } label: {
                            TrackRow(track: entry.track)
                        }
                        .buttonStyle(.plain)
                    }
                    .onMove { source, destination in
                        player.moveUpNext(from: source, to: destination)
                    }
                    .onDelete { offsets in
                        player.removeUpNext(at: offsets)
                    }
                } header: {
                    HStack {
                        Text("接下来播放")
                        Spacer()
                        if !player.queue.upNext.isEmpty {
                            Button("清空") { player.clearUpNext() }
                                .font(.caption)
                                .textCase(nil)
                        }
                    }
                }

                let history = player.queue.history
                if !history.isEmpty {
                    Section("播放过的") {
                        ForEach(history) { entry in
                            Button {
                                player.jump(toEntryID: entry.id)
                            } label: {
                                TrackRow(track: entry.track)
                                    .opacity(0.6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("播放队列")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
