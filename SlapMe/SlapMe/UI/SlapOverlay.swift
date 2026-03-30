import SwiftUI
import AppKit

/// Shows a floating overlay window with a random phrase when a slap is detected.
final class SlapOverlayManager {
    static let shared = SlapOverlayManager()

    private var overlayWindow: NSWindow?

    private let phrases = [
        "Don't slap me like that!",
        "OUCH! 😫",
        "Hey! Watch it!",
        "That actually hurt!",
        "Do it again 😏",
        "Is that all you got?",
        "HARDER!",
        "Why would you do that?!",
        "I felt that one 💀",
        "My CPU is tingling",
        "Bro chill 😭",
        "NOT THE SCREEN!",
        "I'm telling Apple",
        "You call that a slap?",
        "OK I deserved that",
        "VIOLATION! 🚨",
        "Emotional damage!",
    ]

    private let emojis = ["👋", "💥", "😮", "🫣", "😤", "🤯", "💀", "🔥", "⚡️", "😭"]

    func showSlap(force: Double) {
        DispatchQueue.main.async { [self] in
            // Dismiss any existing overlay
            overlayWindow?.orderOut(nil)

            guard let screen = NSScreen.main else { return }

            let phrase = phrases.randomElement()!
            let emoji = emojis.randomElement()!

            // Create overlay content
            let hostingView = NSHostingView(
                rootView: SlapBubbleView(emoji: emoji, phrase: phrase, force: force)
            )

            let width: CGFloat = 300
            let height: CGFloat = 120

            // Position: center-top of screen
            let x = screen.frame.midX - width / 2
            let y = screen.frame.maxY - 200

            let window = NSWindow(
                contentRect: NSRect(x: x, y: y, width: width, height: height),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = .floating
            window.backgroundColor = .clear
            window.isOpaque = false
            window.ignoresMouseEvents = true
            window.hasShadow = false
            window.contentView = hostingView
            window.orderFront(nil)

            overlayWindow = window

            // Animate out after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.4
                    window.animator().alphaValue = 0
                }, completionHandler: {
                    window.orderOut(nil)
                })
            }
        }
    }
}

struct SlapBubbleView: View {
    let emoji: String
    let phrase: String
    let force: Double

    @State private var appear = false

    var body: some View {
        VStack(spacing: 8) {
            Text(emoji)
                .font(.system(size: 40))
                .scaleEffect(appear ? 1.0 : 0.3)

            Text(phrase)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.black.opacity(0.8))
                .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        )
        .scaleEffect(appear ? 1.0 : 0.5)
        .opacity(appear ? 1.0 : 0)
        .offset(y: appear ? 0 : 20)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                appear = true
            }
        }
    }
}
