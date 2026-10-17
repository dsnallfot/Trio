import AVFoundation
import MediaPlayer
import UIKit

/// Optional acknowledgement sound, invoked only after a successful manual bolus command.
/// Audio failures must never propagate into the insulin delivery path.
@MainActor final class ManualBolusSound {
    static let shared = ManualBolusSound()
    static let enabledKey = "Trio.manualBolusSound.enabled"
    static let volumeKey = "Trio.manualBolusSound.volume"

    private var playbackTask: Task<Void, Never>?

    private enum PlaybackError: Error {
        case missingSound
        case preparationFailed
        case playbackFailed
    }

    // Keep the invoking UI/Shortcut/APNS operation alive until audio cleanup finishes.
    // The child task isolates audio cancellation/errors from the accepted bolus.
    func playIfEnabled() async {
        guard UserDefaults.standard.bool(forKey: Self.enabledKey), playbackTask == nil else { return }
        let task = Task { await play() }
        playbackTask = task
        await task.value
    }

    private func play() async {
        let session = AVAudioSession.sharedInstance()
        let previousCategory = session.category
        let previousMode = session.mode
        let previousOptions = session.categoryOptions
        var previousVolume: Float?
        var player: AVAudioPlayer?
        var volumeView: MPVolumeView?
        var slider: UISlider?
        var sessionActivated = false
        var sessionConfigured = false
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Manual bolus acknowledgement") {
            Task { @MainActor in self.playbackTask?.cancel() }
        }
        defer {
            player?.stop()
            volumeView?.removeFromSuperview()
            if sessionActivated {
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
            }
            if sessionConfigured {
                try? session.setCategory(previousCategory, mode: previousMode, options: previousOptions)
            }
            if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
            playbackTask = nil
        }

        do {
            guard let url = Bundle.main.url(forResource: "manual_bolus_ack", withExtension: "wav") else {
                throw PlaybackError.missingSound
            }
            // Mix with existing audio when activating from a background wake.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            sessionConfigured = true
            try session.setActive(true)
            sessionActivated = true
            let audio = try AVAudioPlayer(contentsOf: url)
            player = audio
            guard audio.prepareToPlay() else {
                throw PlaybackError.preparationFailed
            }

            // Same volume-control workaround as LoopFollow; retain one view for this playback.
            let view = MPVolumeView(frame: .zero)
            volumeView = view
            view.alpha = 0.000001
            let window = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow }
            window?.addSubview(view)
            try await Task.sleep(nanoseconds: 50_000_000)
            slider = view.subviews.first { $0 is UISlider } as? UISlider
            if let slider {
                previousVolume = session.outputVolume
                let saved = UserDefaults.standard.object(forKey: Self.volumeKey) as? NSNumber
                let volume = saved?.floatValue ?? 0.5
                slider.value = volume.isFinite ? min(1, max(0.1, volume)) : 0.5
                // Let the system apply the volume before the short sound starts.
                try await Task.sleep(nanoseconds: 100_000_000)
            } else {
                warning(.service, "Manual bolus sound: volume override unavailable")
            }
            try Task.checkCancellation()
            guard audio.play() else {
                throw PlaybackError.playbackFailed
            }
            // Bound lifetime and restore volume even if playback is interrupted.
            try await Task.sleep(nanoseconds: UInt64((audio.duration + 0.15) * 1_000_000_000))
        } catch is CancellationError {
            // Still restore volume below when background time expires.
        } catch {
            let nsError = error as NSError
            warning(
                .service,
                "Manual bolus sound failed: domain=\(nsError.domain), code=\(nsError.code), \(error)"
            )
        }
        player?.stop()
        if let previousVolume, let slider {
            await restoreVolume(previousVolume, slider: slider, session: session)
        }
    }

    private func restoreVolume(
        _ volume: Float,
        slider: UISlider,
        session: AVAudioSession
    ) async {
        // MPVolumeView applies changes asynchronously. Keep it attached and the audio session
        // active until the system reports the restored volume, including after cancellation.
        for _ in 1 ... 3 {
            slider.setValue(volume, animated: false)
            slider.sendActions(for: .valueChanged)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    continuation.resume()
                }
            }
            if abs(session.outputVolume - volume) < 0.02 {
                return
            }
        }
        warning(
            .service,
            "Manual bolus sound: volume restoration unconfirmed target=\(volume), observed=\(session.outputVolume)"
        )
    }
}
