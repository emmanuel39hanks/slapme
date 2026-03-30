import SwiftUI
import Combine

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
    private var cancellables = Set<AnyCancellable>()

    let settingsManager = SettingsManager()
    let motionEngine = MotionEngine()
    let soundEngine = SoundEngine()
    private var reactionEngine: ReactionEngine!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Wire up engines
        reactionEngine = ReactionEngine(
            settings: settingsManager,
            sound: soundEngine,
            motion: motionEngine
        )

        soundEngine.preloadAll()
        reactionEngine.start()

        // Menu bar with slap count
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: "SlapMe")
            button.title = " 0"
            button.imagePosition = .imageLeading
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Update menu bar count when slaps happen
        settingsManager.$totalSlaps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.statusItem?.button?.title = " \(count)"
            }
            .store(in: &cancellables)

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 480)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(settingsManager)
                .environmentObject(motionEngine)
                .environmentObject(soundEngine)
        )
        self.popover = popover

        NSLog("[SlapMe] App launched, detection started")
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
