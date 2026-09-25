import SwiftUI

struct SearchView: View {
    @Environment(SearchViewModel.self) private var model
    @AppStorage(SettingsKey.jamendoClientID) private var jamendoClientID = ""
    @AppStorage(SettingsKey.searchAsYouType) private var searchAsYouType = false

    private let previewLimit = 5

    var body: some View {
        @Bindable var model = model
        List {
            if model.hasSubmitted {
                Section {
                    SourceFilterBar(filter: $model.filter, sources: model.availableSources, counts: counts)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                ForEach(model.visibleSources, id: \.self) { source in
                    SourceSectionView(
                        source: source,
                        previewLimit: model.filter == .all ? previewLimit : nil,
                        onShowAll: { model.filter = .only(source) }
                    )
                }
            } else {
                SearchHistoryView(jamendoEnabled: !jamendoClientID.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("搜索")
        .searchable(text: $model.text, placement: .navigationBarDrawer(displayMode: .always), prompt: "歌曲、歌手、专辑")
        .searchScopes($model.scope, activation: .onSearchPresentation) {
            ForEach(SearchScope.allCases, id: \.self) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .onSubmit(of: .search) {
            model.submit()
        }
        .onChange(of: model.scope) {
            model.scopeChanged()
        }
        .onChange(of: model.filter) {
            model.filterChanged()
        }
        .onChange(of: model.text) { _, newValue in
            if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                model.reset()
            }
        }
        .task(id: searchAsYouType ? model.text : "") {
            // Optional search-as-you-type, debounced; only hits iTunes and the local library.
            guard searchAsYouType, !model.text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            model.liveSearch()
        }
        .navigationDestination(for: RemoteCollection.self) { collection in
            CollectionDetailView(collection: collection)
        }
    }

    private var counts: [SourceID: Int] {
        var result: [SourceID: Int] = [:]
        for source in model.availableSources {
            if source == .local {
                result[source] = model.localResults.count
            } else if let state = model.sections[source], state.status == .loaded {
                result[source] = state.totalCount ?? state.items.count
            }
        }
        return result
    }
}
