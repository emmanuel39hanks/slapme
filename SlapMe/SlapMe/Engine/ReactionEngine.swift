import Foundation
import Combine
import AppKit

/// Orchestrates: MotionEngine → SoundEngine + overlay.
/// Kept simple — no screen shake or flash (those were crashing the app).
final class ReactionEngine: ObservableObject {
    private let settings: SettingsManager
    private let sound: SoundEngine
    private let motion: MotionEngine
    private var cancellables = Set<AnyCancellable>()

    init(settings: SettingsManager, sound: SoundEngine, motion: MotionEngine) {
        self.settings = settings
        self.sound = sound
        self.motion = motion
    }

    func start() {
        motion.startDetection(settings: settings)

        motion.forceEvent
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleForceEvent(event)
            }
            .store(in: &cancellables)
    }

    func stop() {
        motion.stopDetection()
        cancellables.removeAll()
    }

    private func handleForceEvent(_ event: MotionEngine.ForceEvent) {
        guard settings.isEnabled else { return }

        NSLog("[ReactionEngine] SLAP %.2f → playing sound", event.force)

        // Play sound
        sound.play(force: event.force, volumeScale: settings.volumeScale)

        // Show overlay
        SlapOverlayManager.shared.showSlap(force: event.force)

        // Update stats
        settings.totalSlaps += 1
    }
}
