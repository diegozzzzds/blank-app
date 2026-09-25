import SwiftData
import SwiftUI

struct FavoritesView: View {
    @Query(filter: #Predicate<Track> { $0.isFavorite }) private var favorites: [Track]
    @Environment(LibraryStore.self) private var library

    var body: some View {
        TrackListView(
            title: "收藏",
            tracks: favorites.sorted { ($0.favoritedAt ?? .distantPast) > ($1.favoritedAt ?? .distantPast) },
            emptyTitle: "还没有收藏",
            emptyMessage: "点歌曲右侧的菜单或向左滑动即可收藏。",
            emptySystemImage: "heart",
            deleteLabel: "取消收藏",
            onDelete: { track in
                library.setFavorite(track.playable, false)
            }
        )
    }
}
