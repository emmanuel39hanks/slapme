import Foundation
import Combine
import IOKit
import IOKit.hid
import AVFoundation

/// Detects physical slaps/taps on Apple Silicon MacBooks using the built-in
/// MEMS accelerometer (AppleSPUHIDDevice) via IOKit HID.
///
/// Falls back to microphone-based detection if accelerometer is unavailable
/// (Intel Macs, base M1, or insufficient permissions).
final class MotionEngine: ObservableObject {
    // MARK: - Published State
    @Published var currentForce: Double = 0.0
    @Published var isDetecting: Bool = false
    @Published var lastEventTimestamp: Date?
    @Published var comboCount: Int = 0
    @Published var detectionMethod: DetectionMethod = .none

    enum DetectionMethod: String {
        case none = "None"
        case accelerometer = "Accelerometer"
        case microphone = "Microphone"
    }

    // MARK: - Force Event Publisher
    let forceEvent = PassthroughSubject<ForceEvent, Never>()

    // MARK: - Private
    private var hidDevice: IOHIDDevice?
    private var reportBuffer = [UInt8](repeating: 0, count: 64)
    private var audioEngine: AVAudioEngine?

    private var cooldownActive = false
    private var comboResetTimer: Timer?

    // STA/LTA (Short-Term Average / Long-Term Average) for spike detection
    private var shortTermSamples: [Double] = []
    private var longTermSamples: [Double] = []
    private let staWindow = 15    // ~0.15s at 100Hz
    private let ltaWindow = 200   // ~2s at 100Hz
    private var restMagnitude: Double = 1.0  // gravity baseline

    // Mic fallback
    private var ambientLevel: Float = 0.0
    private var ambientSamples: [Float] = []

    struct ForceEvent {
        let force: Double
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

        // Try accelerometer first (Apple Silicon M1 Pro+)
        if startAccelerometer(settings: settings) {
            DispatchQueue.main.async {
                self.detectionMethod = .accelerometer
                self.isDetecting = true
            }
            return
        }

        // Fallback: microphone-based detection
        startMicrophoneDetection(settings: settings)
    }

    func stopDetection() {
        isDetecting = false

        // Stop accelerometer
        if let device = hidDevice {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            hidDevice = nil
        }

        // Stop mic
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        comboResetTimer?.invalidate()
    }

    // MARK: - Accelerometer (Apple Silicon)

    private func startAccelerometer(settings: SettingsManager) -> Bool {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        // Match AppleSPUHIDDevice accelerometer: vendor usage page 0xFF00, usage 3
        let matching: [String: Any] = [
            kIOHIDPrimaryUsagePageKey as String: 0xFF00,
            kIOHIDPrimaryUsageKey as String: 3
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            print("[MotionEngine] HID manager open failed (\(openResult)) — need root for accelerometer")
            return false
        }

        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let device = deviceSet.first else {
            print("[MotionEngine] No AppleSPUHIDDevice accelerometer found")
            return false
        }

        let deviceResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard deviceResult == kIOReturnSuccess else {
            print("[MotionEngine] Device open failed (\(deviceResult))")
            return false
        }

        hidDevice = device

        // Register HID input report callback
        let context = Unmanaged.passUnretained(self).toOpaque()
        reportBuffer = [UInt8](repeating: 0, count: 64)

        withUnsafeMutablePointer(to: &reportBuffer[0]) { ptr in
            IOHIDDeviceRegisterInputReportCallback(
                device, ptr, 64,
                { context, result, sender, type, reportID, report, length in
                    guard let ctx = context else { return }
                    let engine = Unmanaged<MotionEngine>.fromOpaque(ctx).takeUnretainedValue()
                    engine.handleAccelReport(report, length: Int(length))
                },
                context
            )
        }

        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        print("[MotionEngine] Accelerometer started (Apple Silicon SPU)")
        return true
    }

