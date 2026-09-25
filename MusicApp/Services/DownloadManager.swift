import Foundation
import Observation

/// Downloads full-length CC tracks into Documents/Music for offline listening.
/// iTunes previews are never downloaded (their terms only allow streaming).
@MainActor
@Observable
final class DownloadManager {
    enum Status: Equatable {
        case notDownloaded
        case downloading(Double)
        case downloaded
        case failed(String)
    }

    /// Progress (0...1) keyed by track id.
    private(set) var progress: [String: Double] = [:]
    private(set) var failures: [String: String] = [:]

    @ObservationIgnored private var tasks: [String: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var pending: [String: PlayableTrack] = [:]
    private let files: FileLocations
    private let library: LibraryStore
    private let player: PlayerManager
    private let delegate: DownloadDelegate
    private let session: URLSession

    init(files: FileLocations, library: LibraryStore, player: PlayerManager) {
        self.files = files
        self.library = library
        self.player = player
        let delegate = DownloadDelegate()
        self.delegate = delegate
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = ["User-Agent": URLSessionHTTPClient.userAgent]
        self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)

        delegate.onProgress = { [weak self] id, fraction in
            Task { @MainActor in
                guard let self, self.progress[id] != nil else { return }
                self.progress[id] = fraction
            }
        }
        delegate.onFinished = { [weak self] id, tempURL, ext in
            Task { @MainActor in self?.finish(id: id, tempURL: tempURL, ext: ext) }
        }
        delegate.onFailed = { [weak self] id, message in
            Task { @MainActor in self?.fail(id: id, message: message) }
        }
    }

    var activeCount: Int { progress.count }

    func status(for track: PlayableTrack) -> Status {
        _ = library.revision
        if let fraction = progress[track.id] { return .downloading(fraction) }
        if let stored = library.track(withID: track.id), let filename = stored.localFilename,
           files.musicFileExists(filename) {
            return .downloaded
        }
        if let message = failures[track.id] { return .failed(message) }
        return .notDownloaded
    }

    func canDownload(_ track: PlayableTrack) -> Bool {
        track.isDownloadable && !track.isPreview
    }

    func download(_ track: PlayableTrack) {
        guard canDownload(track), let url = track.downloadURL, progress[track.id] == nil else { return }
        if case .downloaded = status(for: track) { return }
        library.upsert(track)
        failures[track.id] = nil
        progress[track.id] = 0
        pending[track.id] = track
        let task = session.downloadTask(with: url)
        task.taskDescription = track.id
        tasks[track.id] = task
        task.resume()
    }

    func download(_ tracks: [PlayableTrack]) {
        for track in tracks {
            download(track)
        }
    }

    func cancel(_ id: String) {
        tasks[id]?.cancel()
        tasks[id] = nil
        pending[id] = nil
        progress[id] = nil
    }

    func removeDownload(_ track: PlayableTrack) {
        cancel(track.id)
        library.removeDownload(for: track.id)
        var updated = track
        updated.localFilename = nil
        player.trackDidChange(updated)
    }

    private func finish(id: String, tempURL: URL, ext: String) {
        defer {
            tasks[id] = nil
            pending[id] = nil
            progress[id] = nil
        }
        guard let track = pending[id] ?? library.track(withID: id)?.playable else {
            try? FileManager.default.removeItem(at: tempURL)
            return
        }
        let filename = files.uniqueMusicFilename(base: "\(track.artist) - \(track.title)", ext: ext)
        let destination = files.musicURL(filename)
        do {
            try FileManager.default.moveItem(at: tempURL, to: destination)
        } catch {
            failures[id] = "保存文件失败：\(error.localizedDescription)"
            return
        }
        FileLocations.excludeFromBackup(destination)
        let stored = library.upsert(track)
        stored.localFilename = filename
        library.save()
        player.trackDidChange(stored.playable)
    }

    private func fail(id: String, message: String) {
        guard progress[id] != nil else { return }
        progress[id] = nil
        tasks[id] = nil
        pending[id] = nil
        failures[id] = message
    }
}

/// URLSession callbacks arrive on a background queue.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    var onProgress: ((String, Double) -> Void)?
    var onFinished: ((String, URL, String) -> Void)?
    var onFailed: ((String, String) -> Void)?

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let id = downloadTask.taskDescription, totalBytesExpectedToWrite > 0 else { return }
        onProgress?(id, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            onFailed?(id, "服务器返回错误（HTTP \(http.statusCode)）")
            return
        }
        let response = downloadTask.response
        let ext = FileNaming.fileExtension(forMIME: response?.mimeType)
            ?? response?.suggestedFilename.flatMap { name -> String? in
                let ext = (name as NSString).pathExtension.lowercased()
                return FileNaming.playableExtensions.contains(ext) ? ext : nil
            }
            ?? "mp3"
        // The system deletes `location` when this method returns, so move it synchronously.
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        do {
            try FileManager.default.moveItem(at: location, to: staging)
            onFinished?(id, staging, ext)
        } catch {
            onFailed?(id, "保存文件失败：\(error.localizedDescription)")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let id = task.taskDescription else { return }
        if (error as? URLError)?.code == .cancelled { return }
        onFailed?(id, error.localizedDescription)
    }
}
