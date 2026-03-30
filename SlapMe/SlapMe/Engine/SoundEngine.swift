import Foundation
import AVFoundation
import Combine

/// High-performance sound engine with preloading and force-based selection.
/// Uses AVAudioEngine for low-latency playback (<100ms).
final class SoundEngine: ObservableObject {
    // MARK: - Published
    @Published var loadedPack: SoundPack?
    @Published var isPlaying: Bool = false
    @Published var availablePacks: [SoundPackMeta] = []

    // MARK: - Audio
    private let audioEngine = AVAudioEngine()
    private var playerNodes: [AVAudioPlayerNode] = []
    private var preloadedBuffers: [ForceRange: [AVAudioPCMBuffer]] = [:]
    private let maxConcurrentPlayers = 4
    private var currentPlayerIndex = 0

    // MARK: - Types

    enum ForceRange: String, CaseIterable {
        case soft = "soft"
        case medium = "medium"
        case hard = "hard"

        init(force: Double) {
            switch force {
            case 0..<0.3: self = .soft
            case 0.3..<0.7: self = .medium
            default: self = .hard
            }
        }
    }

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
        let id: String  // folder name
        let name: String
        let author: String
        let description: String
        let path: URL
    }

    // MARK: - Init

    init() {
        setupAudioEngine()
        scanAvailablePacks()
    }

    private func setupAudioEngine() {
        let mainMixer = audioEngine.mainMixerNode
        let output = audioEngine.outputNode
        let format = output.inputFormat(forBus: 0)

        // Create player node pool for concurrent playback
        for _ in 0..<maxConcurrentPlayers {
            let player = AVAudioPlayerNode()
            audioEngine.attach(player)
            audioEngine.connect(player, to: mainMixer, format: format)
            playerNodes.append(player)
        }

        do {
            try audioEngine.start()
        } catch {
            print("[SoundEngine] Failed to start audio engine: \(error)")
        }
    }

    // MARK: - Pack Management

    func scanAvailablePacks() {
        var packs: [SoundPackMeta] = []

        // Check bundle resources
        if let bundlePath = Bundle.main.resourceURL?.appendingPathComponent("SoundPacks") {
            packs.append(contentsOf: scanPacksAt(bundlePath))
        }

        // Check Application Support for user packs
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let userPacksDir = appSupport.appendingPathComponent("SlapMe/SoundPacks")
            packs.append(contentsOf: scanPacksAt(userPacksDir))
        }

        // Include built-in default if nothing found
        if packs.isEmpty {
            packs.append(SoundPackMeta(
                id: "default",
                name: "Default",
                author: "SlapMe",
                description: "Built-in sound effects",
                path: Bundle.main.resourceURL ?? URL(fileURLWithPath: "/")
            ))
        }

        DispatchQueue.main.async {
            self.availablePacks = packs
        }
    }

    private func scanPacksAt(_ directory: URL) -> [SoundPackMeta] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [] }

        return contents.compactMap { url -> SoundPackMeta? in
            let metaURL = url.appendingPathComponent("metadata.json")
            guard let data = try? Data(contentsOf: metaURL),
                  let pack = try? JSONDecoder().decode(SoundPack.self, from: data) else {
                return nil
            }
            return SoundPackMeta(
                id: url.lastPathComponent,
                name: pack.name,
                author: pack.author,
                description: pack.description,
                path: url
            )
        }
    }

    // MARK: - Preloading

    func preloadCurrentPack(settings: SettingsManager) {
        let packId = settings.selectedSoundPack

        // Find pack path
        guard let meta = availablePacks.first(where: { $0.id == packId }) else {
            preloadDefaultSounds()
            return
        }

        let metaURL = meta.path.appendingPathComponent("metadata.json")
        guard let data = try? Data(contentsOf: metaURL),
              let pack = try? JSONDecoder().decode(SoundPack.self, from: data) else {
            preloadDefaultSounds()
            return
        }

        loadedPack = pack
        preloadedBuffers.removeAll()

        // Preload each category
        preloadedBuffers[.soft] = pack.sounds.soft.compactMap {
            loadBuffer(from: meta.path.appendingPathComponent($0))
        }
        preloadedBuffers[.medium] = pack.sounds.medium.compactMap {
            loadBuffer(from: meta.path.appendingPathComponent($0))
        }
        preloadedBuffers[.hard] = pack.sounds.hard.compactMap {
            loadBuffer(from: meta.path.appendingPathComponent($0))
        }
    }

    private func preloadDefaultSounds() {
        // Generate simple synthesized sounds as fallback
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

        for range in ForceRange.allCases {
            let buffer = generateToneBuffer(
                format: format,
                frequency: range == .soft ? 440 : range == .medium ? 660 : 880,
                duration: range == .soft ? 0.1 : range == .medium ? 0.2 : 0.3,
                amplitude: range == .soft ? 0.3 : range == .medium ? 0.6 : 1.0
            )
            if let buffer {
                preloadedBuffers[range] = [buffer]
            }
        }
    }

    private func loadBuffer(from url: URL) -> AVAudioPCMBuffer? {
        guard let audioFile = try? AVAudioFile(forReading: url) else { return nil }

        let frameCount = AVAudioFrameCount(audioFile.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frameCount) else {
            return nil
        }

        do {
            try audioFile.read(into: buffer)
            return buffer
        } catch {
            print("[SoundEngine] Failed to load \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    private func generateToneBuffer(
        format: AVAudioFormat,
        frequency: Double,
        duration: Double,
        amplitude: Double
    ) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData?[0] else { return nil }

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            // Sine wave with exponential decay envelope
            let envelope = exp(-t * 10.0)
            channelData[frame] = Float(sin(2.0 * .pi * frequency * t) * amplitude * envelope)
        }

        return buffer
    }

    // MARK: - Playback

    /// Play a sound matching the given force level
    func play(force: Double, volumeScale: Double) {
        let range = ForceRange(force: force)

        guard let buffers = preloadedBuffers[range], !buffers.isEmpty else { return }

        // Pick random buffer from category
        let buffer = buffers.randomElement()!

        // Round-robin through player nodes
        let player = playerNodes[currentPlayerIndex % maxConcurrentPlayers]
        currentPlayerIndex += 1

        // Stop if already playing
        if player.isPlaying {
            player.stop()
        }

        // Scale volume by force and user preference
        let volume = Float(force * volumeScale)
        player.volume = min(1.0, max(0.1, volume))

        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()

        DispatchQueue.main.async {
            self.isPlaying = true
        }

        // Reset playing state after estimated duration
        let duration = Double(buffer.frameLength) / buffer.format.sampleRate
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.isPlaying = false
        }
    }

    /// Preview a specific sound from a pack
    func preview(range: ForceRange) {
        play(force: range == .soft ? 0.15 : range == .medium ? 0.5 : 0.85, volumeScale: 0.8)
    }
}
