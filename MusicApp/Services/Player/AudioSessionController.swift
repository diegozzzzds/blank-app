import AVFoundation
import Foundation

/// Owns the AVAudioSession: category, activation, interruptions and route changes.
@MainActor
final class AudioSessionController {
    var onInterruptionBegan: (() -> Void)?
    var onInterruptionEnded: ((_ shouldResume: Bool) -> Void)?
    /// Headphones unplugged / Bluetooth disconnected: playback should pause.
    var onOldDeviceUnavailable: (() -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var isActive = false

    /// Called at launch. Sets the category without activating, so launching doesn't stop other apps' audio.
    func configure() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        } catch {
            print("AVAudioSession category error: \(error)")
        }
        startObserving()
    }

    /// Called right before playback starts.
    func activate() {
        guard !isActive else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            isActive = true
        } catch {
            print("AVAudioSession activation error: \(error)")
        }
    }

    private func startObserving() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: session, queue: .main
        ) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            MainActor.assumeIsolated {
                self?.handleInterruption(type: type, options: options)
            }
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: session, queue: .main
        ) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                .flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            MainActor.assumeIsolated {
                if reason == .oldDeviceUnavailable {
                    self?.onOldDeviceUnavailable?()
                }
            }
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isActive = false
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            }
        })
    }

    private func handleInterruption(type: AVAudioSession.InterruptionType?, options: AVAudioSession.InterruptionOptions) {
        switch type {
        case .began:
            isActive = false
            onInterruptionBegan?()
        case .ended:
            onInterruptionEnded?(options.contains(.shouldResume))
        default:
            break
        }
    }
}
