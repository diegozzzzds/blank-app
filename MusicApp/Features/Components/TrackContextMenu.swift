import SwiftUI

/// Context menu and swipe actions shared by every track list.
struct TrackMenuModifier: ViewModifier {
    let track: PlayableTrack
    let list: [PlayableTrack]

    @Environment(TrackActions.self) private var actions

    func body(content: Content) -> some View {
        content
            .contextMenu {
                TrackMenuItems(track: track, list: list)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    actions.playNext([track])
                } label: {
                    Label("下一首播放", systemImage: "text.insert")
                }
                .tint(.indigo)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    actions.toggleFavorite(track)
                } label: {
                    Label(actions.isFavorite(track) ? "取消收藏" : "收藏",
                          systemImage: actions.isFavorite(track) ? "heart.slash" : "heart")
                }
                .tint(.pink)
                Button {
                    actions.addToPlaylist([track])
                } label: {
                    Label("加入歌单", systemImage: "text.badge.plus")
                }
                .tint(.blue)
            }
    }
}

/// Menu items, also used by the "…" button on the Now Playing screen.
struct TrackMenuItems: View {
    let track: PlayableTrack
    var list: [PlayableTrack] = []

    @Environment(TrackActions.self) private var actions
    @Environment(DownloadManager.self) private var downloads

    var body: some View {
        Button {
            actions.play(track, in: list.isEmpty ? [track] : list)
        } label: {
            Label("播放", systemImage: "play")
        }
        Button {
            actions.playNext([track])
        } label: {
            Label("下一首播放", systemImage: "text.insert")
        }
        Button {
            actions.addToQueue([track])
        } label: {
            Label("添加到播放队列", systemImage: "text.append")
        }
        Divider()
        Button {
            actions.toggleFavorite(track)
        } label: {
            if actions.isFavorite(track) {
                Label("取消收藏", systemImage: "heart.slash")
            } else {
                Label("收藏", systemImage: "heart")
            }
        }
        Button {
            actions.addToPlaylist([track])
        } label: {
            Label("添加到歌单…", systemImage: "text.badge.plus")
        }
        if !actions.isInLibrary(track) {
            Button {
                actions.addToLibrary(track)
            } label: {
                Label("加入曲库", systemImage: "plus.circle")
            }
        }
        if downloads.canDownload(track) {
            switch downloads.status(for: track) {
            case .downloaded:
                Button(role: .destructive) {
                    actions.removeDownload(track)
                } label: {
                    Label("删除下载", systemImage: "trash")
                }
            case .downloading:
                Button {
                    downloads.cancel(track.id)
                } label: {
                    Label("取消下载", systemImage: "xmark.circle")
                }
            case .notDownloaded, .failed:
                Button {
                    actions.download(track)
                } label: {
                    Label("下载", systemImage: "arrow.down.circle")
                }
            }
        }
        Divider()
        Button {
            actions.showInfo(track)
        } label: {
            Label("详细信息与授权", systemImage: "info.circle")
        }
        if let page = track.webPageURL {
            Link(destination: page) {
                Label(track.source == .itunes ? "在 Apple Music 中打开" : "打开来源网页", systemImage: "safari")
            }
        }
    }
}

extension View {
    func trackMenu(_ track: PlayableTrack, in list: [PlayableTrack]) -> some View {
        modifier(TrackMenuModifier(track: track, list: list))
    }
}
