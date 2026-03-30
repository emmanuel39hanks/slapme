import Foundation
import Combine
import AVFoundation

/// Detects physical slaps/taps on the MacBook using the built-in microphone.
///
/// The mic picks up impact vibrations transmitted through the chassis.
/// We analyze audio amplitude in real-time to detect sudden spikes
/// that indicate physical contact (vs. ambient noise or speech).
final class MotionEngine: ObservableObject {
    // MARK: - Published State
    @Published var currentForce: Double = 0.0
    @Published var isDetecting: Bool = false
    @Published var lastEventTimestamp: Date?
    @Published var comboCount: Int = 0

    // MARK: - Force Event Publisher
    let forceEvent = PassthroughSubject<ForceEvent, Never>()

    // MARK: - Private
    private var audioEngine: AVAudioEngine?
    private var cooldownActive = false
    private var comboResetTimer: Timer?

    // Rolling baseline for ambient noise level
    private var ambientLevel: Float = 0.0
    private var ambientSamples: [Float] = []
    private let ambientWindowSize = 60  // ~1 second at 60fps tap node callback

    // Impact detection parameters
    private var lastPeakTime: Date = .distantPast

    struct ForceEvent {
        let force: Double       // 0.0 - 1.0 normalized
        let category: ForceCategory
        let timestamp: Date
        let raw: SIMD3<Double>
    }

    enum ForceCategory: String {
        case tap = "tap"
        case hit = "hit"
        case slap = "slap"

        init(force: Double) {
            switch force {
            case 0..<0.3: self = .tap
            case 0.3..<0.7: self = .hit
            default: self = .slap
            }
        }
    }

    // MARK: - Lifecycle

    func startDetection(settings: SettingsManager) {
        guard !isDetecting else { return }

        // Request mic permission
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginAudioDetection(settings: settings)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.beginAudioDetection(settings: settings)
                    }
                }
            }
        default:
            print("[MotionEngine] Microphone access denied")
        }
    }

    func stopDetection() {
        isDetecting = false
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        comboResetTimer?.invalidate()
    }

    // MARK: - Audio-Based Detection

    private func beginAudioDetection(settings: SettingsManager) {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            print("[MotionEngine] Invalid audio format")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, settings: settings)
        }

        do {
            try engine.start()
            audioEngine = engine
            DispatchQueue.main.async {
                self.isDetecting = true
            }
        } catch {
            print("[MotionEngine] Failed to start audio engine: \(error)")
        }
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, settings: SettingsManager) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        // Calculate RMS (root mean square) of the buffer
        var sumSquares: Float = 0
        var peak: Float = 0
        for i in 0..<frameLength {
            let sample = abs(channelData[i])
            sumSquares += sample * sample
            if sample > peak { peak = sample }
        }
        let rms = sqrt(sumSquares / Float(frameLength))

        // Update ambient noise baseline (slow-moving average)
        ambientSamples.append(rms)
        if ambientSamples.count > ambientWindowSize {
            ambientSamples.removeFirst()
        }
        ambientLevel = ambientSamples.reduce(0, +) / Float(ambientSamples.count)

        // Impact detection: look for sudden spikes above ambient
        // A physical slap creates a sharp transient that's 3-10x above ambient
        let spikeRatio = ambientLevel > 0.0001 ? peak / ambientLevel : peak / 0.001
        let sensitivityMultiplier = Float(0.3 + settings.sensitivity * 0.7)

        // Threshold: spike must be significantly above ambient
        let threshold: Float = 4.0 / sensitivityMultiplier  // Higher sensitivity = lower threshold

        guard spikeRatio > threshold else {
            // Decay force display smoothly
            DispatchQueue.main.async {
                if self.currentForce > 0.01 {
                    self.currentForce *= 0.85
                } else {
                    self.currentForce = 0
                }
            }
            return
        }

        // Normalize force: map spike ratio to 0-1
        // threshold..threshold*4 → 0..1
        let maxRatio = threshold * 5.0
        let normalizedForce = Double(min(1.0, max(0.0, (spikeRatio - threshold) / (maxRatio - threshold))))

        guard !cooldownActive else {
            DispatchQueue.main.async {
                self.currentForce = normalizedForce
            }
            return
        }

        // Typing protection: very light taps in rapid succession are likely typing
        if settings.typingProtection {
            let timeSinceLast = Date().timeIntervalSince(lastPeakTime)
            if normalizedForce < 0.2 && timeSinceLast < 0.15 {
                return
            }
        }

        lastPeakTime = Date()

        let event = ForceEvent(
            force: normalizedForce,
            category: ForceCategory(force: normalizedForce),
            timestamp: Date(),
            raw: SIMD3<Double>(Double(peak), Double(rms), Double(spikeRatio))
        )

        DispatchQueue.main.async {
            self.currentForce = normalizedForce
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
            DispatchQueue.main.async {
                self?.comboCount = 0
            }
        }
    }

    // MARK: - Simulate

    /// Inject a simulated force event for testing / sound board buttons
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
