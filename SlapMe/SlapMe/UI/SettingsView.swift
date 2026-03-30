import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var motion: MotionEngine
    @EnvironmentObject var sound: SoundEngine

    var body: some View {
        TabView {
            GeneralTab()
                .environmentObject(settings)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            SoundTab()
                .environmentObject(settings)
                .environmentObject(sound)
                .tabItem {
                    Label("Sound", systemImage: "speaker.wave.2")
                }

            AdvancedTab()
                .environmentObject(settings)
                .tabItem {
                    Label("Advanced", systemImage: "slider.horizontal.3")
                }
        }
        .frame(width: 450, height: 340)
    }
}

// MARK: - General Tab

struct GeneralTab: View {
    @EnvironmentObject var settings: SettingsManager

    var body: some View {
        Form {
            Section {
                Toggle("Enable SlapMe", isOn: $settings.isEnabled)
                Toggle("Launch at login", isOn: .constant(false))  // TODO: implement with SMAppService
            }

            Section("Detection") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Sensitivity")
                        Spacer()
                        Text(String(format: "%.0f%%", settings.sensitivity * 100))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.sensitivity, in: 0...1, step: 0.05)
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("Cooldown")
                        Spacer()
                        Text(String(format: "%.0fms", settings.cooldownInterval * 1000))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.cooldownInterval, in: 0.1...2.0, step: 0.1)
                }

                Picker("Mode", selection: $settings.activeMode) {
                    ForEach(SlapMode.allCases) { mode in
                        HStack {
                            Image(systemName: mode.icon)
                            Text(mode.displayName)
                        }
                        .tag(mode)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Sound Tab

struct SoundTab: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var sound: SoundEngine

    var body: some View {
        Form {
            Section("Volume") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Volume Scale")
                        Spacer()
                        Text(String(format: "%.0f%%", settings.volumeScale * 100))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.volumeScale, in: 0...1, step: 0.05)
                }
            }

            Section("Sound Pack") {
                Picker("Active Pack", selection: $settings.selectedSoundPack) {
                    ForEach(sound.availablePacks) { pack in
                        Text(pack.name).tag(pack.id)
                    }
                }
                .onChange(of: settings.selectedSoundPack) { _ in
                    sound.preloadCurrentPack(settings: settings)
                }
            }

            Section("Preview") {
                HStack(spacing: 12) {
                    PreviewButton(label: "Soft", range: .soft, sound: sound)
                    PreviewButton(label: "Medium", range: .medium, sound: sound)
                    PreviewButton(label: "Hard", range: .hard, sound: sound)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct PreviewButton: View {
    let label: String
    let range: SoundEngine.ForceRange
    let sound: SoundEngine

    @State private var isActive = false

    var body: some View {
        Button(action: {
            isActive = true
            sound.preview(range: range)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { isActive = false }
        }) {
            VStack(spacing: 4) {
                Image(systemName: "speaker.wave.\(range == .soft ? "1" : range == .medium ? "2" : "3")")
                    .font(.system(size: 18))
                    .foregroundColor(isActive ? .accentColor : .primary)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Advanced Tab

struct AdvancedTab: View {
    @EnvironmentObject var settings: SettingsManager

    var body: some View {
        Form {
            Section("Safety") {
                Toggle("Typing protection", isOn: $settings.typingProtection)
                    .help("Ignores light taps during rapid input to avoid accidental triggers")

                Toggle("Headphone mode warning", isOn: $settings.headphoneWarning)
                    .help("Shows a warning when headphones are connected and volume is high")
            }

            Section("Stats") {
                LabeledContent("Total Slaps") {
                    Text("\(settings.totalSlaps)")
                        .monospacedDigit()
                }
                Button("Reset Stats") {
                    settings.totalSlaps = 0
                }
            }

            Section("Debug") {
                LabeledContent("Force Threshold") {
                    Text(String(format: "%.2f", settings.forceThreshold))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
