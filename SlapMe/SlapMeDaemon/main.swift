/// SlapMeDaemon — Privileged helper that reads the Apple Silicon accelerometer
/// via IOKit HID and broadcasts slap events over a Unix Domain Socket.
///
/// Must run as root: sudo SlapMeDaemon

import Foundation
import IOKit
import IOKit.hid

// MARK: - Config

let socketPath = "/tmp/slapme.sock"
let sampleRate = 100 // approximate Hz from HID reports

// MARK: - Socket Server

var clientFDs: [Int32] = []
var serverFD: Int32 = -1

func startSocketServer() {
    // Remove stale socket
    unlink(socketPath)

    serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
    guard serverFD >= 0 else {
        print("[Daemon] Failed to create socket")
        exit(1)
    }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
        let pathBuf = UnsafeMutableRawPointer(pathPtr).assumingMemoryBound(to: CChar.self)
        socketPath.withCString { strncpy(pathBuf, $0, 104 - 1) }
    }

    let bindResult = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
            bind(serverFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard bindResult == 0 else {
        print("[Daemon] Failed to bind: \(String(cString: strerror(errno)))")
        exit(1)
    }

    listen(serverFD, 5)
    chmod(socketPath, 0o777) // Allow non-root app to connect

    print("[Daemon] Listening on \(socketPath)")

    // Accept connections in background
    DispatchQueue.global().async {
        while true {
            let clientFD = accept(serverFD, nil, nil)
            if clientFD >= 0 {
                print("[Daemon] Client connected (fd=\(clientFD))")
                clientFDs.append(clientFD)
            }
        }
    }
}

func broadcast(_ message: String) {
    let data = (message + "\n").data(using: .utf8)!
    var deadFDs: [Int32] = []

    for fd in clientFDs {
        let result = data.withUnsafeBytes { ptr in
            write(fd, ptr.baseAddress!, ptr.count)
        }
        if result < 0 {
            deadFDs.append(fd)
        }
    }

    clientFDs.removeAll { deadFDs.contains($0) }
}

// MARK: - Accelerometer

var reportBuffer = [UInt8](repeating: 0, count: 64)

// STA/LTA for slap detection
var shortTermEnergy: [Double] = []
var longTermEnergy: [Double] = []
let staWindow = 12
let ltaWindow = 200
var cooldownUntil = Date.distantPast

func readInt32LE(_ ptr: UnsafeMutablePointer<UInt8>, offset: Int) -> Int32 {
    Int32(ptr[offset])
        | (Int32(ptr[offset + 1]) << 8)
        | (Int32(ptr[offset + 2]) << 16)
        | (Int32(ptr[offset + 3]) << 24)
}

func handleReport(_ report: UnsafeMutablePointer<UInt8>, length: Int) {
    guard length >= 18 else { return }

    let x = Double(readInt32LE(report, offset: 6)) / 65536.0
    let y = Double(readInt32LE(report, offset: 10)) / 65536.0
    let z = Double(readInt32LE(report, offset: 14)) / 65536.0
    let magnitude = sqrt(x * x + y * y + z * z)

    // Energy = squared deviation from gravity (~1g at rest)
    let energy = (magnitude - 1.0) * (magnitude - 1.0)

    shortTermEnergy.append(energy)
    longTermEnergy.append(energy)
    if shortTermEnergy.count > staWindow { shortTermEnergy.removeFirst() }
    if longTermEnergy.count > ltaWindow { longTermEnergy.removeFirst() }

    guard longTermEnergy.count >= ltaWindow / 2 else { return }

    let sta = shortTermEnergy.reduce(0, +) / Double(shortTermEnergy.count)
    let lta = longTermEnergy.reduce(0, +) / Double(longTermEnergy.count)

    // STA/LTA ratio — classic seismology trigger
    let ratio = lta > 0.00001 ? sta / lta : 1.0

    // Also check absolute deviation
    let deviation = abs(magnitude - 1.0)

    // Trigger conditions
    guard ratio > 3.0, deviation > 0.15 else { return }
    guard Date() > cooldownUntil else { return }

    // Normalize force: 0.15g deviation = light tap, 3g+ = hard slap
    let force = min(1.0, max(0.1, deviation / 2.5))

    cooldownUntil = Date().addingTimeInterval(0.5)

    let event = String(format: "{\"type\":\"slap\",\"force\":%.3f,\"x\":%.3f,\"y\":%.3f,\"z\":%.3f,\"mag\":%.3f}", force, x, y, z, magnitude)
    print("[Daemon] SLAP! force=\(String(format: "%.2f", force)) mag=\(String(format: "%.3f", magnitude)) ratio=\(String(format: "%.1f", ratio))")
    broadcast(event)
}

func startAccelerometer() -> Bool {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

    // Match Apple SPU accelerometer: usage page 0xFF00, usage 3
    let matching: [String: Any] = [
        kIOHIDPrimaryUsagePageKey as String: 0xFF00,
        kIOHIDPrimaryUsageKey as String: 3
    ]
    IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

    let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    guard openResult == kIOReturnSuccess else {
        print("[Daemon] HID manager open failed: \(openResult). Are you running as root (sudo)?")
        return false
    }

    guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
          let device = deviceSet.first else {
        print("[Daemon] No AppleSPUHIDDevice accelerometer found.")
        print("[Daemon] This Mac may not have the SPU sensor (need Apple Silicon M1 Pro or later)")
        return false
    }

    let deviceOpenResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    guard deviceOpenResult == kIOReturnSuccess else {
        print("[Daemon] Failed to open HID device: \(deviceOpenResult)")
        return false
    }

    print("[Daemon] Accelerometer opened successfully")

    // Register callback
    IOHIDDeviceRegisterInputReportCallback(
        device,
        &reportBuffer,
        reportBuffer.count,
        { context, result, sender, type, reportID, report, length in
            handleReport(report, length: Int(length))
        },
        nil
    )

    IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

    return true
}

// MARK: - Main

print("[Daemon] SlapMe Daemon starting...")
print("[Daemon] PID: \(ProcessInfo.processInfo.processIdentifier)")
print("[Daemon] Running as: \(NSUserName()) (uid=\(getuid()))")

guard getuid() == 0 else {
    print("[Daemon] ERROR: Must run as root. Use: sudo SlapMeDaemon")
    exit(1)
}

startSocketServer()

guard startAccelerometer() else {
    print("[Daemon] Failed to start accelerometer")
    exit(1)
}

print("[Daemon] Ready — waiting for slaps...")

// Keep the run loop alive
signal(SIGINT) { _ in
    print("\n[Daemon] Shutting down...")
    unlink(socketPath)
    if serverFD >= 0 { close(serverFD) }
    exit(0)
}

CFRunLoopRun()
