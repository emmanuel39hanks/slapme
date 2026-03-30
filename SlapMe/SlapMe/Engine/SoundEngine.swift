import Foundation
import AppKit
import Combine

/// Sound engine using NSSound — immune to AVAudioEngine conflicts,
/// works with hardened runtime, no format conversion needed.
final class SoundEngine: ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var availableSounds: [SoundItem] = []
    @Published var selectedSound: String = "" {
        didSet {
            UserDefaults.standard.set(selectedSound, forKey: "selectedSound")
        }
    }

    private var currentSound: NSSound?
    private var preloadedSounds: [String: NSSound] = [:]

    struct SoundItem: Identifiable, Hashable {
        let id: String
        let name: String
        let path: URL
    }

    // Compat stubs
    struct SoundPackMeta: Identifiable { let id: String; let name: String; let author: String; let description: String; let path: URL }
    var availablePacks: [SoundPackMeta] { [] }
    enum ForceRange: String, CaseIterable { case soft, medium, hard }

    init() {
        scanSounds()
        selectedSound = UserDefaults.standard.string(forKey: "selectedSound") ?? ""
    }

    // MARK: - Scan (no Bundle.module — search explicitly)

    func scanSounds() {
        var items: [SoundItem] = []
        let bundleName = "SlapMe_SlapMe.bundle"
        let subPath = "SoundPacks/default"

        // Build all candidate paths — order matters, first match wins
        var searchPaths: [URL] = []

        // 1. .app bundle: Contents/Resources/Sounds/ (flat directory)
        if let resURL = Bundle.main.resourceURL {
            searchPaths.append(resURL.appendingPathComponent("Sounds"))
            searchPaths.append(resURL.appendingPathComponent("\(bundleName)/\(subPath)"))
            searchPaths.append(resURL.appendingPathComponent(subPath))
        }

        // 2. Relative to executable (Contents/MacOS → Contents/Resources)
        if let exec = Bundle.main.executableURL {
            let contents = exec.deletingLastPathComponent().deletingLastPathComponent()
            searchPaths.append(contents.appendingPathComponent("Resources/\(bundleName)/\(subPath)"))
        }

        // 3. Next to the executable (SPM swift build puts bundle here)
        if let exec = Bundle.main.executableURL {
            searchPaths.append(exec.deletingLastPathComponent().appendingPathComponent("\(bundleName)/\(subPath)"))
        }

        // 4. Bundle.main root (fallback)
        searchPaths.append(Bundle.main.bundleURL.appendingPathComponent("\(bundleName)/\(subPath)"))

        // 5. User's Application Support
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            searchPaths.append(appSupport.appendingPathComponent("SlapMe/\(subPath)"))
        }

        for basePath in searchPaths {
            guard FileManager.default.fileExists(atPath: basePath.path) else { continue }
            guard let files = try? FileManager.default.contentsOfDirectory(at: basePath, includingPropertiesForKeys: nil) else { continue }

            NSLog("[SoundEngine] Found sounds at: %@", basePath.path)

            for file in files {
                let ext = file.pathExtension.lowercased()
                guard ["mp3", "wav", "m4a", "aac"].contains(ext) else { continue }
                let filename = file.lastPathComponent
                let name = file.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "_", with: " ").capitalized

                if !items.contains(where: { $0.id == filename }) {
                    items.append(SoundItem(id: filename, name: name, path: file))
                }
            }
            if !items.isEmpty { break }
        }

        NSLog("[SoundEngine] Loaded %d sounds: %@", items.count, items.map(\.name).joined(separator: ", "))

        // Set synchronously first so preloadAll works immediately after
        self.availableSounds = items
        if self.selectedSound.isEmpty || !items.contains(where: { $0.id == self.selectedSound }) {
            self.selectedSound = items.first?.id ?? ""
        }

        // Preload into memory
        for item in items {
            if let s = NSSound(contentsOf: item.path, byReference: true) {
                preloadedSounds[item.id] = s
            }
        }
        NSLog("[SoundEngine] Preloaded %d sounds into memory", preloadedSounds.count)
    }

    func preloadCurrentPack(settings: SettingsManager) {
        // no-op — NSSound loads on play
    }

    // MARK: - Playback via NSSound

    func playSelected(volume: Float = 1.0) {
        guard let item = availableSounds.first(where: { $0.id == selectedSound }) else {
            NSLog("[SoundEngine] No sound selected, available: %@", availableSounds.map(\.id).joined(separator: ", "))
            return
        }
        playFile(url: item.path, volume: volume)
    }

    func playSound(id: String, volume: Float = 1.0) {
        guard let item = availableSounds.first(where: { $0.id == id }) else {
            NSLog("[SoundEngine] Sound '%@' not found", id)
            return
        }
        playFile(url: item.path, volume: volume)
    }

    /// Preload all sounds into memory so playback is instant
    func preloadAll() {
        for item in availableSounds {
            if let s = NSSound(contentsOf: item.path, byReference: true) {
                preloadedSounds[item.id] = s
            }
        }
        NSLog("[SoundEngine] Preloaded %d sounds", preloadedSounds.count)
    }

    private func playFile(url: URL, volume: Float) {
        let filename = url.lastPathComponent

        // Use preloaded copy (make a fresh copy so we can play overlapping)
        let sound: NSSound?
        if let preloaded = preloadedSounds[filename] {
            sound = preloaded.copy() as? NSSound
        } else {
            sound = NSSound(contentsOf: url, byReference: true)
        }

        guard let s = sound else {
            NSLog("[SoundEngine] FAILED to load: %@", url.path)
            return
        }

        // Stop previous only if same sound
        currentSound?.stop()

        s.volume = volume
        s.play()
        currentSound = s

        NSLog("[SoundEngine] Playing: %@", filename)

        DispatchQueue.main.async { self.isPlaying = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + s.duration) { [weak self] in
            self?.isPlaying = false
        }
    }

    // Legacy API
    func play(force: Double, volumeScale: Double) {
        playSelected(volume: Float(volumeScale))
    }

    func preview(range: ForceRange) {
        playSelected(volume: 0.8)
    }
}
