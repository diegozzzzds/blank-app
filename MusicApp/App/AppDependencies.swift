import Foundation
import SwiftData

/// Creates and owns every long-lived service. Lives for the whole app lifetime.
@MainActor
final class AppDependencies {
    let container: ModelContainer
    let files: FileLocations
    let http: HTTPClient
    let registry: SourceRegistry
    let library: LibraryStore
    let audioSession: AudioSessionController
    let player: PlayerManager
    let lyrics: LyricsService
    let downloads: DownloadManager
    let importer: LocalImportService
    let actions: TrackActions
    let search: SearchViewModel

    init(container: ModelContainer, files: FileLocations = .standard) {
        self.container = container
        self.files = files
        http = URLSessionHTTPClient()
        registry = SourceRegistry(http: http)
        library = LibraryStore(context: container.mainContext, files: files)
        audioSession = AudioSessionController()
        audioSession.configure()
        player = PlayerManager(
            audioSession: audioSession,
            nowPlaying: NowPlayingController(),
            artwork: ArtworkLoader(files: files),
            files: files,
            library: library
        )
        lyrics = LyricsService(client: LRCLIBClient(http: http), library: library)
        downloads = DownloadManager(files: files, library: library, player: player)
        importer = LocalImportService(files: files, library: library)
        actions = TrackActions(library: library, player: player, downloads: downloads)
        search = SearchViewModel(registry: registry, library: library)
    }
}
