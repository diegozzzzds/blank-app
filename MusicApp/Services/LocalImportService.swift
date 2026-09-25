import AVFoundation
import Foundation
import Observation
import UIKit

/// Imports audio files (and matching .lrc lyrics) from the Files app into Documents/Music.
@MainActor
@Observable
final class LocalImportService {
    struct Report: Equatable {
        var imported = 0
        var lyricsMatched = 0
        var skipped = 0
        var failures: [String] = []

        var summary: String {
            var parts: [String] = []
            parts.append("导入 \(imported) 首")
            if lyricsMatched > 0 { parts.append("匹配歌词 \(lyricsMatched) 个") }
            if skipped > 0 { parts.append("跳过 \(skipped) 个") }
            if !failures.isEmpty { parts.append("失败 \(failures.count) 个") }
            return parts.joined(separator: "，")
        }
    }

    struct LocalMetadata: Sendable {
        var title: String?
        var artist: String?
        var album: String?
        var duration: TimeInterval?
        var artworkData: Data?
    }

    private let files: FileLocations
    private let library: LibraryStore

    init(files: FileLocations, library: LibraryStore) {
        self.files = files
        self.library = library
    }

    /// Imports files picked with `.fileImporter`. Audio is copied; `.lrc` files are attached to the
    /// audio file with the same base name (imported now or already in the library).
    func importFiles(_ urls: [URL]) async -> Report {
        var report = Report()
        var importedByBaseName: [String: String] = [:]
        let audio = urls.filter { FileNaming.playableExtensions.contains($0.pathExtension.lowercased()) }
        let lyrics = urls.filter { $0.pathExtension.lowercased() == "lrc" }
        report.skipped = urls.count - audio.count - lyrics.count

        for url in audio {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let base = url.deletingPathExtension().lastPathComponent
                let filename = files.uniqueMusicFilename(base: base, ext: url.pathExtension.lowercased())
                let destination = files.musicURL(filename)
                try FileManager.default.copyItem(at: url, to: destination)
                let id = await register(fileAt: destination, filename: filename)
                importedByBaseName[base.lowercased()] = id
                report.imported += 1
            } catch {
                report.failures.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }

        for url in lyrics {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), let text = TextDecoding.decodeText(data) else {
                report.failures.append("\(url.lastPathComponent)：无法读取")
                continue
            }
            let base = url.deletingPathExtension().lastPathComponent.lowercased()
            if let id = importedByBaseName[base] ?? existingTrackID(forBaseName: base) {
                library.setCustomLyrics(text, for: id)
                report.lyricsMatched += 1
            } else {
                report.failures.append("\(url.lastPathComponent)：找不到同名的歌曲")
            }
        }
        return report
    }

    /// Registers audio files that were copied into Documents (or Documents/Music) via the Files app or Finder.
    func scanDocumentsFolder() async -> Report {
        var report = Report()
        let manager = FileManager.default
        let known = Set(library.allDownloadedTracks().compactMap(\.localFilename))

        // Files dropped in the Documents root are moved into Music first.
        let rootFiles = (try? manager.contentsOfDirectory(at: files.documentsDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in rootFiles where FileNaming.playableExtensions.contains(url.pathExtension.lowercased()) {
            let filename = files.uniqueMusicFilename(base: url.deletingPathExtension().lastPathComponent, ext: url.pathExtension.lowercased())
            try? manager.moveItem(at: url, to: files.musicURL(filename))
        }

        let musicFiles = (try? manager.contentsOfDirectory(at: files.musicDirectory, includingPropertiesForKeys: nil)) ?? []
        var byBaseName: [String: String] = [:]
        for url in musicFiles where FileNaming.playableExtensions.contains(url.pathExtension.lowercased()) {
            let filename = url.lastPathComponent
            guard !known.contains(filename) else { continue }
            let id = await register(fileAt: url, filename: filename)
            byBaseName[url.deletingPathExtension().lastPathComponent.lowercased()] = id
            report.imported += 1
        }

        let lyricFiles = (rootFiles + musicFiles).filter { $0.pathExtension.lowercased() == "lrc" }
        for url in lyricFiles {
            let base = url.deletingPathExtension().lastPathComponent.lowercased()
            guard let id = byBaseName[base] ?? existingTrackID(forBaseName: base),
                  library.track(withID: id)?.customLyrics == nil,
                  let data = try? Data(contentsOf: url),
                  let text = TextDecoding.decodeText(data) else { continue }
            library.setCustomLyrics(text, for: id)
            report.lyricsMatched += 1
        }
        return report
    }

    private func existingTrackID(forBaseName base: String) -> String? {
        library.allDownloadedTracks().first { track in
            guard let filename = track.localFilename else { return false }
            return (filename as NSString).deletingPathExtension.lowercased() == base
        }?.stableID
    }

    /// Reads tags, saves artwork and inserts the track. Returns its id.
    private func register(fileAt url: URL, filename: String) async -> String {
        let metadata = await Self.readMetadata(url)
        let id = "local:\(UUID().uuidString)"
        var artworkFilename: String?
        if let data = metadata.artworkData, let image = UIImage(data: data),
           let jpeg = image.jpegData(compressionQuality: 0.85) {
            let name = "\(UUID().uuidString).jpg"
            if (try? jpeg.write(to: files.artworkURL(name))) != nil {
                artworkFilename = name
            }
        }
        let fallback = Self.parseFilename(url.deletingPathExtension().lastPathComponent)
        let track = PlayableTrack(
            id: id,
            source: .local,
            title: metadata.title.nonEmpty ?? fallback.title,
            artist: metadata.artist.nonEmpty ?? fallback.artist ?? "未知艺术家",
            album: metadata.album.nonEmpty,
            duration: metadata.duration,
            localArtworkFilename: artworkFilename,
            localFilename: filename,
            isPreview: false
        )
        library.upsert(track)
        return id
    }

    /// "Artist - Title" file names are common when tags are missing.
    nonisolated static func parseFilename(_ name: String) -> (title: String, artist: String?) {
        let cleaned = name.replacingOccurrences(of: "_", with: " ")
        if let range = cleaned.range(of: " - ") {
            let artist = cleaned[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let title = cleaned[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if !artist.isEmpty, !title.isEmpty { return (title, artist) }
        }
        return (cleaned.trimmingCharacters(in: .whitespaces), nil)
    }

    nonisolated static func readMetadata(_ url: URL) async -> LocalMetadata {
        let asset = AVURLAsset(url: url)
        var result = LocalMetadata()
        guard let loaded = try? await asset.load(.commonMetadata, .duration) else { return result }
        let (items, duration) = loaded
        let seconds = duration.seconds
        if seconds.isFinite, seconds > 0 { result.duration = seconds }

        func string(_ identifier: AVMetadataIdentifier) async -> String? {
            guard let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier).first else {
                return nil
            }
            return try? await item.load(.stringValue)
        }
        result.title = await string(.commonIdentifierTitle)
        result.artist = await string(.commonIdentifierArtist)
        result.album = await string(.commonIdentifierAlbumName)
        if let artwork = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .commonIdentifierArtwork).first {
            result.artworkData = try? await artwork.load(.dataValue)
        }
        return result
    }
}
