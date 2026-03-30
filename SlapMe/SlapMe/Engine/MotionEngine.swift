import Foundation
import Combine

/// Connects to SlapMeDaemon via Unix Domain Socket to receive accelerometer-based
/// slap events. If daemon isn't running, prompts user to start it with admin privileges.
final class MotionEngine: ObservableObject {
    @Published var currentForce: Double = 0.0
    @Published var isDetecting: Bool = false
    @Published var lastEventTimestamp: Date?
    @Published var comboCount: Int = 0
    @Published var detectionMethod: String = "None"
    @Published var daemonStatus: String = "Not connected"

    let forceEvent = PassthroughSubject<ForceEvent, Never>()

    private let socketPath = "/tmp/slapme.sock"
    private var socketFD: Int32 = -1
    private var readThread: Thread?
    private var comboResetTimer: Timer?
    private var isRunning = false

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
        NSLog("[MotionEngine] Starting accelerometer detection via daemon...")

        // Try to connect to existing daemon
        if connectToDaemon() {
            startReading(settings: settings)
            return
        }

        // Daemon not running — launch it with admin privileges
        NSLog("[MotionEngine] Daemon not running, launching with admin privileges...")
        launchDaemon { [weak self] success in
            if success {
                // Wait a moment for daemon to start
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if self?.connectToDaemon() == true {
                        self?.startReading(settings: settings)
                    } else {
                        NSLog("[MotionEngine] Failed to connect after launching daemon")
                        DispatchQueue.main.async {
                            self?.daemonStatus = "Failed to connect"
                        }
                    }
                }
            } else {
                NSLog("[MotionEngine] Failed to launch daemon (user cancelled?)")
                DispatchQueue.main.async {
                    self?.daemonStatus = "Not authorized"
                }
            }
        }
    }

    func stopDetection() {
        isRunning = false
        isDetecting = false
        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }
        comboResetTimer?.invalidate()
    }

    // MARK: - Daemon Connection

    private func connectToDaemon() -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
            let pathBuf = UnsafeMutableRawPointer(pathPtr).assumingMemoryBound(to: CChar.self)
            socketPath.withCString { strncpy(pathBuf, $0, 104 - 1) }
        }

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard result == 0 else {
            close(fd)
            return false
        }

        socketFD = fd
        NSLog("[MotionEngine] Connected to daemon at %@", socketPath)
        return true
    }

    private func startReading(settings: SettingsManager) {
        isRunning = true

        DispatchQueue.main.async {
            self.isDetecting = true
            self.detectionMethod = "Accelerometer"
            self.daemonStatus = "Connected"
        }

        // Read from socket in background thread
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self else { return }

            var buffer = [UInt8](repeating: 0, count: 4096)
            var lineBuffer = ""

            while self.isRunning && self.socketFD >= 0 {
                let bytesRead = read(self.socketFD, &buffer, buffer.count)
                if bytesRead <= 0 {
                    NSLog("[MotionEngine] Daemon disconnected")
                    DispatchQueue.main.async {
                        self.isDetecting = false
                        self.daemonStatus = "Disconnected"
                    }
                    break
                }

                lineBuffer += String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""

                // Process complete lines
                while let newlineIdx = lineBuffer.firstIndex(of: "\n") {
                    let line = String(lineBuffer[lineBuffer.startIndex..<newlineIdx])
                    lineBuffer = String(lineBuffer[lineBuffer.index(after: newlineIdx)...])

                    self.processEvent(line)
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

            // Decay force display
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self?.currentForce = 0
            }
        }
    }

    // MARK: - Launch Daemon

    private func launchDaemon(completion: @escaping (Bool) -> Void) {
        // Find the daemon binary — it's bundled next to the app binary
        let daemonPath = findDaemonPath()

        guard let path = daemonPath else {
            NSLog("[MotionEngine] SlapMeDaemon binary not found")
            completion(false)
            return
        }

        NSLog("[MotionEngine] Launching daemon: %@", path)

        // Use osascript to get admin privileges
        let script = "do shell script \"\\\"\(path)\\\" &\" with administrator privileges"

        DispatchQueue.global().async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", script]

            do {
                try task.run()
                task.waitUntilExit()
                let success = task.terminationStatus == 0
                DispatchQueue.main.async { completion(success) }
            } catch {
                NSLog("[MotionEngine] osascript error: %@", error.localizedDescription)
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    private func findDaemonPath() -> String? {
        // Check next to the app executable
        if let exec = Bundle.main.executableURL {
            let sameDir = exec.deletingLastPathComponent().appendingPathComponent("SlapMeDaemon")
            if FileManager.default.fileExists(atPath: sameDir.path) { return sameDir.path }

            // In Contents/MacOS/
            let macosDir = exec.deletingLastPathComponent().appendingPathComponent("SlapMeDaemon")
            if FileManager.default.fileExists(atPath: macosDir.path) { return macosDir.path }

            // In Contents/Helpers/
            let helpersDir = exec.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Helpers/SlapMeDaemon")
            if FileManager.default.fileExists(atPath: helpersDir.path) { return helpersDir.path }
        }

        // SPM build directory
        let buildPath = Bundle.main.executableURL?.deletingLastPathComponent()
            .appendingPathComponent("SlapMeDaemon")
        if let p = buildPath, FileManager.default.fileExists(atPath: p.path) { return p.path }

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
