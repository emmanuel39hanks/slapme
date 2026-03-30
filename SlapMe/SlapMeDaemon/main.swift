/// SlapHelper — Reads the Apple Silicon accelerometer via IOKit HID and
/// outputs slap events as JSON lines to stdout. No root privileges needed.
///
/// IOKit HID callbacks only fire under CFRunLoopRun(), NOT NSApplication.run(),
/// so this runs as a helper process launched by the main app.

import Foundation
import IOKit
import IOKit.hid

// Disable output buffering
setbuf(stdout, nil)
setbuf(stderr, nil)

// MARK: - Globals (must persist for HID callback lifetime)

var buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
buf.initialize(repeating: 0, count: 64)

var sampleCount = 0
var shortTermEnergy: [Double] = []
var longTermEnergy: [Double] = []
let staWindow = 12
let ltaWindow = 200
var cooldownUntil = Date.distantPast

func readInt32LE(_ ptr: UnsafeMutablePointer<UInt8>, offset: Int) -> Int32 {
    Int32(ptr[offset]) | (Int32(ptr[offset + 1]) << 8)
        | (Int32(ptr[offset + 2]) << 16) | (Int32(ptr[offset + 3]) << 24)
}

// MARK: - Setup

let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let matching: [String: Any] = [
    kIOHIDPrimaryUsagePageKey as String: 0xFF00,
    kIOHIDPrimaryUsageKey as String: 3,
]
IOHIDManagerSetDeviceMatching(mgr, matching as CFDictionary)
IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))

guard let devices = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice> else {
    fputs("[SlapHelper] ERROR: No HID devices found\n", stderr)
    exit(1)
}

fputs("[SlapHelper] Found \(devices.count) accelerometer device(s)\n", stderr)

// Register callbacks on ALL matching devices. The FIFO device (Keyboard/Trackpad)
// sends the actual accelerometer data, but the SPU device must also be opened —
// skipping it prevents the FIFO device from delivering callbacks.
var opened = false
for dev in devices {
    let transport = IOHIDDeviceGetProperty(dev, "Transport" as CFString) as? String ?? "?"
    let product = IOHIDDeviceGetProperty(dev, "Product" as CFString) as? String ?? "Unknown"

    let result = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
    if result != kIOReturnSuccess {
        fputs("[SlapHelper] Failed to open \(product): \(result)\n", stderr)
        continue
    }

    IOHIDDeviceSetProperty(dev, "ReportInterval" as CFString, 1000 as CFNumber)

    IOHIDDeviceRegisterInputReportCallback(
        dev, buf, 64,
        { _, _, _, _, _, report, length in
            sampleCount += 1
            guard length >= 18 else { return }

            if sampleCount == 1 || sampleCount % 2000 == 0 {
                fputs("[SlapHelper] Alive: \(sampleCount) samples\n", stderr)
            }

            let x = Double(readInt32LE(report, offset: 6)) / 65536.0
            let y = Double(readInt32LE(report, offset: 10)) / 65536.0
            let z = Double(readInt32LE(report, offset: 14)) / 65536.0
            let magnitude = sqrt(x * x + y * y + z * z)
            let energy = (magnitude - 1.0) * (magnitude - 1.0)

            shortTermEnergy.append(energy)
            longTermEnergy.append(energy)
            if shortTermEnergy.count > staWindow { shortTermEnergy.removeFirst() }
            if longTermEnergy.count > ltaWindow { longTermEnergy.removeFirst() }

            guard longTermEnergy.count >= ltaWindow / 2 else { return }

            let sta = shortTermEnergy.reduce(0, +) / Double(shortTermEnergy.count)
            let lta = longTermEnergy.reduce(0, +) / Double(longTermEnergy.count)
            let ratio = lta > 0.00001 ? sta / lta : 1.0
            let deviation = abs(magnitude - 1.0)

            // STA/LTA trigger + minimum deviation
            guard ratio > 3.0, deviation > 0.15 else { return }
            guard Date() > cooldownUntil else { return }

            let force = min(1.0, max(0.1, deviation / 2.5))
            cooldownUntil = Date().addingTimeInterval(0.5)

            // JSON event to stdout — the app reads this via pipe
            print(
                "{\"type\":\"slap\",\"force\":\(String(format: "%.3f", force)),\"x\":\(String(format: "%.3f", x)),\"y\":\(String(format: "%.3f", y)),\"z\":\(String(format: "%.3f", z)),\"mag\":\(String(format: "%.3f", magnitude))}"
            )
            fputs(
                "[SlapHelper] SLAP! force=\(String(format: "%.2f", force)) mag=\(String(format: "%.3f", magnitude)) ratio=\(String(format: "%.1f", ratio))\n",
                stderr)
        }, nil)

    IOHIDDeviceScheduleWithRunLoop(dev, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    fputs("[SlapHelper] Registered: \(product) (\(transport))\n", stderr)
    opened = true
}

guard opened else {
    fputs("[SlapHelper] ERROR: Could not open any accelerometer device\n", stderr)
    exit(1)
}

// Signal readiness to parent
print("READY")

// Exit cleanly when parent dies
signal(SIGPIPE) { _ in exit(0) }

// Run the event loop — HID callbacks are delivered here
CFRunLoopRun()
