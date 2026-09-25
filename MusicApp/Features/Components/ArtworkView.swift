import SwiftUI
import UIKit

/// Cover art with a gradient placeholder. Loads local artwork from disk and remote artwork with AsyncImage.
struct ArtworkView: View {
    var url: URL?
    var localFilename: String?
    var size: CGFloat?
    var cornerRadius: CGFloat = 8
    /// Picks a stable placeholder colour.
    var seed: String = ""

    init(url: URL?, localFilename: String? = nil, size: CGFloat? = nil, cornerRadius: CGFloat = 8, seed: String = "") {
        self.url = url
        self.localFilename = localFilename
        self.size = size
        self.cornerRadius = cornerRadius
        self.seed = seed
    }

    init(track: PlayableTrack, size: CGFloat? = nil, cornerRadius: CGFloat = 8) {
        self.init(url: track.artworkURL, localFilename: track.localArtworkFilename, size: size,
                  cornerRadius: cornerRadius, seed: track.id)
    }

    init(collection: RemoteCollection, size: CGFloat? = nil, cornerRadius: CGFloat = 8) {
        self.init(url: collection.artworkURL, size: size, cornerRadius: cornerRadius, seed: collection.id)
    }

    @State private var localImage: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { content }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: localFilename) {
                guard let localFilename else {
                    localImage = nil
                    return
                }
                let path = FileLocations.standard.artworkURL(localFilename).path
                localImage = await Task.detached(priority: .utility) { UIImage(contentsOfFile: path) }.value
            }
    }

    @ViewBuilder
    private var content: some View {
        if let localImage {
            Image(uiImage: localImage)
                .resizable()
                .scaledToFill()
        } else if let url {
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        let palettes: [[Color]] = [
            [.pink, .purple], [.orange, .red], [.teal, .blue], [.indigo, .purple], [.mint, .teal], [.yellow, .orange],
        ]
        let index = abs(seed.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }) % palettes.count
        return ZStack {
            LinearGradient(colors: palettes[index], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "music.note")
                .font(.system(size: max(12, (size ?? 120) * 0.38), weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
