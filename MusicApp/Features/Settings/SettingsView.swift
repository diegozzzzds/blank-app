import SwiftData
import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.jamendoClientID) private var jamendoClientID = ""
    @AppStorage(SettingsKey.itunesCountry) private var itunesCountry = "HK"
    @AppStorage(SettingsKey.searchAsYouType) private var searchAsYouType = false
    @AppStorage(SettingsKey.openverseIncludeNonMusic) private var includeNonMusic = false

    @Environment(SourceRegistry.self) private var registry
    @Environment(LibraryStore.self) private var library
    @Environment(LyricsService.self) private var lyrics
    @Environment(TrackActions.self) private var actions

    @State private var jamendoTest: TestState = .idle
    @State private var downloadsSize: Int64 = 0
    @State private var cacheSize = 0
    @State private var confirmDeleteDownloads = false

    enum TestState: Equatable {
        case idle
        case testing
        case success
        case failure(String)
    }

    private let countries: [(code: String, name: String)] = [
        ("HK", "中国香港"), ("TW", "中国台湾"), ("US", "美国"), ("JP", "日本"), ("SG", "新加坡"), ("GB", "英国"),
    ]

    var body: some View {
        Form {
            Section {
                Picker("iTunes 地区", selection: $itunesCountry) {
                    ForEach(countries, id: \.code) { country in
                        Text(country.name).tag(country.code)
                    }
                }
                Toggle("边输入边搜索", isOn: $searchAsYouType)
                Toggle("Openverse 包含音效和其他音频", isOn: $includeNonMusic)
            } header: {
                Text("搜索")
            } footer: {
                Text("iTunes 中国大陆区不提供搜索结果，默认使用香港区。边输入边搜索只作用于 iTunes 和本地曲库；其他来源在按下搜索键后才请求，以免触发频率限制。")
            }

            Section {
                TextField("client_id", text: $jamendoClientID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .onChange(of: jamendoClientID) { jamendoTest = .idle }
                HStack {
                    Button("测试连接") {
                        Task { await testJamendo() }
                    }
                    .disabled(jamendoClientID.trimmingCharacters(in: .whitespaces).isEmpty || jamendoTest == .testing)
                    Spacer()
                    switch jamendoTest {
                    case .idle:
                        EmptyView()
                    case .testing:
                        ProgressView()
                    case .success:
                        Label("可用", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failure(let message):
                        Label(message, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
                Link("免费申请 client_id", destination: URL(string: "https://devportal.jamendo.com")!)
            } header: {
                Text("Jamendo")
            } footer: {
                Text("Jamendo 提供大量可完整播放、可下载的 CC 授权独立音乐。在 Jamendo 开发者网站注册一个应用即可获得 client_id。")
            }

            Section {
                LabeledContent("已下载音乐", value: ByteCountFormatter.string(fromByteCount: downloadsSize, countStyle: .file))
                LabeledContent("图片缓存", value: ByteCountFormatter.string(fromByteCount: Int64(cacheSize), countStyle: .file))
                Button("清除图片缓存") {
                    URLCache.shared.removeAllCachedResponses()
                    refreshSizes()
                    actions.showToast("已清除图片缓存")
                }
                Button("清除歌词缓存") {
                    clearLyricsCache()
                }
                Button("删除所有下载", role: .destructive) {
                    confirmDeleteDownloads = true
                }
                .disabled(downloadsSize == 0)
            } header: {
                Text("存储")
            }

            Section {
                NavigationLink("关于与版权") {
                    AboutView()
                }
            }
        }
        .navigationTitle("设置")
        .onAppear(perform: refreshSizes)
        .confirmationDialog("删除所有下载的歌曲？", isPresented: $confirmDeleteDownloads, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                deleteAllDownloads()
            }
        } message: {
            Text("导入的本地音乐不会被删除。")
        }
    }

    private func testJamendo() async {
        jamendoTest = .testing
        let source = JamendoSource(http: registry.http, clientID: jamendoClientID)
        do {
            try await source.testConnection()
            jamendoTest = .success
        } catch {
            jamendoTest = .failure(MusicSourceError.wrap(error).errorDescription ?? "失败")
        }
    }

    private func refreshSizes() {
        downloadsSize = FileLocations.directorySize(FileLocations.standard.musicDirectory)
        cacheSize = URLCache.shared.currentDiskUsage
    }

    private func clearLyricsCache() {
        let descriptor = FetchDescriptor<Track>(predicate: #Predicate { $0.cachedLyrics != nil })
        for track in (try? library.context.fetch(descriptor)) ?? [] {
            track.cachedLyrics = nil
            track.cachedLyricsSynced = false
        }
        library.save()
        lyrics.clearMemoryCache()
        actions.showToast("已清除歌词缓存")
    }

    private func deleteAllDownloads() {
        for track in library.allDownloadedTracks() where track.source != .local {
            actions.removeDownload(track.playable)
        }
        refreshSizes()
    }
}