    /// Parse HID report: x/y/z are Int32 LE at byte offsets 6, 10, 14.
    /// Divide by 65536 to get values in g.
    private func handleAccelReport(_ report: UnsafeMutablePointer<UInt8>, length: Int) {
        guard length >= 18 else { return }

        let x = readInt32LE(report, offset: 6)
        let y = readInt32LE(report, offset: 10)
        let z = readInt32LE(report, offset: 14)

        let gx = Double(x) / 65536.0
        let gy = Double(y) / 65536.0
        let gz = Double(z) / 65536.0
        let magnitude = sqrt(gx * gx + gy * gy + gz * gz)

        // STA/LTA spike detection
        shortTermSamples.append(magnitude)
        longTermSamples.append(magnitude)
        if shortTermSamples.count > staWindow { shortTermSamples.removeFirst() }
        if longTermSamples.count > ltaWindow { longTermSamples.removeFirst() }

        guard longTermSamples.count >= ltaWindow / 2 else {
            // Still calibrating
            restMagnitude = longTermSamples.reduce(0, +) / Double(longTermSamples.count)
            return
        }

        let sta = shortTermSamples.reduce(0, +) / Double(shortTermSamples.count)
        let lta = longTermSamples.reduce(0, +) / Double(longTermSamples.count)

        // Deviation from rest (gravity ~1g)
        let deviation = abs(magnitude - lta)
        let ratio = lta > 0.001 ? sta / lta : 1.0

        // Normalize force: deviation of 0.5g = light tap, 3g+ = hard slap
        let normalizedForce = min(1.0, max(0.0, deviation / 3.0))

        DispatchQueue.main.async {
            self.currentForce = normalizedForce
        }

        // Trigger threshold (STA/LTA ratio)
        guard ratio > 1.3, deviation > 0.15 else { return }
        guard !cooldownActive else { return }

        let event = ForceEvent(
            force: normalizedForce,
            category: ForceCategory(force: normalizedForce),
            timestamp: Date(),
            raw: SIMD3<Double>(gx, gy, gz)
        )

        DispatchQueue.main.async {
            self.lastEventTimestamp = event.timestamp
            self.comboCount += 1
            self.forceEvent.send(event)
            self.startCooldown(interval: 0.3)
            self.resetComboAfterDelay()
        }
    }

    private func readInt32LE(_ ptr: UnsafeMutablePointer<UInt8>, offset: Int) -> Int32 {
        return Int32(ptr[offset])
            | (Int32(ptr[offset + 1]) << 8)
            | (Int32(ptr[offset + 2]) << 16)
            | (Int32(ptr[offset + 3]) << 24)
    }

    // MARK: - Microphone Fallback

    private func startMicrophoneDetection(settings: SettingsManager) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginMicDetection(settings: settings)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.beginMicDetection(settings: settings)
                    }
                }
            }
        default:
            print("[MotionEngine] Mic access denied")
        }
    }

    private func beginMicDetection(settings: SettingsManager) {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else { return }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.processMicBuffer(buffer, settings: settings)
        }

        do {
            try engine.start()
            audioEngine = engine
            DispatchQueue.main.async {
                self.detectionMethod = .microphone
                self.isDetecting = true
            }
        } catch {
            print("[MotionEngine] Mic engine failed: \(error)")
        }
    }

    private func processMicBuffer(_ buffer: AVAudioPCMBuffer, settings: SettingsManager) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        var peak: Float = 0
        var sumSquares: Float = 0
        for i in 0..<frameLength {
            let s = abs(channelData[i])
            sumSquares += s * s
            if s > peak { peak = s }
        }
        let rms = sqrt(sumSquares / Float(frameLength))

        ambientSamples.append(rms)
        if ambientSamples.count > 60 { ambientSamples.removeFirst() }
        ambientLevel = ambientSamples.reduce(0, +) / Float(ambientSamples.count)

        let spikeRatio = ambientLevel > 0.0001 ? peak / ambientLevel : peak / 0.001
        let threshold: Float = 4.0 / Float(0.3 + settings.sensitivity * 0.7)

        guard spikeRatio > threshold else {
            DispatchQueue.main.async {
                if self.currentForce > 0.01 { self.currentForce *= 0.85 }
                else { self.currentForce = 0 }
            }
            return
        }

        let maxRatio = threshold * 5.0
        let force = Double(min(1.0, max(0.0, (spikeRatio - threshold) / (maxRatio - threshold))))
        guard !cooldownActive else { return }

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
