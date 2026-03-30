import Foundation
import Combine
import AppKit

/// Orchestrates the response pipeline: MotionEngine → mapping → SoundEngine + visual effects.
final class ReactionEngine: ObservableObject {
    // MARK: - Dependencies
    private let settings: SettingsManager
    private let sound: SoundEngine
    private let motion: MotionEngine

    // MARK: - State
    @Published var lastReaction: Reaction?
    private var cancellables = Set<AnyCancellable>()

    struct Reaction {
        let force: Double
        let category: MotionEngine.ForceCategory
        let soundPlayed: Bool
        let visualEffect: VisualEffect
        let timestamp: Date
    }

    enum VisualEffect {
        case none
        case menuBarBounce
        case screenFlash(intensity: Double)
        case screenShake(intensity: Double)
    }

    // MARK: - Init

    init(settings: SettingsManager, sound: SoundEngine, motion: MotionEngine) {
        self.settings = settings
        self.sound = sound
        self.motion = motion
    }

    // MARK: - Start / Stop

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

    // MARK: - Event Handling

    private func handleForceEvent(_ event: MotionEngine.ForceEvent) {
        guard settings.isEnabled else {
            NSLog("[ReactionEngine] Disabled, ignoring event")
            return
        }

        NSLog("[ReactionEngine] Force event: %.2f (%@) → playing sound", event.force, event.category.rawValue)

        // Determine visual effect based on force
        let visual = mapForceToVisual(event.force, category: event.category)

        // Play sound
        sound.play(force: event.force, volumeScale: settings.volumeScale)

        // Apply visual effect
        applyVisualEffect(visual)

        // Update stats
        settings.totalSlaps += 1

        // Record reaction
        let reaction = Reaction(
            force: event.force,
            category: event.category,
            soundPlayed: true,
            visualEffect: visual,
            timestamp: event.timestamp
        )
        lastReaction = reaction

        // Combo escalation
        if settings.activeMode == .combo && motion.comboCount >= 3 {
            applyComboEffect(comboCount: motion.comboCount, force: event.force)
        }
    }

    // MARK: - Force → Visual Mapping

    private func mapForceToVisual(_ force: Double, category: MotionEngine.ForceCategory) -> VisualEffect {
        switch category {
        case .tap:
            return .menuBarBounce
        case .hit:
            return .screenFlash(intensity: force)
        case .slap:
            return .screenShake(intensity: force)
        }
    }

    // MARK: - Visual Effects

    private func applyVisualEffect(_ effect: VisualEffect) {
        switch effect {
        case .none:
            break

        case .menuBarBounce:
            // Subtle bounce via NSApp icon badge or status item animation
            NSApp.requestUserAttention(.informationalRequest)

        case .screenFlash(let intensity):
            flashScreen(intensity: intensity)

        case .screenShake(let intensity):
            shakeScreen(intensity: intensity)
        }
    }

    private func flashScreen(intensity: Double) {
        guard let screen = NSScreen.main else { return }

        let flashWindow = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        flashWindow.level = .screenSaver
        flashWindow.backgroundColor = NSColor.white.withAlphaComponent(CGFloat(intensity * 0.3))
        flashWindow.isOpaque = false
        flashWindow.ignoresMouseEvents = true
        flashWindow.orderFront(nil)

        // Fade out
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            flashWindow.animator().alphaValue = 0
        }, completionHandler: {
            flashWindow.orderOut(nil)
        })
    }

    private func shakeScreen(intensity: Double) {
        guard let _ = NSScreen.main,
              let window = NSApp.windows.first else { return }

        let originalFrame = window.frame
        let shakeAmount = CGFloat(intensity * 8)
        let shakeDuration = 0.05
        let shakeCount = 4

        for i in 0..<shakeCount {
            let delay = Double(i) * shakeDuration
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let direction = (i % 2 == 0) ? shakeAmount : -shakeAmount
                let decay = CGFloat(1.0 - Double(i) / Double(shakeCount))
                var shakeFrame = originalFrame
                shakeFrame.origin.x += direction * decay
                window.setFrame(shakeFrame, display: false)
            }
        }

        // Reset position
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(shakeCount) * shakeDuration) {
            window.setFrame(originalFrame, display: false)
        }
    }

    private func applyComboEffect(comboCount: Int, force: Double) {
        // Escalate: each combo level adds more dramatic effects
        let escalatedForce = min(1.0, force + Double(comboCount) * 0.05)
        flashScreen(intensity: escalatedForce * 0.5)
    }
}
