import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var motion: MotionEngine
    @EnvironmentObject var sound: SoundEngine

    @State private var lastTriggerScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 0) {
            // Hero area with force visualization
            ZStack {
                // Background gradient that reacts to force
                RoundedRectangle(cornerRadius: 0)
                    .fill(
                        LinearGradient(
                            colors: [forceGradientColor.opacity(0.15), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .animation(.easeOut(duration: 0.3), value: motion.currentForce)

                VStack(spacing: 12) {
                    // Mascot / Force circle
                    ZStack {
                        // Pulse rings
                        if motion.currentForce > 0.1 {
                            Circle()
                                .stroke(forceColor.opacity(0.2), lineWidth: 2)
                                .frame(width: 80, height: 80)
                                .scaleEffect(lastTriggerScale)
                                .animation(
                                    .easeOut(duration: 0.8),
                                    value: lastTriggerScale
                                )
                        }

                        Circle()
                            .fill(forceColor.opacity(0.1))
                            .frame(width: 64, height: 64)

                        Circle()
                            .fill(forceColor)
                            .frame(
                                width: 48 + CGFloat(motion.currentForce) * 16,
                                height: 48 + CGFloat(motion.currentForce) * 16
                            )
                            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: motion.currentForce)

                        Text(forceEmoji)
                            .font(.system(size: 24))
                    }

                    // Force percentage
                    Text("\(Int(motion.currentForce * 100))%")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .contentTransition(.numericText())

                    // Status pill
                    HStack(spacing: 5) {
                        Circle()
                            .fill(settings.isEnabled ? Color.green : Color.gray.opacity(0.5))
                            .frame(width: 6, height: 6)
                        Text(statusText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(Capsule())
                }
                .padding(.vertical, 20)
            }
            .frame(height: 180)

            // Slap counter banner
            if settings.totalSlaps > 0 {
                HStack {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text("\(settings.totalSlaps) slaps all time")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    if motion.comboCount >= 3 {
                        Text("COMBO x\(motion.comboCount)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.06))
            }

            Divider()

            // Controls
            VStack(spacing: 2) {
                // Enable toggle
                controlRow {
                    Toggle(isOn: $settings.isEnabled) {
                        Label("Detection", systemImage: "waveform.path")
                            .font(.system(size: 13))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                // Sensitivity
                controlRow {
                    VStack(spacing: 4) {
                        HStack {
                            Label("Sensitivity", systemImage: "dial.low")
                                .font(.system(size: 12))
                            Spacer()
                            Text(sensitivityLabel)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.sensitivity, in: 0...1, step: 0.05)
                            .controlSize(.small)
                    }
                }

                // Cooldown
                controlRow {
                    HStack {
                        Label("Cooldown", systemImage: "timer")
                            .font(.system(size: 12))
                        Spacer()
                        Picker("", selection: cooldownBinding) {
                            Text("Fast").tag(0.15)
                            Text("Normal").tag(0.3)
                            Text("Slow").tag(0.8)
                            Text("Chill").tag(1.5)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 170)
                        .controlSize(.small)
                    }
                }

                // Mode
                controlRow {
                    HStack {
                        Label("Mode", systemImage: settings.activeMode.icon)
                            .font(.system(size: 12))
                        Spacer()
                        Picker("", selection: $settings.activeMode) {
                            ForEach(SlapMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 130)
                        .controlSize(.small)
                    }
                }

                // Sound pack
                controlRow {
                    HStack {
                        Label("Sounds", systemImage: "speaker.wave.2")
                            .font(.system(size: 12))
                        Spacer()
                        Picker("", selection: $settings.selectedSoundPack) {
                            ForEach(sound.availablePacks) { pack in
                                Text(pack.name).tag(pack.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 130)
                        .controlSize(.small)
                    }
                }
            }

            Divider()

            // Test buttons
            HStack(spacing: 6) {
                testButton("Tap", force: 0.15, icon: "hand.point.up")
                testButton("Hit", force: 0.5, icon: "hand.raised")
                testButton("Slap!", force: 0.95, icon: "hand.raised.fill")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // Footer
            HStack {
                Button("Settings...") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.accentColor)

                Spacer()

                Text("v1.0")
                    .font(.system(size: 10))
                    .foregroundColor(.gray.opacity(0.4))

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 300)
        .onChange(of: motion.currentForce) { _ in
            if motion.currentForce > 0.3 {
                lastTriggerScale = 1.8
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    lastTriggerScale = 1.0
                }
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func controlRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
    }

    private func testButton(_ label: String, force: Double, icon: String) -> some View {
        Button(action: {
            motion.simulateForce(force)
        }) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.08))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    // MARK: - Computed

    private var forceEmoji: String {
        switch motion.currentForce {
        case 0..<0.05: return "😴"
        case 0.05..<0.3: return "😏"
        case 0.3..<0.7: return "😮"
        default: return "🤯"
        }
    }

    private var forceColor: Color {
        switch motion.currentForce {
        case 0..<0.3: return .green
        case 0.3..<0.7: return .orange
        default: return .red
        }
    }

    private var forceGradientColor: Color {
        switch motion.currentForce {
        case 0..<0.05: return .gray
        case 0.05..<0.3: return .green
        case 0.3..<0.7: return .orange
        default: return .red
        }
    }

    private var statusText: String {
        if !settings.isEnabled { return "Paused" }
        if motion.currentForce > 0.5 { return "OUCH!" }
        if motion.comboCount >= 3 { return "On fire" }
        return "Listening"
    }

    private var sensitivityLabel: String {
        switch settings.sensitivity {
        case 0..<0.3: return "Low"
        case 0.3..<0.7: return "Med"
        default: return "High"
        }
    }

    private var cooldownBinding: Binding<Double> {
        Binding(
            get: {
                // Snap to nearest preset
                let presets: [Double] = [0.15, 0.3, 0.8, 1.5]
                return presets.min(by: { abs($0 - settings.cooldownInterval) < abs($1 - settings.cooldownInterval) }) ?? 0.3
            },
            set: { settings.cooldownInterval = $0 }
        )
    }
}
