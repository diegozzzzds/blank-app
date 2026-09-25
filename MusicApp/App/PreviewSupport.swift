import SwiftData
import SwiftUI

#if DEBUG
/// In-memory dependencies and sample data for SwiftUI previews.
@MainActor
enum PreviewSupport {
    static let dependencies: AppDependencies = {
        let container = try! ModelContainerFactory.make(inMemory: true)
        return AppDependencies(container: container)
    }()

    static let sampleTracks: [PlayableTrack] = [
        PlayableTrack(
            id: "openverse:preview-1",
            source: .openverse,
            title: "Old Movie Ragtime Piano",
            artist: "Akashic Records",
            album: "Silent Movie Ragtime Piano",
            duration: 72,
            streamURL: URL(string: "https://prod-1.storage.jamendo.com/?trackid=923463&format=mp32"),
            license: LicenseInfo(code: "by-nc-nd", version: "3.0")
        ),
        PlayableTrack(
            id: "itunes:preview-2",
            source: .itunes,
            title: "晴天",
            artist: "周杰倫",
            album: "葉惠美",
            duration: 269,
            isPreview: true
        ),
    ]
}

#Preview("主界面") {
    RootView()
        .appEnvironment(PreviewSupport.dependencies)
}

#Preview("歌曲行") {
    List(PreviewSupport.sampleTracks) { track in
        TrackRow(track: track)
    }
    .appEnvironment(PreviewSupport.dependencies)
}
#endif
