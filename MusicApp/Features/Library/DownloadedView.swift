import SwiftData
import SwiftUI

struct DownloadedView: View {
    @Query(filter: #Predicate<Track> { $0.localFilename != nil && $0.sourceRaw != "local" },
           sort: \Track.dateAdded, order: .reverse)
    private var downloaded: [Track]
    @Environment(TrackActions.self) private var actions
    @Environment(DownloadManager.self) private var downloads

    var body: some View {
        TrackListView(
            title: "已下载",
            tracks: downloaded,
            emptyTitle: "没有下载的歌曲",
            emptyMessage: "来自 Openverse、Internet Archive 和 Jamendo 的完整曲目可以下载离线收听。",
            emptySystemImage: "arrow.down.circle",
            deleteLabel: "删除下载",
            onDelete: { track in
                actions.removeDownload(track.playable)
            }
        )
        .safeAreaInset(edge: .top) {
            if downloads.activeCount > 0 {
                Label("正在下载 \(downloads.activeCount) 首", systemImage: "arrow.down.circle")
                    .font(.footnote)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
        }
    }
}
