import Foundation
import Combine

final class SettingsManager: ObservableObject {
    // MARK: - Published Settings
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "isEnabled") }
    }

    @Published var sensitivity: Double {
        didSet { UserDefaults.standard.set(sensitivity, forKey: "sensitivity") }
    }

    @Published var cooldownInterval: Double {
        didSet { UserDefaults.standard.set(cooldownInterval, forKey: "cooldownInterval") }
    }

    @Published var volumeScale: Double {
        didSet { UserDefaults.standard.set(volumeScale, forKey: "volumeScale") }
    }

    @Published var selectedSoundPack: String {
        didSet { UserDefaults.standard.set(selectedSoundPack, forKey: "selectedSoundPack") }
    }

    @Published var activeMode: SlapMode {
        didSet { UserDefaults.standard.set(activeMode.rawValue, forKey: "activeMode") }
    }

    @Published var typingProtection: Bool {
        didSet { UserDefaults.standard.set(typingProtection, forKey: "typingProtection") }
    }

    @Published var headphoneWarning: Bool {
        didSet { UserDefaults.standard.set(headphoneWarning, forKey: "headphoneWarning") }
    }

    // MARK: - Stats
    @Published var totalSlaps: Int = 0

    // MARK: - Init
    init() {
        let defaults = UserDefaults.standard

        // Register defaults
        defaults.register(defaults: [
            "isEnabled": true,
            "sensitivity": 0.5,
            "cooldownInterval": 0.3,
            "volumeScale": 0.8,
            "selectedSoundPack": "default",
            "activeMode": SlapMode.slap.rawValue,
            "typingProtection": true,
            "headphoneWarning": true,
        ])

        self.isEnabled = defaults.bool(forKey: "isEnabled")
        self.sensitivity = defaults.double(forKey: "sensitivity")
        self.cooldownInterval = defaults.double(forKey: "cooldownInterval")
        self.volumeScale = defaults.double(forKey: "volumeScale")
        self.selectedSoundPack = defaults.string(forKey: "selectedSoundPack") ?? "default"
        self.activeMode = SlapMode(rawValue: defaults.string(forKey: "activeMode") ?? "") ?? .slap
        self.typingProtection = defaults.bool(forKey: "typingProtection")
        self.headphoneWarning = defaults.bool(forKey: "headphoneWarning")
    }

    // MARK: - Force Threshold

    /// Minimum force to register as an interaction, adjusted by sensitivity
    var forceThreshold: Double {
        return max(0.05, 0.5 - (sensitivity * 0.45))
    }
}

// MARK: - Enums

enum SlapMode: String, CaseIterable, Identifiable {
    case slap = "slap"
    case event = "event"
    case passive = "passive"
    case combo = "combo"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .slap: return "Slap Mode"
        case .event: return "Event Mode"
        case .passive: return "Passive Mode"
        case .combo: return "Combo Mode"
        }
    }

    var description: String {
        switch self {
        case .slap: return "Motion-triggered reactions"
        case .event: return "USB connect/disconnect triggers"
        case .passive: return "Random ambient reactions"
        case .combo: return "Consecutive hits escalate"
        }
    }

    var icon: String {
        switch self {
        case .slap: return "hand.raised.fill"
        case .event: return "cable.connector"
        case .passive: return "waveform"
        case .combo: return "bolt.fill"
        }
    }
}
