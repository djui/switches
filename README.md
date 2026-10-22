# Switches

<!-- GateGuard: supersedes nothing — edits existing README; linked from GitHub repo home; user asked for GH Pages landing. -->
Landing page: [djui.github.io/switches](https://djui.github.io/switches/) (served from `/docs` via GitHub Pages).

A native macOS menu bar app that plays mechanical keyboard sounds on every key press and
release. Each key sounds from where it sits on the keyboard (left keys on the left, right
keys on the right), with small random pitch and volume changes so typing never sounds
robotic.

- Swift 6 / SwiftUI, macOS 15+, no third-party runtime dependencies
- Real-time-safe audio path: `AVAudioEngine` + `AVAudioSourceNode`, lock-free trigger
  queue, 32-voice mixer, 64–128 frame buffers (≈1.5–3 ms)
- Themes: Cardboard, Milky Yellow and eight Cherry MX packs (Black/Blue/Brown/Red, ABS/PBT)
- Pausing: menu toggle, global hotkey **⌃⌥⌘K**, excluded apps, games, full-screen apps and
  secure text entry
- Settings: volume, theme, stereo width, headphone mode, pitch/volume variation, key-up
  level, keyboard layout (ANSI/ISO/JIS), launch at login

## Requirements

- Xcode 16 or newer (macOS 15 SDK)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- For reconverting sounds only: [ffmpeg](https://ffmpeg.org) (`brew install ffmpeg`) to decode
  the Mechvibes OGG files
- For releases only: [GitHub CLI](https://cli.github.com) (`gh auth login`)

## Build and install

```sh
make build      # Release build -> build/Switches.app
make install    # build, replace /Applications/Switches.app, restart it
make test       # SwitchesCore unit tests
make release    # test, bump version, commit, tag, push, GitHub Release, install
```

`Switches.xcodeproj` is generated from `project.yml` and not checked in; run
`make generate` (or `xcodegen generate`) to open the project in Xcode.

`scripts/build_release.sh` signs with your **Apple Development** identity if one is in the
keychain (override with `DEVELOPMENT_TEAM=XXXXXXXXXX`), otherwise ad-hoc. Keep using the
same identity for local installs, otherwise macOS forgets the Input Monitoring grant.
`scripts/build_release.sh --notarize` exports with Developer ID and notarizes (needs
`NOTARY_PROFILE`, a `notarytool` keychain profile).

## Permissions

Switches needs **Input Monitoring** (System Settings › Privacy & Security › Input
Monitoring). It uses a listen-only event tap and only ever sees virtual key codes, never
characters. Accessibility permission is **not** required. The app is sandboxed and has no
network access.

On first launch an onboarding window explains the permission and opens System Settings.
Switches starts listening as soon as the permission is granted.

## Themes

Raw packs live in `Sounds/` and are converted **once** into the runtime format the app
bundles from `Switches/Resources/Themes/`:

```sh
make convert-sounds   # swift scripts/convert_sounds.swift
```

Supported source formats:

| Format | Layout |
| --- | --- |
| Per-key WAV | `Sounds/<Name>/{mechvibesID}-down.wav`, `{mechvibesID}-up.wav` |
| Mechvibes "single" | `Sounds/<Name>/config.json` + one sound file sliced by `defines: {id: [offsetMs, lengthMs]}` |

The converter maps Mechvibes key IDs to macOS `CGKeyCode`s (table in
`Packages/SwitchesCore/Sources/SwitchesCore/Input/MechvibesKeyMap.swift`), trims silence
lightly, derives key-up sounds where a pack has none (−4 dB, 60 % length), and peak-
normalizes each theme to −1 dBFS.

Output per theme (`Switches/Resources/Themes/<Name>/`):

- `{cgKeyCode}-down.caf` / `{cgKeyCode}-up.caf`: 48 kHz, mono, 16-bit linear PCM
- `theme.json`:

```json
{
  "formatVersion": 1,
  "name": "Cardboard",
  "sampleRate": 48000,
  "channels": 1,
  "source": "per-key-wav",
  "keys": { "0": { "down": "0-down.caf", "up": "0-up.caf" } },
  "fallbacks": { "alpha": 0, "space": 49, "enter": 36, "backspace": 51, "modifier": 56 }
}
```

Keys without their own sample use the `fallbacks` entry for their group (alpha, space,
enter, backspace, modifier). Every folder under `Themes/` with a `theme.json` shows up in
the theme picker under its folder name. To add a pack, drop it into `Sounds/`, run
`make convert-sounds` and rebuild.

## Project layout

```
project.yml                     XcodeGen spec (app target + local package)
Switches/                       App target: SwitchesApp, UI/, Assets, Info.plist
Switches/Resources/Themes/      Converted themes bundled into the app
Packages/SwitchesCore/          Audio/, Input/, Packs/, Control/ + unit tests
Sounds/                         Raw source packs (conversion input only)
docs/                           GitHub Pages landing site
scripts/                        convert_sounds, make_icons, build/install/release
```

## Website (GitHub Pages)

Static site in [`docs/`](docs/). Enable once:

1. Repo **Settings → Pages**
2. Source: **Deploy from a branch**
3. Branch: `main` / folder `/docs`

Or via CLI: `gh api -X PUT repos/djui/switches/pages -f build_type=legacy -f source[branch]=main -f source[path]=/docs`

Site URL: https://djui.github.io/switches/
