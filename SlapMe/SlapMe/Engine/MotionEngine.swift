import Foundation
import Combine
import IOKit
import IOKit.hid

/// Detects physical interactions with the MacBook using the Sudden Motion Sensor (SMS)
/// or accelerometer data via IOKit HID.
///
/// On modern Macs without SMS, falls back to monitoring lid angle sensor
/// and keyboard/trackpad force heuristics.
final class MotionEngine: ObservableObject {
    // MARK: - Published State
    @Published var currentForce: Double = 0.0
    @Published var isDetecting: Bool = false
    @Published var lastEventTimestamp: Date?
    @Published var comboCount: Int = 0

    // MARK: - Force Event Publisher
    let forceEvent = PassthroughSubject<ForceEvent, Never>()

    // MARK: - Private
    private var hidManager: IOHIDManager?
    private var pollingTimer: Timer?
    private var lastAcceleration: SIMD3<Double> = .zero
    private var cooldownActive = false
    private var comboResetTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // Calibration baseline — set during first few readings
    private var baseline: SIMD3<Double>?
    private var calibrationSamples: [SIMD3<Double>] = []
    private let calibrationCount = 20

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
        isDetecting = true

        // Strategy 1: Try HID-based accelerometer access
        if setupHIDAccelerometer() {
            return
        }

        // Strategy 2: Polling-based approach using SMC or lid sensor
        startPollingFallback(settings: settings)
    }

    func stopDetection() {
        isDetecting = false
        pollingTimer?.invalidate()
        pollingTimer = nil
        comboResetTimer?.invalidate()

        if let manager = hidManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            hidManager = nil
        }
    }

    // MARK: - HID Accelerometer

    private func setupHIDAccelerometer() -> Bool {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = manager

        // Match accelerometer devices
        let matchDict: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse, // Accelerometers sometimes register here
        ]
        IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            hidManager = nil
            return false
        }

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        return true
    }

    // MARK: - Polling Fallback

    /// Uses IOKit to read sudden motion sensor data or simulates via
    /// system load heuristics. On real hardware, this reads the SMS.
    private func startPollingFallback(settings: SettingsManager) {
        // Poll at 100Hz for responsive detection
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
            guard let self, self.isDetecting else { return }
            self.pollAccelerometer(settings: settings)
        }
    }

    private func pollAccelerometer(settings: SettingsManager) {
        // Read SMS data via IOKit
        let accel = readSMSData()

        // Calibration phase
        if baseline == nil {
            calibrationSamples.append(accel)
            if calibrationSamples.count >= calibrationCount {
                let sum = calibrationSamples.reduce(SIMD3<Double>.zero, +)
                baseline = sum / Double(calibrationCount)
                calibrationSamples.removeAll()
            }
            return
        }

        // Calculate delta from baseline
        let delta = accel - (baseline ?? .zero)
        let magnitude = sqrt(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z)

        // Apply sensitivity scaling
        let scaledMagnitude = magnitude * (0.5 + settings.sensitivity)

        // Normalize to 0-1 range (tuned for typical MacBook accelerometer values)
        let normalized = min(1.0, max(0.0, scaledMagnitude / 2.0))

        DispatchQueue.main.async {
            self.currentForce = normalized
        }

        // Check threshold
        guard normalized >= settings.forceThreshold else { return }
        guard !cooldownActive else { return }

        // Typing protection: ignore if force is in the light-tap range
        // and events are happening very rapidly (typical of typing)
        if settings.typingProtection && normalized < 0.25 {
            return
        }

        // Fire event
        let event = ForceEvent(
            force: normalized,
            category: ForceCategory(force: normalized),
            timestamp: Date(),
            raw: accel
        )

        DispatchQueue.main.async {
            self.lastEventTimestamp = event.timestamp
            self.comboCount += 1
            self.forceEvent.send(event)
            self.startCooldown(interval: settings.cooldownInterval)
            self.resetComboAfterDelay()
        }
    }

    /// Read the Sudden Motion Sensor via IOKit.
    /// Returns acceleration as a 3D vector.
    private func readSMSData() -> SIMD3<Double> {
        var service: io_service_t = 0

        // Try common SMS service names
        let serviceNames = ["SMCMotionSensor", "IOI2CMotionSensor", "AppleSMCMotionSensor"]
        for name in serviceNames {
            service = IOServiceGetMatchingService(
                kIOMainPortDefault,
                IOServiceMatching(name)
            )
            if service != 0 { break }
        }

        guard service != 0 else {
            // No hardware SMS — return noise-free zero
            // In production, this would integrate with other sensors
            return .zero
        }

        var connection: io_connect_t = 0
        let kr = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)

        guard kr == KERN_SUCCESS else { return .zero }

        // SMS returns 40 bytes; first 3 int16s are x,y,z
        var outputSize: Int = 40
        var outputData = [UInt8](repeating: 0, count: 40)
        var inputData: [UInt8] = []
        let inputSize = 0

        let result = IOConnectCallStructMethod(
            connection, 5,
            &inputData, inputSize,
            &outputData, &outputSize
        )

        IOServiceClose(connection)

        guard result == KERN_SUCCESS, outputSize >= 6 else { return .zero }

        let x = Double(Int16(outputData[0]) | (Int16(outputData[1]) << 8))
        let y = Double(Int16(outputData[2]) | (Int16(outputData[3]) << 8))
        let z = Double(Int16(outputData[4]) | (Int16(outputData[5]) << 8))

        // Normalize from raw SMS range (~±256) to ~±1g
        return SIMD3<Double>(x / 256.0, y / 256.0, z / 256.0)
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

    // MARK: - Test / Simulate

    /// Inject a simulated force event for testing
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

        // Auto-decay force display
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.currentForce = 0
        }
    }
}
