import Foundation
import Combine

/// Launches the SlapHelper subprocess to read the accelerometer and receive slap events.
///
/// IOKit HID callbacks only fire under CFRunLoopRun(), NOT under NSApplication.run().
/// So we use a helper process that runs its own CFRunLoop and pipes slap events as
/// JSON lines to stdout, which we read here.
final class MotionEngine: ObservableObject {
    @Published var currentForce: Double = 0.0
    @Published var isDetecting: Bool = false
    @Published var lastEventTimestamp: Date?
    @Published var comboCount: Int = 0
    @Published var detectionMethod: String = "None"
    @Published var daemonStatus: String = "Not connected"

    let forceEvent = PassthroughSubject<ForceEvent, Never>()

    private var helperProcess: Process?
    private var comboResetTimer: Timer?

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

    // MARK: - Start / Stop

    func startDetection(settings: SettingsManager) {
        guard !isDetecting else { return }
        NSLog("[MotionEngine] Starting accelerometer detection via helper process...")

        guard let helperPath = findHelperPath() else {
            NSLog("[MotionEngine] SlapMeDaemon helper binary not found")
            DispatchQueue.main.async {
                self.daemonStatus = "Helper not found"
            }
            return
        }

        NSLog("[MotionEngine] Launching helper: %@", helperPath)
        launchHelper(path: helperPath)
    }

    func stopDetection() {
        helperProcess?.terminate()
        helperProcess = nil
        isDetecting = false
        comboResetTimer?.invalidate()
    }

    // MARK: - Helper Process

    private func launchHelper(path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        process.terminationHandler = { [weak self] proc in
            NSLog("[MotionEngine] Helper exited with status %d", proc.terminationStatus)
            DispatchQueue.main.async {
                self?.isDetecting = false
                self?.daemonStatus = "Helper stopped"
            }
        }

        do {
            try process.run()
        } catch {
            NSLog("[MotionEngine] Failed to launch helper: %@", error.localizedDescription)
            DispatchQueue.main.async {
                self.daemonStatus = "Launch failed"
            }
            return
        }

        helperProcess = process

        // Log stderr from helper
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                for line in text.split(separator: "\n") {
                    NSLog("[SlapHelper] %@", String(line))
                }
            }
        }

        // Read stdout for events
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let handle = stdoutPipe.fileHandleForReading
            var lineBuffer = ""

            while true {
                let data = handle.availableData
                if data.isEmpty { break } // EOF — helper exited

                lineBuffer += String(data: data, encoding: .utf8) ?? ""

                while let newlineIdx = lineBuffer.firstIndex(of: "\n") {
                    let line = String(lineBuffer[lineBuffer.startIndex..<newlineIdx])
                    lineBuffer = String(lineBuffer[lineBuffer.index(after: newlineIdx)...])

                    if line == "READY" {
                        NSLog("[MotionEngine] Helper is ready — accelerometer active")
                        DispatchQueue.main.async {
                            self?.isDetecting = true
                            self?.detectionMethod = "Accelerometer"
                            self?.daemonStatus = "Active"
                        }
                    } else {
                        self?.processEvent(line)
                    }
                }
            }
        }
    }

    private func processEvent(_ json: String) {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              dict["type"] as? String == "slap",
              let force = dict["force"] as? Double else { return }

        let x = dict["x"] as? Double ?? 0
        let y = dict["y"] as? Double ?? 0
        let z = dict["z"] as? Double ?? 0

        let event = ForceEvent(
            force: force,
            category: ForceCategory(force: force),
            timestamp: Date(),
            raw: SIMD3<Double>(x, y, z)
        )

        DispatchQueue.main.async { [weak self] in
            self?.currentForce = force
            self?.lastEventTimestamp = event.timestamp
            self?.comboCount += 1
            self?.forceEvent.send(event)
            self?.resetComboAfterDelay()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self?.currentForce = 0
            }
        }
    }

    // MARK: - Find Helper

    private func findHelperPath() -> String? {
        if let exec = Bundle.main.executableURL {
            let sameDir = exec.deletingLastPathComponent().appendingPathComponent("SlapMeDaemon")
            if FileManager.default.fileExists(atPath: sameDir.path) { return sameDir.path }
        }
        return nil
    }

    // MARK: - Combo

    private func resetComboAfterDelay() {
        comboResetTimer?.invalidate()
        comboResetTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.comboCount = 0 }
        }
    }

    // MARK: - Simulate (for UI testing)

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
