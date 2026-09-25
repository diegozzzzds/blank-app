import SwiftUI

struct LyricsView: View {
    let track: PlayableTrack

    @Environment(LyricsService.self) private var lyrics

    var body: some View {
        Group {
            switch lyrics.state {
            case .idle, .loading:
                ProgressView("正在查找歌词…")
            case .loaded(let document, let origin):
                if document.isSynced {
                    SyncedLyricsList(document: document, footer: footer(for: origin))
                } else {
                    PlainLyricsList(document: document, note: track.isPreview ? "试听片段，歌词不同步滚动" : nil,
                                    footer: footer(for: origin))
                }
            case .instrumental:
                message("纯音乐，请欣赏", systemImage: "music.quarternote.3")
            case .notFound:
                message("暂无歌词", systemImage: "text.quote",
                        detail: "本地歌曲可以导入同名的 .lrc 歌词文件。")
            case .failed(let error):
                VStack(spacing: 12) {
                    message("歌词加载失败", systemImage: "wifi.exclamationmark", detail: error)
                    Button("重试") {
                        Task { await lyrics.load(for: track, force: true) }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func footer(for origin: LyricsService.Origin) -> String {
        switch origin {
        case .custom: return "歌词来自导入的 .lrc 文件"
        case .cache, .lrclib: return "歌词来自 LRCLIB"
        }
    }

    private func message(_ title: String, systemImage: String, detail: String? = nil) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
}

/// Scrolls to the current line; tapping a line seeks there. Auto-scroll pauses for a few seconds after the user drags.
private struct SyncedLyricsList: View {
    let document: LyricsDocument
    let footer: String

    @Environment(PlayerManager.self) private var player
    @State private var lastUserScroll = Date.distantPast

    var body: some View {
        let current = document.lineIndex(at: player.currentTime + 0.15)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    Color.clear.frame(height: 120)
                    ForEach(document.lines) { line in
                        let isCurrent = line.id == current
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(isCurrent ? .title3.weight(.bold) : .title3.weight(.medium))
                            .foregroundStyle(isCurrent ? Color.primary : Color.secondary.opacity(0.7))
                            .scaleEffect(isCurrent ? 1.0 : 0.96, anchor: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                Task { await player.seek(to: line.time) }
                                lastUserScroll = .distantPast
                            }
                            .id(line.id)
                            .animation(.easeOut(duration: 0.25), value: isCurrent)
                    }
                    Text(footer)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 24)
                    Color.clear.frame(height: 200)
                }
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden)
            .simultaneousGesture(DragGesture().onChanged { _ in lastUserScroll = Date() })
            .onChange(of: current) { _, newValue in
                guard let newValue, Date().timeIntervalSince(lastUserScroll) > 3 else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
            .onAppear {
                if let current {
                    proxy.scrollTo(current, anchor: .center)
                }
            }
        }
    }
}

private struct PlainLyricsList: View {
    let document: LyricsDocument
    let note: String?
    let footer: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let note {
                    Label(note, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                }
                ForEach(document.lines) { line in
                    Text(line.text.isEmpty ? " " : line.text)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Color.primary.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 24)
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
    }
}
