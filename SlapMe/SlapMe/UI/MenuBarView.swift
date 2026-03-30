import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var motion: MotionEngine
    @EnvironmentObject var sound: SoundEngine

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    Text(forceEmoji)
                        .font(.system(size: 44))
                        .scaleEffect(1.0 + motion.currentForce * 0.4)
                        .animation(.spring(response: 0.2, dampingFraction: 0.5), value: motion.currentForce)

                    Text(statusText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "9ca3af"))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color(hex: "f3f4f6"))
                        .clipShape(Capsule())
                }
                .padding(.top, 20)
                .padding(.bottom, 14)

                // Divider
                Rectangle()
                    .fill(Color(hex: "f3f4f6"))
                    .frame(height: 1)

                // Sound picker label
                HStack {
                    Text("Pick a sound")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "9ca3af"))
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)

                // Sound buttons — tap to preview, selected one plays on slap
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                    ], spacing: 8) {
                        ForEach(sound.availableSounds) { item in
                            Button(action: {
                                sound.selectedSound = item.id
                                sound.playSound(id: item.id)
                            }) {
                                Text(item.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(
                                        sound.selectedSound == item.id
                                            ? .white
                                            : Color(hex: "0a0a0a")
                                    )
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(
                                        sound.selectedSound == item.id
                                            ? Color(hex: "0a0a0a")
                                            : Color(hex: "f3f4f6")
                                    )
                                    .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(maxHeight: 200)

                // Divider
                Rectangle()
                    .fill(Color(hex: "f3f4f6"))
                    .frame(height: 1)
                    .padding(.top, 8)

                // Stats
                HStack(spacing: 0) {
                    statItem("\(settings.totalSlaps)", label: "slaps")
                    Rectangle().fill(Color(hex: "e5e7eb")).frame(width: 1, height: 20)
                    statItem(
                        sound.availableSounds.first(where: { $0.id == sound.selectedSound })?.name ?? "--",
                        label: "selected"
                    )
                }
                .padding(.vertical, 10)

                // Divider
                Rectangle()
                    .fill(Color(hex: "f3f4f6"))
                    .frame(height: 1)

                // Footer
                HStack {
                    Button(action: {
                        settings.isEnabled.toggle()
                    }) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(settings.isEnabled ? Color.green : Color(hex: "d1d5db"))
                                .frame(width: 7, height: 7)
                            Text(settings.isEnabled ? "Listening" : "Paused")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(hex: "6b7280"))
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button("Quit") {
                        NSApp.terminate(nil)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "9ca3af"))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .frame(width: 280)
    }

    // MARK: - Helpers

    private func statItem(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(hex: "0a0a0a"))
                .lineLimit(1)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "9ca3af"))
        }
        .frame(maxWidth: .infinity)
    }

    private var forceEmoji: String {
        switch motion.currentForce {
        case 0..<0.05: return "😴"
        case 0.05..<0.3: return "😏"
        case 0.3..<0.7: return "😮"
        default: return "🤯"
        }
    }

    private var statusText: String {
        if !settings.isEnabled { return "Paused" }
        if motion.currentForce > 0.5 { return "OUCH!" }
        if motion.comboCount >= 3 { return "Combo x\(motion.comboCount)" }
        return "Slap your Mac"
    }
}

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
