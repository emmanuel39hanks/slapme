import SwiftUI
import AppKit

/// Shows a floating overlay window with a random phrase when a slap is detected.
/// Reuses a single window to avoid NSHostingView layout crashes during rapid updates.
final class SlapOverlayManager {
    static let shared = SlapOverlayManager()

    private var overlayWindow: NSWindow?
    private var hostingView: NSHostingView<SlapBubbleView>?
    private var dismissWorkItem: DispatchWorkItem?

    private let phrases = [
        "Don't slap me like that!",
        "OUCH!",
        "Hey! Watch it!",
        "That actually hurt!",
        "Do it again",
        "Is that all you got?",
        "HARDER!",
        "Why would you do that?!",
        "I felt that one",
        "My CPU is tingling",
        "Bro chill",
        "NOT THE SCREEN!",
        "I'm telling Apple",
        "You call that a slap?",
        "OK I deserved that",
        "VIOLATION!",
        "Emotional damage!",
    ]

    private let emojis = ["👋", "💥", "😮", "🫣", "😤", "🤯", "💀", "🔥", "⚡️", "😭"]

    func showSlap(force: Double) {
        DispatchQueue.main.async { [self] in
            // Cancel any pending dismiss
            dismissWorkItem?.cancel()

            let phrase = phrases.randomElement()!
            let emoji = emojis.randomElement()!

            guard let screen = NSScreen.main else { return }

            let view = SlapBubbleView(emoji: emoji, phrase: phrase, force: force)

            if let window = overlayWindow, let hosting = hostingView {
                // Reuse existing window — just update content
                window.alphaValue = 1
                hosting.rootView = view

                // Re-fit window to content
                let size = hosting.fittingSize
                let x = screen.frame.midX - size.width / 2
                let y = screen.frame.maxY - 200
                window.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
                window.orderFront(nil)
            } else {
                // First time — create window
                let hosting = NSHostingView(rootView: view)
                let size = hosting.fittingSize

                let x = screen.frame.midX - size.width / 2
                let y = screen.frame.maxY - 200

                let window = NSWindow(
                    contentRect: NSRect(x: x, y: y, width: size.width, height: size.height),
                    styleMask: .borderless,
                    backing: .buffered,
                    defer: false
                )
                window.level = .floating
                window.backgroundColor = .clear
                window.isOpaque = false
                window.ignoresMouseEvents = true
                window.hasShadow = false
                window.contentView = hosting
                window.orderFront(nil)

                overlayWindow = window
                hostingView = hosting
            }

            // Schedule dismiss
            let work = DispatchWorkItem { [weak self] in
                guard let window = self?.overlayWindow else { return }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.4
                    window.animator().alphaValue = 0
                }, completionHandler: {
                    window.orderOut(nil)
                })
            }
            dismissWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
        }
    }
}

struct SlapBubbleView: View {
    let emoji: String
    let phrase: String
    let force: Double

    var body: some View {
        VStack(spacing: 8) {
            Text(emoji)
                .font(.system(size: 40))

            Text(phrase)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: true, vertical: true)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.black.opacity(0.8))
                .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        )
    }
}
