import SwiftData
import SwiftUI

struct SongsListView: View {
    enum SortOrder: String, CaseIterable {
        case dateAdded = "最近添加"
        case title = "歌名"
        case artist = "歌手"
        case mostPlayed = "播放次数"
    }

    @Query private var tracks: [Track]
    @State private var sortOrder: SortOrder = .dateAdded

    var body: some View {
        TrackListView(
            title: "歌曲",
            tracks: sorted,
            emptyTitle: "还没有歌曲",
            emptyMessage: "收藏、加入歌单、下载或导入的歌曲都会出现在这里。"
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("排序", selection: $sortOrder) {
                        ForEach(SortOrder.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("排序")
            }
        }
    }

    private var sorted: [Track] {
        switch sortOrder {
        case .dateAdded: return tracks.sorted { $0.dateAdded > $1.dateAdded }
        case .title: return tracks.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .artist: return tracks.sorted { $0.artist.localizedStandardCompare($1.artist) == .orderedAscending }
        case .mostPlayed: return tracks.sorted { $0.playCount > $1.playCount }
        }
    }
}
