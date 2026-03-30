import Foundation
import AVFoundation
import Combine

/// Sound engine that lets users pick a specific sound to play on slap.
/// Uses AVAudioEngine for low-latency playback.
final class SoundEngine: ObservableObject {
    // MARK: - Published
    @Published var isPlaying: Bool = false
    @Published var availableSounds: [SoundItem] = []
    @Published var selectedSound: String = "" {
        didSet {
            UserDefaults.standard.set(selectedSound, forKey: "selectedSound")
            preloadSelected()
        }
    }

    // MARK: - Audio
    private let audioEngine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var selectedBuffer: AVAudioPCMBuffer?
    private var engineFormat: AVAudioFormat!

    struct SoundItem: Identifiable, Hashable {
        let id: String      // filename
        let name: String    // display name
        let path: URL
    }

    // Kept for API compat with ReactionEngine
    struct SoundPack: Codable {
        let name: String
        let author: String
        let version: String
        let description: String
        let sounds: SoundCategories
    }
    struct SoundCategories: Codable {
        let soft: [String]
        let medium: [String]
        let hard: [String]
    }
    struct SoundPackMeta: Identifiable {
        let id: String
        let name: String
        let author: String
        let description: String
        let path: URL
    }
    var availablePacks: [SoundPackMeta] { [] }
    enum ForceRange: String, CaseIterable {
        case soft, medium, hard
        init(force: Double) {
            switch force {
            case 0..<0.3: self = .soft
            case 0.3..<0.7: self = .medium
            default: self = .hard
            }
        }
    }

    // MARK: - Init

    init() {
        setupAudioEngine()
        scanSounds()
        selectedSound = UserDefaults.standard.string(forKey: "selectedSound") ?? ""
    }

    private func setupAudioEngine() {
        engineFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)
            ?? audioEngine.outputNode.inputFormat(forBus: 0)

        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: engineFormat)

        do {
            try audioEngine.start()
        } catch {
            print("[SoundEngine] Failed to start: \(error)")
        }
    }

    // MARK: - Scan sounds

    func scanSounds() {
        var items: [SoundItem] = []

        // Search everywhere the resource bundle could be
        let bundleName = "SlapMe_SlapMe.bundle"
        let subPath = "SoundPacks/default"

        var searchPaths: [URL] = []

        // 1. Bundle.module (works when running from swift build)
        if let p = Bundle.module.resourceURL?.appendingPathComponent(subPath) { searchPaths.append(p) }

        // 2. Inside .app/Contents/Resources/<bundle>/
        if let p = Bundle.main.resourceURL?.appendingPathComponent("\(bundleName)/\(subPath)") { searchPaths.append(p) }

        // 3. Next to executable (swift build)
        let execURL = Bundle.main.executableURL?.deletingLastPathComponent()
        if let p = execURL?.appendingPathComponent("\(bundleName)/\(subPath)") { searchPaths.append(p) }

        // 3b. Contents/Resources from Contents/MacOS (proper .app bundle)
        if let p = execURL?.deletingLastPathComponent()
            .appendingPathComponent("Resources/\(bundleName)/\(subPath)") { searchPaths.append(p) }

        // 4. .app root (fallback)
        let appRoot = Bundle.main.bundleURL.appendingPathComponent("\(bundleName)/\(subPath)")
        searchPaths.append(appRoot)

        // 5. Direct in Resources
        if let p = Bundle.main.resourceURL?.appendingPathComponent(subPath) { searchPaths.append(p) }

        // 6. User's Application Support
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            searchPaths.append(appSupport.appendingPathComponent("SlapMe/\(subPath)"))
        }

        for basePath in searchPaths {
            guard FileManager.default.fileExists(atPath: basePath.path) else { continue }
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: basePath, includingPropertiesForKeys: nil
            ) else { continue }

            print("[SoundEngine] Scanning: \(basePath.path)")

            for file in files {
                let ext = file.pathExtension.lowercased()
                guard ext == "mp3" || ext == "wav" || ext == "m4a" else { continue }

                let filename = file.lastPathComponent
                let displayName = file.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "_", with: " ")
                    .capitalized

                if !items.contains(where: { $0.id == filename }) {
                    items.append(SoundItem(id: filename, name: displayName, path: file))
                }
            }

            if !items.isEmpty { break }  // Found sounds, stop searching
        }

        print("[SoundEngine] Found \(items.count) sounds: \(items.map(\.name))")

        DispatchQueue.main.async {
            self.availableSounds = items
            if self.selectedSound.isEmpty, let first = items.first {
                self.selectedSound = first.id
            }
        }
    }

    // MARK: - Preload

    private func preloadSelected() {
        guard let item = availableSounds.first(where: { $0.id == selectedSound }) else {
            print("[SoundEngine] Sound '\(selectedSound)' not found")
            return
        }
        selectedBuffer = loadBuffer(from: item.path)
        print("[SoundEngine] Preloaded: \(item.name) (\(selectedBuffer != nil ? "OK" : "FAILED"))")
    }

    func preloadCurrentPack(settings: SettingsManager) {
        // Compat shim — just preload selected
        if selectedSound.isEmpty, let first = availableSounds.first {
            selectedSound = first.id
        }
        preloadSelected()
    }

    // MARK: - Load buffer

    private func loadBuffer(from url: URL) -> AVAudioPCMBuffer? {
        guard let audioFile = try? AVAudioFile(forReading: url) else {
            print("[SoundEngine] Can't read: \(url.lastPathComponent)")
            return nil
        }

        // Convert to engine format if needed
        if audioFile.processingFormat.channelCount == engineFormat.channelCount
            && audioFile.processingFormat.sampleRate == engineFormat.sampleRate {
            let frameCount = AVAudioFrameCount(audioFile.length)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frameCount) else {
                return nil
            }
            try? audioFile.read(into: buffer)
            return buffer
        }

        guard let converter = AVAudioConverter(from: audioFile.processingFormat, to: engineFormat) else {
            return nil
        }
        let ratio = engineFormat.sampleRate / audioFile.processingFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(audioFile.length) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: engineFormat, frameCapacity: outputFrameCount),
              let inputBuffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: AVAudioFrameCount(audioFile.length)) else {
            return nil
        }

        try? audioFile.read(into: inputBuffer)
        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }
        return error == nil ? outputBuffer : nil
    }

    // MARK: - Play

    /// Play the selected sound
    func playSelected(volume: Float = 1.0) {
        guard let buffer = selectedBuffer else {
            print("[SoundEngine] No buffer loaded")
            return
        }

        if playerNode.isPlaying {
            playerNode.stop()
        }

        playerNode.volume = min(1.0, max(0.1, volume))
        playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts)
        playerNode.play()

        DispatchQueue.main.async { self.isPlaying = true }

        let duration = Double(buffer.frameLength) / buffer.format.sampleRate
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.isPlaying = false
        }
    }

    /// Play a specific sound by ID (for preview/tap)
    func playSound(id: String, volume: Float = 1.0) {
        guard let item = availableSounds.first(where: { $0.id == id }),
              let buffer = loadBuffer(from: item.path) else { return }

        if playerNode.isPlaying {
            playerNode.stop()
        }

        playerNode.volume = volume
        playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts)
        playerNode.play()

        DispatchQueue.main.async { self.isPlaying = true }
        let duration = Double(buffer.frameLength) / buffer.format.sampleRate
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.isPlaying = false
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
