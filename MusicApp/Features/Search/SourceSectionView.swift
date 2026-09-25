import SwiftUI

/// One source's results inside the search list.
struct SourceSectionView: View {
    let source: SourceID
    /// In the "全部" view each source shows a preview; tapping "更多" switches the filter.
    var previewLimit: Int?
    var onShowAll: (() -> Void)?

    @Environment(SearchViewModel.self) private var model
    @Environment(TrackActions.self) private var actions

    var body: some View {
        Section {
            if source == .local {
                localContent
            } else if let state = model.sections[source] {
                remoteContent(state)
            }
        } header: {
            header
        } footer: {
            if let hint = model.hint(for: source) {
                Text(hint)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            SourceBadge(source: source)
            Text(source.displayName)
            Spacer()
            if let count = totalCount, count > 0 {
                Text("\(count) 条结果")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
    }

    private var totalCount: Int? {
        if source == .local { return model.localResults.count }
        guard let state = model.sections[source], state.status == .loaded else { return nil }
        return state.totalCount ?? model.items(for: source).count
    }

    // MARK: - Local

    @ViewBuilder
    private var localContent: some View {
        let tracks = model.localResults
        if tracks.isEmpty {
            Text("曲库里没有匹配的歌曲")
                .foregroundStyle(.secondary)
        } else {
            ForEach(limited(tracks)) { track in
                trackButton(track, list: tracks)
            }
            showAllButton(total: tracks.count)
        }
    }

    // MARK: - Remote

    @ViewBuilder
    private func remoteContent(_ state: SourceSectionState) -> some View {
        switch state.status {
        case .loading:
            HStack {
                ProgressView()
                Text("正在搜索…").foregroundStyle(.secondary)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                Button("重试") { model.retry(source) }
                    .buttonStyle(.borderless)
            }
        case .loaded:
            let items = model.items(for: source)
            if items.isEmpty {
                Text("没有找到结果")
                    .foregroundStyle(.secondary)
            } else {
                let tracks = items.compactMap(\.track)
                ForEach(limited(items)) { item in
                    switch item {
                    case .track(let track):
                        trackButton(track, list: tracks)
                    case .collection(let collection):
                        NavigationLink(value: collection) {
                            CollectionRow(collection: collection)
                        }
                    }
                }
                if previewLimit != nil {
                    showAllButton(total: items.count, hasMore: state.hasMore)
                } else {
                    loadMoreRow(state)
                }
            }
        }
    }

    @ViewBuilder
    private func loadMoreRow(_ state: SourceSectionState) -> some View {
        if state.isLoadingMore {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
        } else if let error = state.loadMoreError {
            Button("加载失败，点此重试（\(error)）") {
                Task { await model.loadMore(source) }
            }
            .font(.footnote)
        } else if state.hasMore {
            Button {
                Task { await model.loadMore(source) }
            } label: {
                HStack {
                    Spacer()
                    Text("加载更多")
                    Spacer()
                }
            }
            .onAppear {
                // Infinite scroll: load when the button scrolls into view.
                Task { await model.loadMore(source) }
            }
        }
    }

    @ViewBuilder
    private func showAllButton(total: Int, hasMore: Bool = false) -> some View {
        if let previewLimit, total > previewLimit || hasMore, let onShowAll {
            Button {
                onShowAll()
            } label: {
                HStack {
                    Text("查看全部 \(source.displayName) 结果")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func trackButton(_ track: PlayableTrack, list: [PlayableTrack]) -> some View {
        Button {
            actions.play(track, in: list)
        } label: {
            TrackRow(track: track, showsSource: false)
        }
        .buttonStyle(.plain)
        .trackMenu(track, in: list)
    }

    private func limited<T>(_ items: [T]) -> [T] {
        guard let previewLimit else { return items }
        return Array(items.prefix(previewLimit))
    }
}
