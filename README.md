# SlapMe

Your Mac reacts to every hit.

SlapMe is a macOS menu bar app that detects physical interactions with your MacBook — taps, hits, and slaps — and triggers customizable sounds and visual effects. Open source, developer-first, endlessly extensible.

![macOS](https://img.shields.io/badge/macOS-13%2B-black?style=flat-square&logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)

---

## How It Works

1. **Install & launch** — SlapMe lives in your menu bar. No dock icon, zero setup.
2. **Pick a sound** — Tap any sound to preview and select it.
3. **Slap your Mac** — The selected sound plays when a physical impact is detected.

## Features

- **Slap Detection** — Microphone-based impact detection (works on all Macs) + Apple Silicon accelerometer via IOKit HID (M1 Pro+, requires root)
- **Sound Picker** — Tap to preview, selected sound plays on slap
- **Bundled Sounds** — Bruh, Sheesh, Vine Boom, Let's Go, Noice, Oof, and more
- **Custom Sounds** — Drop MP3/WAV files into the sound pack folder
- **Menu Bar Native** — No dock icon, minimal UI
- **Open Source** — MIT licensed, extend it however you want

## Project Structure

```
SlapMe/                             # macOS SwiftUI App
├── Package.swift                   # SPM manifest (macOS 13+)
├── SlapMe/
│   ├── SlapMeApp.swift             # Entry point, menu bar setup
│   ├── Info.plist                  # App config (LSUIElement, mic permission)
│   ├── Core/
│   │   └── SettingsManager.swift   # UserDefaults-backed settings
│   ├── Engine/
│   │   ├── MotionEngine.swift      # Slap detection (mic + accelerometer)
│   │   ├── SoundEngine.swift       # AVAudioPlayer-based playback
│   │   └── ReactionEngine.swift    # Wires detection → sound + visual
│   ├── UI/
│   │   ├── MenuBarView.swift       # Sound picker + controls
│   │   └── SettingsView.swift      # Settings panel
│   └── Resources/
│       ├── AppIcon.icns
│       └── SoundPacks/default/     # Bundled sound files
└── Tests/

web/                                # Marketing site (Next.js + Tailwind)
```

## Development

### Prerequisites

- macOS 13+ (Ventura or later)
- Xcode 15+ (includes Swift 5.9+)
- Node.js 18+ (for the marketing site)

### Build & Run Locally

```bash
# Clone the repo
git clone https://github.com/emmanuel39hanks/slapme.git
cd slapme

# Build the macOS app
cd SlapMe
swift build

# Run it (from swift build)
.build/debug/SlapMe

# Or open in Xcode and hit Cmd+R
open Package.swift
```

### Add Custom Sounds

Drop `.mp3`, `.wav`, or `.m4a` files into:

```
SlapMe/SlapMe/Resources/SoundPacks/default/
```

Then rebuild. They'll show up in the sound picker automatically.

Users can also add sounds at runtime by placing files in:

```
~/Library/Application Support/SlapMe/SoundPacks/default/
```

### Marketing Site

```bash
cd web
npm install
npm run dev
# Open http://localhost:3000
```

---

## Building for Distribution

If you want to distribute the app (share the `.app` with others), you need to sign and notarize it. This requires an [Apple Developer account](https://developer.apple.com/) ($99/year).

### Step 1: Set Up Signing Certificate

1. Open **Xcode → Settings → Accounts**
2. Add your Apple ID if not already there
3. Select your team → **Manage Certificates**
4. Click **+** → **Developer ID Application**

Verify it installed:

```bash
security find-identity -v -p codesigning
# Should show: "Developer ID Application: Your Name (TEAM_ID)"
```

### Step 2: Create an App-Specific Password

Apple notarization requires an app-specific password (not your regular Apple ID password):

1. Go to [account.apple.com](https://account.apple.com)
2. Sign in → **Sign-In and Security** → **App-Specific Passwords**
3. Click **Generate** → name it "notarytool" → copy the password

### Step 3: Store Notarization Credentials

```bash
xcrun notarytool store-credentials "notary" \
  --apple-id YOUR_APPLE_ID@icloud.com \
  --team-id YOUR_TEAM_ID \
  --password YOUR_APP_SPECIFIC_PASSWORD
```

This saves credentials securely in your Keychain. You only need to do this once.

### Step 4: Build, Sign, Notarize

```bash
# Build release binary
cd SlapMe
swift build -c release

# Assemble the .app bundle
APP="../release/SlapMe.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/arm64-apple-macosx/release/SlapMe "$APP/Contents/MacOS/SlapMe"
chmod +x "$APP/Contents/MacOS/SlapMe"
cp SlapMe/Info.plist "$APP/Contents/Info.plist"
cp SlapMe/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R .build/arm64-apple-macosx/release/SlapMe_SlapMe.bundle "$APP/Contents/Resources/"

# Sign with your Developer ID
codesign --force --deep --sign "Developer ID Application: YOUR NAME (TEAM_ID)" \
  --options runtime "$APP"

# Verify signature
codesign --verify --verbose "$APP"

# Package for notarization (use ditto, not zip — preserves code signature)
cd ../release
ditto -c -k --keepParent SlapMe.app SlapMe.zip

# Submit for notarization
xcrun notarytool submit SlapMe.zip --keychain-profile "notary" --wait

# Staple the notarization ticket to the app
xcrun stapler staple SlapMe.app

# Re-package the stapled app for distribution
rm SlapMe.zip
ditto -c -k --keepParent SlapMe.app SlapMe.zip
```

The resulting `SlapMe.zip` can be distributed to anyone — no Gatekeeper warnings.

### Step 5: Generate App Icon (optional)

If you modify the icon SVG (`web/public/app-icon.svg`):

```bash
# Create iconset from PNGs
mkdir -p /tmp/AppIcon.iconset
# Copy your icon PNGs with the naming convention icon_NxN.png and icon_NxN@2x.png
# Sizes needed: 16, 32, 128, 256, 512

# Convert to .icns
iconutil --convert icns /tmp/AppIcon.iconset --output SlapMe/SlapMe/Resources/AppIcon.icns
```

---

## How Slap Detection Works

### Microphone (default, all Macs)

The built-in mic picks up impact vibrations transmitted through the MacBook chassis. The engine tracks ambient noise level as a rolling baseline and detects sudden spikes (transients 3-10x above ambient) that indicate physical contact.

### Accelerometer (Apple Silicon M1 Pro+)

Apple Silicon MacBooks contain a hidden MEMS IMU (Bosch BMI286) accessible via IOKit HID on `AppleSPUHIDDevice` (usage page `0xFF00`, usage `3`). This gives real acceleration data in g-force at ~400Hz. Requires root access — the app tries this first and falls back to microphone.

To run with accelerometer support:

```bash
sudo .build/release/SlapMe
```

## Contributing

Contributions welcome. Please open an issue first to discuss what you'd like to change.

1. Fork the repo
2. Create your branch (`git checkout -b feat/my-feature`)
3. Commit your changes
4. Push to the branch
5. Open a Pull Request

## License

[MIT](LICENSE)
