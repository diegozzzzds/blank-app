import SwiftUI

/// Shown before a search: recent searches and a short guide to the sources.
struct SearchHistoryView: View {
    @Environment(SearchViewModel.self) private var model
    let jamendoEnabled: Bool

    var body: some View {
        if !model.history.items.isEmpty {
            Section {
                ForEach(model.history.items, id: \.self) { term in
                    Button {
                        model.search(term)
                    } label: {
                        Label(term, systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(.primary)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            model.removeFromHistory(term)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("最近搜索")
                    Spacer()
                    Button("清除") { model.clearHistory() }
                        .font(.caption)
                        .textCase(nil)
                }
            }
        }

        Section("音乐来源") {
            sourceRow(.itunes, "主流歌曲、封面和 30 秒试听")
            if jamendoEnabled {
                sourceRow(.jamendo, "CC 授权的独立音乐，完整播放，可下载")
            }
            sourceRow(.openverse, "CC 授权的完整曲目，可下载")
            sourceRow(.internetArchive, "公有领域与 CC 专辑、老唱片、现场录音")
            sourceRow(.local, "你收藏、下载和导入的歌曲")
        }

        if !jamendoEnabled {
            Section {
                Text("在「设置」里填写 Jamendo client_id，可以搜索更多可完整播放的独立音乐。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sourceRow(_ source: SourceID, _ description: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            SourceBadge(source: source)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
