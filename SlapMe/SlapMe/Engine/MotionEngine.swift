import Foundation
import Combine
import IOKit
import IOKit.hid
import AVFoundation

/// Detects physical slaps/taps using microphone (primary) or accelerometer (if root).
final class MotionEngine: ObservableObject {
    @Published var currentForce: Double = 0.0
    @Published var isDetecting: Bool = false
    @Published var lastEventTimestamp: Date?
    @Published var comboCount: Int = 0
    @Published var detectionMethod: String = "None"

    let forceEvent = PassthroughSubject<ForceEvent, Never>()

    private var audioEngine: AVAudioEngine?
    private var cooldownActive = false
    private var comboResetTimer: Timer?
    private var ambientLevel: Float = 0.0
    private var ambientSamples: [Float] = []

    struct ForceEvent {
        let force: Double
        let category: ForceCategory
        let timestamp: Date
        let raw: SIMD3<Double>
    }

    enum ForceCategory: String {
        case tap, hit, slap
        init(force: Double) {
            switch force {
            case 0..<0.3: self = .tap
            case 0.3..<0.7: self = .hit
            default: self = .slap
            }
        }
    }

    // MARK: - Start

    func startDetection(settings: SettingsManager) {
        guard !isDetecting else { return }
        NSLog("[MotionEngine] Starting detection...")

        // Go straight to microphone — it works on all Macs without root
        startMicrophoneDetection(settings: settings)
    }

    func stopDetection() {
        isDetecting = false
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        comboResetTimer?.invalidate()
    }

    // MARK: - Microphone Detection

    private func startMicrophoneDetection(settings: SettingsManager) {
        NSLog("[MotionEngine] Requesting mic permission...")

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            NSLog("[MotionEngine] Mic already authorized")
            beginMicDetection(settings: settings)
        case .notDetermined:
            NSLog("[MotionEngine] Mic not determined, requesting...")
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                NSLog("[MotionEngine] Mic permission result: %@", granted ? "granted" : "denied")
                if granted {
                    DispatchQueue.main.async {
                        self?.beginMicDetection(settings: settings)
                    }
                }
            }
        case .denied:
            NSLog("[MotionEngine] Mic DENIED — user needs to enable in System Settings > Privacy")
        case .restricted:
            NSLog("[MotionEngine] Mic RESTRICTED")
        @unknown default:
            NSLog("[MotionEngine] Mic unknown status")
        }
    }

    private func beginMicDetection(settings: SettingsManager) {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        NSLog("[MotionEngine] Mic format: sr=%.0f ch=%d", format.sampleRate, format.channelCount)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            NSLog("[MotionEngine] ERROR: Invalid mic format")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.processMicBuffer(buffer, settings: settings)
        }

        do {
            try engine.start()
            audioEngine = engine
            DispatchQueue.main.async {
                self.detectionMethod = "Microphone"
                self.isDetecting = true
            }
            NSLog("[MotionEngine] Mic detection STARTED")
        } catch {
            NSLog("[MotionEngine] ERROR starting mic: %@", error.localizedDescription)
        }
    }

    private func processMicBuffer(_ buffer: AVAudioPCMBuffer, settings: SettingsManager) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        // Calculate peak amplitude
        var peak: Float = 0
        var sumSquares: Float = 0
        for i in 0..<frameLength {
            let s = abs(channelData[i])
            sumSquares += s * s
            if s > peak { peak = s }
        }
        let rms = sqrt(sumSquares / Float(frameLength))

        // Update ambient baseline
        ambientSamples.append(rms)
        if ambientSamples.count > 60 { ambientSamples.removeFirst() }
        ambientLevel = ambientSamples.reduce(0, +) / Float(ambientSamples.count)

        // Spike detection
        let spikeRatio = ambientLevel > 0.0001 ? peak / ambientLevel : peak / 0.001
        let sensitivityMult = Float(0.3 + settings.sensitivity * 0.7)
        let threshold: Float = 3.0 / sensitivityMult

        guard spikeRatio > threshold else {
            // Decay force
            DispatchQueue.main.async {
                if self.currentForce > 0.01 { self.currentForce *= 0.85 }
                else { self.currentForce = 0 }
            }
            return
        }

        guard !cooldownActive else { return }

        // Normalize
        let maxRatio = threshold * 4.0
        let force = Double(min(1.0, max(0.0, (spikeRatio - threshold) / (maxRatio - threshold))))

        // Typing protection
        if settings.typingProtection && force < 0.15 {
            return
        }

        NSLog("[MotionEngine] SLAP DETECTED! force=%.2f spikeRatio=%.1f", force, spikeRatio)

        let event = ForceEvent(
            force: force,
            category: ForceCategory(force: force),
            timestamp: Date(),
            raw: SIMD3<Double>(Double(peak), Double(rms), Double(spikeRatio))
        )

        DispatchQueue.main.async {
            self.currentForce = force
            self.lastEventTimestamp = event.timestamp
            self.comboCount += 1
            self.forceEvent.send(event)
            self.startCooldown(interval: settings.cooldownInterval)
            self.resetComboAfterDelay()
        }
    }

    // MARK: - Cooldown & Combo

    private func startCooldown(interval: Double) {
        cooldownActive = true
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
            self?.cooldownActive = false
        }
    }

    private func resetComboAfterDelay() {
        comboResetTimer?.invalidate()
        comboResetTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.comboCount = 0 }
        }
    }

    // MARK: - Simulate

    func simulateForce(_ force: Double) {
        let normalized = min(1.0, max(0.0, force))
        let event = ForceEvent(
            force: normalized,
            category: ForceCategory(force: normalized),
            timestamp: Date(),
            raw: SIMD3<Double>(normalized, 0, 0)
        )

        DispatchQueue.main.async {
            self.currentForce = normalized
            self.lastEventTimestamp = event.timestamp
            self.comboCount += 1
            self.forceEvent.send(event)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.currentForce = 0
        }
    }
}
