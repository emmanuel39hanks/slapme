import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var motion: MotionEngine
    @EnvironmentObject var sound: SoundEngine

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("SlapMe")
                        .font(.system(size: 14, weight: .semibold))
                }

                Spacer()

                // Status indicator
                HStack(spacing: 5) {
                    Circle()
                        .fill(settings.isEnabled ? Color.green : Color.gray)
                        .frame(width: 6, height: 6)
                    Text(settings.isEnabled ? "Active" : "Off")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // Force Meter
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Force")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(motion.currentForce * 100))%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.gray.opacity(0.15))
                            .frame(height: 6)

                        Capsule()
                            .fill(forceColor)
                            .frame(width: max(0, geo.size.width * motion.currentForce), height: 6)
                            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: motion.currentForce)
                    }
                }
                .frame(height: 6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Enable Toggle
            Toggle(isOn: $settings.isEnabled) {
                Label("Enable Detection", systemImage: "waveform.path")
                    .font(.system(size: 13))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Sensitivity
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Sensitivity")
                        .font(.system(size: 12))
                    Spacer()
                    Text(sensitivityLabel)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Slider(value: $settings.sensitivity, in: 0...1, step: 0.05)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)

            // Cooldown
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Cooldown")
                        .font(.system(size: 12))
                    Spacer()
                    Text("\(Int(settings.cooldownInterval * 1000))ms")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Slider(value: $settings.cooldownInterval, in: 0.1...2.0, step: 0.1)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)

            Divider()
                .padding(.vertical, 4)

            // Sound Pack Picker
            HStack {
                Text("Sound Pack")
                    .font(.system(size: 12))
                Spacer()
                Picker("", selection: $settings.selectedSoundPack) {
                    ForEach(sound.availablePacks) { pack in
                        Text(pack.name).tag(pack.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)

            // Mode Picker
            HStack {
                Text("Mode")
                    .font(.system(size: 12))
                Spacer()
                Picker("", selection: $settings.activeMode) {
                    ForEach(SlapMode.allCases) { mode in
                        Label(mode.displayName, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)

            Divider()
                .padding(.vertical, 4)

            // Stats
            HStack(spacing: 16) {
                StatView(value: "\(settings.totalSlaps)", label: "Total")
                StatView(value: "\(motion.comboCount)", label: "Combo")
                StatView(
                    value: motion.lastEventTimestamp != nil
                        ? timeAgo(motion.lastEventTimestamp!)
                        : "--",
                    label: "Last"
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // Test buttons
            HStack(spacing: 8) {
                TestButton(label: "Tap", force: 0.2, engine: motion)
                TestButton(label: "Hit", force: 0.5, engine: motion)
                TestButton(label: "Slap", force: 0.9, engine: motion)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // Footer
            HStack {
                Button("Settings...") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.accentColor)

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 320)
    }

    // MARK: - Helpers

    private var forceColor: Color {
        switch motion.currentForce {
        case 0..<0.3: return .green
        case 0.3..<0.7: return .orange
        default: return .red
        }
    }

    private var sensitivityLabel: String {
        switch settings.sensitivity {
        case 0..<0.3: return "Low"
        case 0.3..<0.7: return "Medium"
        default: return "High"
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 1 { return "now" }
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m"
    }
}

// MARK: - Subviews

struct StatView: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct TestButton: View {
    let label: String
    let force: Double
    let engine: MotionEngine

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            isPressed = true
            engine.simulateForce(force)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isPressed = false
            }
        }) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isPressed ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}
