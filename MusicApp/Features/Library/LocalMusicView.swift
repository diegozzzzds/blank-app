import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Declared in Info.plist (UTImportedTypeDeclarations); there is no system type for .lrc.
    static let lrc = UTType(importedAs: "com.musicapp.lrc", conformingTo: .plainText)
}

struct LocalMusicView: View {
    @Query(filter: #Predicate<Track> { $0.sourceRaw == "local" }, sort: \Track.dateAdded, order: .reverse)
    private var localTracks: [Track]
    @Environment(LocalImportService.self) private var importer

    @State private var showImporter = false
    @State private var isImporting = false
    @State private var report: LocalImportService.Report?

    var body: some View {
        TrackListView(
            title: "本地音乐",
            tracks: localTracks,
            emptyTitle: "没有本地音乐",
            emptyMessage: "点右上角的 + 从「文件」App 导入 mp3、m4a 等音乐文件。同名的 .lrc 歌词文件会一起导入。",
            emptySystemImage: "folder"
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showImporter = true
                    } label: {
                        Label("从「文件」导入…", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        Task { await scan() }
                    } label: {
                        Label("扫描 App 文件夹", systemImage: "arrow.clockwise")
                    }
                } label: {
                    if isImporting {
                        ProgressView()
                    } else {
                        Image(systemName: "plus")
                    }
                }
                .disabled(isImporting)
                .accessibilityLabel("导入音乐")
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.audio, .lrc],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task { await importFiles(urls) }
            case .failure(let error):
                report = LocalImportService.Report(failures: [error.localizedDescription])
            }
        }
        .alert("导入完成", isPresented: Binding(get: { report != nil }, set: { if !$0 { report = nil } })) {
            Button("好") { report = nil }
        } message: {
            if let report {
                Text(([report.summary] + report.failures.prefix(5)).joined(separator: "\n"))
            }
        }
    }

    private func importFiles(_ urls: [URL]) async {
        isImporting = true
        report = await importer.importFiles(urls)
        isImporting = false
    }

    private func scan() async {
        isImporting = true
        let result = await importer.scanDocumentsFolder()
        isImporting = false
        report = result.imported == 0 && result.lyricsMatched == 0
            ? LocalImportService.Report(failures: ["没有发现新的音乐文件。可以用「文件」App 或电脑上的访达把音乐拷到本 App 的文件夹里。"])
            : result
    }
}
