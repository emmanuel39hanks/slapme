import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var motion: MotionEngine
    @EnvironmentObject var sound: SoundEngine

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                // Hero
                VStack(spacing: 16) {
                    // Emoji that reacts
                    Text(forceEmoji)
                        .font(.system(size: 48))
                        .scaleEffect(1.0 + motion.currentForce * 0.3)
                        .animation(.spring(response: 0.25, dampingFraction: 0.5), value: motion.currentForce)

                    // Force display
                    Text("\(Int(motion.currentForce * 100))%")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "0a0a0a"))

                    // Status
                    Text(statusText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "9ca3af"))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color(hex: "f3f4f6"))
                        .clipShape(Capsule())

                    // Force bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(hex: "f3f4f6"))
                            Capsule()
                                .fill(Color(hex: "0a0a0a"))
                                .frame(width: max(0, geo.size.width * motion.currentForce))
                                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: motion.currentForce)
                        }
                    }
                    .frame(height: 6)
                    .padding(.horizontal, 32)
                }
                .padding(.top, 24)
                .padding(.bottom, 16)

                // Sound buttons grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                ], spacing: 8) {
                    soundButton("Bruh", force: 0.5)
                    soundButton("Sheesh", force: 0.55)
                    soundButton("Let's Go", force: 0.9)
                    soundButton("Noice", force: 0.2)
                    soundButton("Vine Boom", force: 0.85)
                    soundButton("Oof", force: 0.15)
                }
                .padding(.horizontal, 16)

                Spacer().frame(height: 12)

                // Stats row
                HStack(spacing: 0) {
                    statItem("\(settings.totalSlaps)", label: "slaps")
                    Divider().frame(height: 20)
                    statItem(motion.comboCount >= 3 ? "x\(motion.comboCount)" : "--", label: "combo")
                    Divider().frame(height: 20)
                    statItem(sensitivityLabel, label: "sensitivity")
                }
                .padding(.vertical, 10)
                .background(Color(hex: "fafafa"))

                // Toggle + quit
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

    // MARK: - Subviews

    private func soundButton(_ label: String, force: Double) -> some View {
        Button(action: {
            motion.simulateForce(force)
        }) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(hex: "0a0a0a"))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color(hex: "f3f4f6"))
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private func statItem(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: "0a0a0a"))
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "9ca3af"))
        }
        .frame(maxWidth: .infinity)
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

    private var statusText: String {
        if !settings.isEnabled { return "Paused" }
        if motion.currentForce > 0.5 { return "OUCH!" }
        if motion.comboCount >= 3 { return "Combo x\(motion.comboCount)" }
        return "Ready"
    }

    private var sensitivityLabel: String {
        switch settings.sensitivity {
        case 0..<0.3: return "low"
        case 0.3..<0.7: return "med"
        default: return "high"
        }
    }
}

// MARK: - Color Extension

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
