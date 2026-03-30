import SwiftUI

@main
struct SlapMeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.settingsManager)
                .environmentObject(appDelegate.motionEngine)
                .environmentObject(appDelegate.soundEngine)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    let settingsManager = SettingsManager()
    let motionEngine = MotionEngine()
    let soundEngine = SoundEngine()
    private var reactionEngine: ReactionEngine!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Wire up engines
        reactionEngine = ReactionEngine(
            settings: settingsManager,
            sound: soundEngine,
            motion: motionEngine
        )

        soundEngine.preloadCurrentPack(settings: settingsManager)

        // Menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: "SlapMe")
            button.action = #selector(togglePopover)
            button.target = self
        }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 440)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(settingsManager)
                .environmentObject(motionEngine)
                .environmentObject(soundEngine)
        )
        self.popover = popover
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
