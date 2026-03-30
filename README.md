# SlapMe

Your Mac reacts to every hit.

SlapMe is a macOS menu bar app that detects physical interactions with your MacBook — taps, hits, and slaps — and triggers customizable sounds and visual effects. Lightweight, fun, endlessly extensible.

![macOS](https://img.shields.io/badge/macOS-13%2B-black?style=flat-square&logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)

---

## How It Works

1. **Install & launch** — SlapMe lives in your menu bar. No dock icon, zero setup.
2. **Slap your Mac** — The motion engine detects force and direction. Light taps, medium hits, full slaps.
3. **Hear the reaction** — Force maps to sound intensity. Pick a sound pack or make your own.

## Features

- **Motion Detection** — Accelerometer-based detection via IOKit with force normalization (0→1)
- **Sound Engine** — AVAudioEngine with preloaded buffers for <100ms latency playback
- **Sound Packs** — Ship with built-in packs or create custom ones (simple folder + `metadata.json`)
- **Combo System** — Consecutive hits escalate reactions with increasingly dramatic effects
- **Multiple Modes** — Slap, Event (USB triggers), Passive (ambient), Combo (streaks)
- **Menu Bar Native** — No dock icon. Toggle, adjust sensitivity, switch packs from the menu
- **Typing Protection** — Filters accidental triggers during keyboard input
- **Cooldown System** — Configurable debounce to prevent spam (100ms–2s)

## Architecture

```
MotionEngine  → detects force (0.0 - 1.0)
    ↓
ReactionEngine → maps force → reaction type
    ↓
SoundEngine   → plays categorized audio clip
    ↓
UI Layer      → screen flash / menu bar animation
```

Each module is independent, testable, and replaceable.

```
SlapMe/
├── SlapMe/
│   ├── SlapMeApp.swift            # Entry point, AppDelegate, NSStatusItem
│   ├── Core/
│   │   └── SettingsManager.swift  # UserDefaults-backed settings
│   ├── Engine/
│   │   ├── MotionEngine.swift     # IOKit SMS accelerometer + force normalization
│   │   ├── SoundEngine.swift      # AVAudioEngine, preloading, force→sound mapping
│   │   └── ReactionEngine.swift   # Orchestrator: motion → sound + visual effects
│   ├── UI/
│   │   ├── MenuBarView.swift      # NSPopover menu bar interface
│   │   └── SettingsView.swift     # Tabbed settings panel
│   └── Resources/
│       └── SoundPacks/            # Built-in sound packs
├── Tests/
│   └── MotionEngineTests.swift
└── Package.swift

web/                               # Marketing site (Next.js)
├── src/
│   ├── app/page.tsx
│   └── components/
└── public/sounds/                 # Playable sound effects
```

## Sound Pack Format

Create a folder with a `metadata.json` and categorized audio clips:

```json
{
  "name": "My Pack",
  "author": "you",
  "version": "1.0.0",
  "description": "Your custom sounds",
  "sounds": {
    "soft": ["tap1.wav", "tap2.wav"],
    "medium": ["hit1.wav", "hit2.wav"],
    "hard": ["slap1.wav", "slap2.wav"]
  }
}
```

Drop the folder into `~/Library/Application Support/SlapMe/SoundPacks/`.

## Development

### macOS App

```bash
# Build with Swift Package Manager
cd SlapMe
swift build

# Or open in Xcode
open Package.swift
```

Requires macOS 13+ and Xcode 15+.

### Marketing Site

```bash
cd web
npm install
npm run dev
```

Runs at `http://localhost:3000`.

## Requirements

- macOS 13.0+ (Ventura or later)
- Apple Silicon or Intel Mac
- Xcode 15+ (for development)

## Contributing

Contributions are welcome. Please open an issue first to discuss what you'd like to change.

1. Fork the repo
2. Create your branch (`git checkout -b feat/my-feature`)
3. Commit your changes
4. Push to the branch
5. Open a Pull Request

## License

[MIT](LICENSE)
