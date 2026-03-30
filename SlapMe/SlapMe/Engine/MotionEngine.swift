import Foundation
import Combine
import AVFoundation

/// Detects physical slaps using the microphone.
/// Uses a dual-threshold system: absolute peak + spike ratio above ambient.
/// Typing and gentle touches are filtered out aggressively.
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

    // Ambient noise tracking
    private var ambientPeaks: [Float] = []
    private let ambientWindowSize = 80

    // Typing filter: track recent small peaks
    private var recentPeakTimes: [Date] = []

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
        NSLog("[MotionEngine] Starting mic detection...")

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginMicDetection(settings: settings)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async { self?.beginMicDetection(settings: settings) }
                }
            }
        default:
            NSLog("[MotionEngine] Mic access denied")
        }
    }

    func stopDetection() {
        isDetecting = false
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        comboResetTimer?.invalidate()
    }

    // MARK: - Mic

    private func beginMicDetection(settings: SettingsManager) {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else { return }

        inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.processBuffer(buffer, settings: settings)
        }

        do {
            try engine.start()
            audioEngine = engine
            DispatchQueue.main.async {
                self.detectionMethod = "Microphone"
                self.isDetecting = true
            }
            NSLog("[MotionEngine] Mic started (sr=%.0f ch=%d)", format.sampleRate, format.channelCount)
        } catch {
            NSLog("[MotionEngine] Mic error: %@", error.localizedDescription)
        }
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer, settings: SettingsManager) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let len = Int(buffer.frameLength)
        guard len > 0 else { return }

        // Find peak amplitude
        var peak: Float = 0
        for i in 0..<len {
            let s = abs(channelData[i])
            if s > peak { peak = s }
        }

        // Update ambient peak baseline (rolling average of peaks)
        ambientPeaks.append(peak)
        if ambientPeaks.count > ambientWindowSize { ambientPeaks.removeFirst() }

        // Need enough samples to calibrate
        guard ambientPeaks.count >= 20 else { return }

        // Ambient level: use the median of recent peaks (robust to outliers)
        let sorted = ambientPeaks.sorted()
        let ambientMedian = sorted[sorted.count / 2]

        // ─── DUAL THRESHOLD ───
        // 1. Absolute minimum peak: must be loud enough to be a physical impact
        //    Typing is usually < 0.05, slaps are > 0.1
        let absoluteThreshold: Float = 0.08 / Float(0.5 + settings.sensitivity * 0.5)

        // 2. Relative spike: must be significantly above ambient
        let spikeRatio = ambientMedian > 0.0001 ? peak / ambientMedian : 0
        let relativeThreshold: Float = 5.0 / Float(0.5 + settings.sensitivity * 0.5)

        // Both must be met
        let isImpact = peak > absoluteThreshold && spikeRatio > relativeThreshold

        // ─── TYPING FILTER ───
        // Typing creates many rapid small-to-medium peaks. A real slap is a single
        // sharp transient followed by silence. If we see many peaks in quick
        // succession, it's typing — ignore.
        let now = Date()
        if peak > absoluteThreshold * 0.5 {
            recentPeakTimes.append(now)
        }
        recentPeakTimes = recentPeakTimes.filter { now.timeIntervalSince($0) < 0.5 }

        // If more than 4 peaks in 500ms, it's typing
        let isTyping = recentPeakTimes.count > 4

        // Decay force display
        if !isImpact {
            DispatchQueue.main.async {
                if self.currentForce > 0.01 { self.currentForce *= 0.8 }
                else { self.currentForce = 0 }
            }
            return
        }

        guard !isTyping else { return }
        guard !cooldownActive else { return }

        // Normalize force
        let maxRatio = relativeThreshold * 4.0
        let force = Double(min(1.0, max(0.1, (spikeRatio - relativeThreshold) / (maxRatio - relativeThreshold))))

        NSLog("[MotionEngine] SLAP! force=%.2f peak=%.3f ratio=%.1f ambient=%.4f", force, peak, spikeRatio, ambientMedian)

        let event = ForceEvent(
            force: force,
            category: ForceCategory(force: force),
            timestamp: now,
            raw: SIMD3<Double>(Double(peak), Double(ambientMedian), Double(spikeRatio))
        )

        DispatchQueue.main.async {
            self.currentForce = force
            self.lastEventTimestamp = event.timestamp
            self.comboCount += 1
            self.forceEvent.send(event)
            self.startCooldown(interval: max(0.5, settings.cooldownInterval))
            self.resetComboAfterDelay()
        }
    }

    // MARK: - Cooldown

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
