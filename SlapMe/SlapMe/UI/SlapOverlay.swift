import SwiftUI
import AppKit

/// Shows a floating overlay window with an animated GIF reaction when a slap is detected.
/// Reuses a single window to avoid NSHostingView layout crashes during rapid updates.
final class SlapOverlayManager {
    static let shared = SlapOverlayManager()

    private var overlayWindow: NSWindow?
    private var gifView: NSImageView?
    private var labelField: NSTextField?
    private var containerView: NSView?
    private var dismissWorkItem: DispatchWorkItem?

    private var gifImages: [NSImage] = []

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

    init() {
        loadGifs()
    }

    private func loadGifs() {
        var searchPaths: [URL] = []

        // .app bundle: Contents/Resources/Gifs/
        if let resURL = Bundle.main.resourceURL {
            let gifsURL = resURL.appendingPathComponent("Gifs")
            searchPaths.append(gifsURL)
            NSLog("[SlapOverlay] Searching for GIFs in: %@", gifsURL.path)
        }

        // SPM bundle: SlapMe_SlapMe.bundle/Gifs/
        if let spmURL = Bundle.module.resourceURL {
            searchPaths.append(spmURL.appendingPathComponent("Gifs"))
        }

        for dir in searchPaths {
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { continue }
            for file in files where file.hasSuffix(".gif") {
                let fullPath = dir.appendingPathComponent(file).path
                if let image = NSImage(contentsOfFile: fullPath) {
                    gifImages.append(image)
                    NSLog("[SlapOverlay] Loaded GIF: %@", file)
                }
            }
            if !gifImages.isEmpty { break }
        }

        NSLog("[SlapOverlay] Total GIFs loaded: %d", gifImages.count)
    }

    func showSlap(force: Double) {
        DispatchQueue.main.async { [self] in
            dismissWorkItem?.cancel()

            guard let screen = NSScreen.main else { return }

            let phrase = phrases.randomElement()!
            let gif = gifImages.randomElement()

            let gifSize: CGFloat = 150
            let windowWidth: CGFloat = 320
            let windowHeight: CGFloat = gif != nil ? 240 : 100

            if let window = overlayWindow {
                // Reuse window
                window.alphaValue = 1

                if let gv = gifView {
                    gv.image = gif
                    gv.animates = true
                    gv.isHidden = gif == nil
                }
                labelField?.stringValue = phrase

                let x = screen.frame.midX - windowWidth / 2
                let y = screen.frame.maxY - 280
                window.setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
                window.orderFront(nil)
            } else {
                // Create window + views
                let x = screen.frame.midX - windowWidth / 2
                let y = screen.frame.maxY - 280

                let window = NSWindow(
                    contentRect: NSRect(x: x, y: y, width: windowWidth, height: windowHeight),
                    styleMask: .borderless,
                    backing: .buffered,
                    defer: false
                )
                window.level = .floating
                window.backgroundColor = .clear
                window.isOpaque = false
                window.ignoresMouseEvents = true
                window.hasShadow = false

                // Container with rounded background
                let container = NSView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight))
                container.wantsLayer = true
                container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
                container.layer?.cornerRadius = 20
                container.layer?.masksToBounds = true

                // GIF view
                let imageView = NSImageView(frame: NSRect(
                    x: (windowWidth - gifSize) / 2,
                    y: windowHeight - gifSize - 16,
                    width: gifSize,
                    height: gifSize
                ))
                imageView.imageScaling = .scaleProportionallyUpOrDown
                imageView.animates = true
                imageView.image = gif
                imageView.isHidden = gif == nil
                imageView.wantsLayer = true
                imageView.layer?.cornerRadius = 12
                imageView.layer?.masksToBounds = true
                container.addSubview(imageView)

                // Text label
                let label = NSTextField(labelWithString: phrase)
                label.font = NSFont.systemFont(ofSize: 15, weight: .bold)
                label.textColor = .white
                label.alignment = .center
                label.backgroundColor = .clear
                label.isBezeled = false
                label.isEditable = false
                let labelY: CGFloat = gif != nil ? 12 : (windowHeight - 30) / 2
                label.frame = NSRect(x: 16, y: labelY, width: windowWidth - 32, height: 30)
                container.addSubview(label)

                window.contentView = container
                window.orderFront(nil)

                overlayWindow = window
                gifView = imageView
                labelField = label
                containerView = container
            }

            // Schedule dismiss
            let work = DispatchWorkItem { [weak self] in
                guard let window = self?.overlayWindow else { return }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.4
                    window.animator().alphaValue = 0
                }, completionHandler: {
                    window.orderOut(nil)
                    self?.gifView?.animates = false
                })
            }
            dismissWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
        }
    }
}
