import Foundation
import AVFoundation
import Combine

/// Simple sound engine using AVAudioPlayer. No format conversion needed.
final class SoundEngine: ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var availableSounds: [SoundItem] = []
    @Published var selectedSound: String = "" {
        didSet {
            UserDefaults.standard.set(selectedSound, forKey: "selectedSound")
        }
    }

    private var player: AVAudioPlayer?

    struct SoundItem: Identifiable, Hashable {
        let id: String
        let name: String
        let path: URL
    }

    // Compat stubs for ReactionEngine
    struct SoundPackMeta: Identifiable { let id: String; let name: String; let author: String; let description: String; let path: URL }
    var availablePacks: [SoundPackMeta] { [] }
    enum ForceRange: String, CaseIterable { case soft, medium, hard }

    init() {
        scanSounds()
        selectedSound = UserDefaults.standard.string(forKey: "selectedSound") ?? ""
    }

    // MARK: - Scan

    func scanSounds() {
        var items: [SoundItem] = []
        let bundleName = "SlapMe_SlapMe.bundle"
        let subPath = "SoundPacks/default"

        var searchPaths: [URL] = []

        // SPM build: Bundle.module
        if let p = Bundle.module.resourceURL?.appendingPathComponent(subPath) {
            searchPaths.append(p)
        }

        // .app bundle: Contents/Resources/<bundle>/
        if let exec = Bundle.main.executableURL {
            let contentsDir = exec.deletingLastPathComponent().deletingLastPathComponent()
            searchPaths.append(contentsDir.appendingPathComponent("Resources/\(bundleName)/\(subPath)"))
        }

        // Main bundle resource URL
        if let p = Bundle.main.resourceURL?.appendingPathComponent("\(bundleName)/\(subPath)") {
            searchPaths.append(p)
        }

        // App root
        searchPaths.append(Bundle.main.bundleURL.appendingPathComponent("\(bundleName)/\(subPath)"))

        // User's Application Support
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            searchPaths.append(appSupport.appendingPathComponent("SlapMe/\(subPath)"))
        }

        for basePath in searchPaths {
            guard FileManager.default.fileExists(atPath: basePath.path),
                  let files = try? FileManager.default.contentsOfDirectory(at: basePath, includingPropertiesForKeys: nil)
            else { continue }

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

        DispatchQueue.main.async {
            self.availableSounds = items
            if self.selectedSound.isEmpty || !items.contains(where: { $0.id == self.selectedSound }) {
                self.selectedSound = items.first?.id ?? ""
            }
        }
    }

    func preloadCurrentPack(settings: SettingsManager) {
        // compat — sounds are loaded on play
    }

    // MARK: - Play

    /// Play the currently selected sound
    func playSelected(volume: Float = 1.0) {
        guard let item = availableSounds.first(where: { $0.id == selectedSound }) else {
            NSLog("[SoundEngine] No sound selected")
            return
        }
        playFile(url: item.path, volume: volume)
    }

    /// Play a specific sound by ID
    func playSound(id: String, volume: Float = 1.0) {
        guard let item = availableSounds.first(where: { $0.id == id }) else { return }
        playFile(url: item.path, volume: volume)
    }

    private func playFile(url: URL, volume: Float) {
        do {
            player?.stop()
            player = try AVAudioPlayer(contentsOf: url)
            player?.volume = volume
            player?.prepareToPlay()
            player?.play()

            DispatchQueue.main.async { self.isPlaying = true }

            let duration = player?.duration ?? 1.0
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                self?.isPlaying = false
            }

            NSLog("[SoundEngine] Playing: %@", url.lastPathComponent)
        } catch {
            NSLog("[SoundEngine] ERROR playing %@: %@", url.lastPathComponent, error.localizedDescription)
        }
    }

    // Legacy API for ReactionEngine
    func play(force: Double, volumeScale: Double) {
        playSelected(volume: Float(volumeScale))
    }

    func preview(range: ForceRange) {
        playSelected(volume: 0.8)
    }
}
