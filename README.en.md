<div align="center">

<img src="SlowQ/SlowQ.png" width="112" alt="SlowQ">

# SlowQ

**Hold ⌘Q for 3 seconds to quit — no more accidental quits**

A tiny native macOS utility that takes over the global ⌘Q shortcut

[![Platform](https://img.shields.io/badge/macOS-13%2B-black?logo=apple&logoColor=white)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)](#project-layout)
[![UI](https://img.shields.io/badge/UI-AppKit-1E90FF)](#how-it-works)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)
[![Stars](https://img.shields.io/github/stars/PandaBoby/SlowQ?style=flat&color=yellow)](https://github.com/PandaBoby/SlowQ/stargazers)

[中文](README.md) · **English**

</div>

---

## What it does

On macOS, `⌘Q` quits the frontmost app **instantly** — one slip of the fingers and your unsaved draft, half-written document, or running job is gone.

SlowQ turns `⌘Q` into a deliberate action: press it and a countdown ring floats up in the center of the screen. **Hold for 3 seconds** to actually quit; **release early and nothing happens**. It intercepts `⌘Q` system-wide via a `CGEventTap`, so it works in **every app** with zero per-app setup.

> Inspired by Chrome's "Hold ⌘Q to quit".

## Features

|  |  |
|---|---|
| 🌐 **System-wide** | `CGEventTap`-based interception works in any app — no per-app configuration |
| ⏱️ **Adjustable delay** | Switch between 1 / 2 / 3 / 5 seconds from the menu bar; the choice is remembered |
| 🎨 **Polished HUD** | Dark glass card, spring entrance animation, blue→red gradient progress ring, pulse glow as it nears completion |
| 🔒 **Privacy first** | Logging is off by default; when enabled it records `⌘Q` events only — never other keystrokes |
| 🪶 **Featherweight** | Menu bar app, no Dock icon; the animation loop runs only while the HUD is visible |
| 🚫 **Instantly disableable** | Pause interception from the menu; quit SlowQ itself with `⌥⌘Q` so it never blocks itself |

## Preview

When you press `⌘Q`, this overlay appears in the center of the screen (the ring fills from blue to red as time runs out):

```text
        ╭──────────────────────────╮
        │            ⌘             │
        │         ╭──────╮         │
        │        ╱        ╲        │
        │       │   2.4    │       │
        │        ╲        ╱        │
        │         ╰──────╯         │
        │                          │
        │      Hold ⌘Q to quit     │
        ╰──────────────────────────╯
```

- **Hold until 0.0** → the caption changes to "release to quit"; letting go quits the app
- **Release early** → the overlay fades out and nothing happens

## Requirements

- macOS **13 (Ventura)** or later
- Xcode Command Line Tools to build (`xcode-select --install`)

## Install

Build from source (no prebuilt binaries yet):

```bash
git clone https://github.com/PandaBoby/SlowQ.git
cd SlowQ
./build-app.sh          # builds and packages SlowQ/SlowQ.app
open SlowQ/SlowQ.app
```

`build-app.sh` handles everything: generating the menu bar icon → compiling release → packaging the `.app` → producing the `.icns` → ad-hoc signing.

## ⚠️ Accessibility permission is required

macOS requires apps that intercept global keyboard events to hold the **Accessibility** permission. Without it, interception silently does nothing:

1. Launch `SlowQ.app`
2. Open **System Settings → Privacy & Security → Accessibility**
3. Find **SlowQ** and tick it (if it's not listed, add `SlowQ/SlowQ.app` with the `+` button)
4. SlowQ detects the grant automatically and starts working — no restart needed

Once granted, a snail icon appears in the menu bar. To verify it's active, check that `~/Library/Logs/SlowQ.log` contains `event tap 安装成功` (enable logging first — see below).

## Usage

**Intercepting ⌘Q**

- Press `⌘Q` in any app → overlay appears → hold for the configured duration → release to quit that app
- Release early → cancelled

**Menu bar**

| Menu item | Effect |
|---|---|
| Disable / Enable ⌘Q interception | Temporarily turn interception off (e.g. to quit several apps in a row) |
| Hold duration → 1/2/3/5 s | Adjust the hold time; persisted automatically |
| Menu bar icon: Color / Mono | Switch between the original colors and a monochrome template (mono adapts to light/dark menu bars) |
| Quit SlowQ (⌥⌘Q) | Quit SlowQ itself (`⌥⌘Q` avoids self-interception) |

## How it works

```text
   physical ⌘Q
      │
      ▼
┌─────────────────────────────┐
│  CGEventTap                 │  ← session-level, head insert: sees events before any app
│  (keyDown / keyUp / flags)  │
└─────────────┬───────────────┘
              │ swallow ⌘Q, start timer
              ▼
      ┌───────────────┐
      │  State machine│  idle → holding → fired
      │  while holding│  swallow all key repeats
      └───────┬───────┘
              │ threshold reached
              ▼
      ┌───────────────┐
      │ deliver a     │  postToPid sends one synthetic ⌘Q
      │ synthetic ⌘Q  │  (tap paused meanwhile to avoid self-interception)
      └───────────────┘
```

A few design notes:

- **Key repeats must be swallowed**: while a key is held, the system keeps re-sending `keyDown`. Swallowing only the first one lets the app quit from the repeats — that was the original "doesn't work" bug
- **`postToPid`, not `CGEventPost`**: the synthetic quit is delivered directly to the target process, bypassing the session tap, so it can't loop back into our own interception
- **Pause-window guard**: the tap is briefly disabled while delivering the synthetic event, and any **physical** `⌘Q` arriving in that window is still swallowed, so it can't be used to bypass the protection
- **Permission polling**: if not yet trusted at launch, SlowQ polls once per second and installs the tap as soon as the grant lands — no restart required

## Configuration

Settings persist via `UserDefaults` (domain `com.slowq.app`):

```bash
defaults write com.slowq.app holdSeconds -float 3            # hold duration (seconds)
defaults write com.slowq.app statusIconTemplate -bool true   # menu bar icon: mono template
defaults write com.slowq.app debugLog -bool true             # debug logging (off by default)

# tail the log
tail -f ~/Library/Logs/SlowQ.log
```

## Project layout

```text
SlowQ/
├── build-app.sh                  # one-shot build: icons → compile → package → sign
├── tools/
│   └── gen-statusbar.swift       # menu bar icon generator (crops padding, scales)
├── SlowQ/
│   ├── Package.swift             # SwiftPM manifest
│   ├── SlowQ.png / .svg          # icon source (replace + rebuild to change icons)
│   └── src/
│       ├── main.swift            # entry point
│       ├── AppDelegate.swift     # event tap + state machine + menu bar + HUD
│       └── Resources/            # generated menu bar icons (1x / 2x)
└── README.md / README.en.md
```

## Troubleshooting

**Interception does nothing**

1. Confirm the SlowQ icon is in the menu bar (if not, the process isn't running)
2. Check that Accessibility permission is ticked
3. **Permission can be invalidated by a rebuild**: the ad-hoc signature changes with the binary, so macOS no longer recognizes the app. Fix:
   ```bash
   tccutil reset Accessibility com.slowq.app
   # then relaunch SlowQ and tick it again in System Settings
   ```
   > Measured behaviour: merely toggling the switch off and on does **not** restore the grant — you must `tccutil reset` and re-tick.

**Icon invisible on a dark menu bar**

The current artwork is a pure black silhouette, so color mode is invisible against a dark menu bar. Switch to **Mono** in the menu to adapt automatically.

**Changing the icon**

Replace `SlowQ/SlowQ.png` (ideally a 1024×1024+ PNG with a transparent background) and re-run `./build-app.sh`.

## Development

```bash
cd SlowQ
swift build            # debug build
swift build -c release # release build
```

Re-run `./build-app.sh` after changing sources to repackage. Same command applies after swapping the icon source.

## License

Released under the [Apache License 2.0](LICENSE).

```text
Copyright 2026 PandaBoby

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0
```

<div align="center">

**[⬆ Back to top](#slowq)** · [中文 README](README.md)

</div>
