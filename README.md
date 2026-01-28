# Keyframe

A professional music performance system for live musicians and producers. Keyframe consists of two companion apps—a Mac desktop workstation and an iOS performance engine/remote controller—that work together seamlessly over your local network.

## Overview

**Keyframe Mac** is your creative studio: compose sessions with multiple songs, each containing sections with distinct plugin configurations, channel mixing, backing tracks, and keyboard zone assignments.

**Keyframe iOS** has two modes:
- **Local Mode**: A complete standalone performance engine with 4-channel mixing, full AUv3 hosting, built-in scale filtering, and chord generation
- **Remote Mode**: Control your Mac Keyframe session from your iPad

## Features

### Mac App

#### Session Management
- Document-based sessions with auto-save
- Songs → Sections hierarchy (Intro, Verse, Chorus, Bridge, etc.)
- Setlists for live performance ordering
- Complete state recall per section

#### Mixer & Plugins
- Multi-channel audio mixer with metering
- AU/VST3 plugin hosting (instruments + effects)
- Per-channel: 1 instrument + up to 4 insert effects
- Master bus with effects chain and limiter
- Full plugin state persistence

#### MIDI & Performance
- Keyboard zone splitting with per-zone transposition
- Built-in scale filtering (13 scale types)
- Diatonic chord engine
- MIDI Learn for controllers
- Song/section triggering via MIDI

#### Additional Features
- Network remote control via iOS
- Dark/Light mode
- BPM and key per song

### iOS App

#### Local Mode (Standalone Performance)
- 4-channel mixer with volume, pan, mute
- AUv3 instrument and effect hosting
- Built-in scale filtering and chord generation
- Session save/restore
- MIDI input from hardware controllers
- MIDI output (Network MIDI, Bluetooth)
- Background audio support

#### Remote Mode (Mac Controller)
- Automatic Mac discovery via Bonjour
- Preset/section grid for one-tap selection
- Bi-directional master volume sync
- Real-time section display
- Auto-reconnect on network changes

#### New Features (v1.1)
- **MIDI Freeze/Hold**: Sustain notes indefinitely via pedal (sustain or toggle mode)
- **Simple Looper**: Record from master output, loop playback survives preset changes

## Scale Types

Both apps include 13 built-in scale types:
- Major, Minor, Harmonic Minor, Melodic Minor
- Dorian, Phrygian, Lydian, Mixolydian, Locrian
- Pentatonic Major, Pentatonic Minor, Blues
- Chromatic

With two filter modes:
- **Snap**: Quantize out-of-scale notes to nearest scale degree
- **Block**: Silently drop out-of-scale notes

## Network Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Local Network                         │
│                                                          │
│  ┌──────────────────┐  TCP/Bonjour  ┌────────────────┐  │
│  │  Keyframe Mac    │◄─────────────►│  Keyframe iOS  │  │
│  │                  │               │  (Remote Mode) │  │
│  │  • Sessions      │  Broadcasts:  │                │  │
│  │  • Presets       │  • Section    │  • Discover    │  │
│  │  • Plugins       │  • Volume     │  • Select      │  │
│  │  • Backing       │               │  • Sync        │  │
│  └──────────────────┘               └────────────────┘  │
│                                                          │
│  ┌──────────────────┐                                   │
│  │  Keyframe iOS    │  (No network required)            │
│  │  (Local Mode)    │                                   │
│  │                  │                                   │
│  │  Standalone      │                                   │
│  │  Performance     │                                   │
│  └──────────────────┘                                   │
└─────────────────────────────────────────────────────────┘
```

## Requirements

### Mac App
- macOS 13.0 or later
- Apple Silicon or Intel

### iOS App
- iOS 15.0 or later
- iPhone or iPad

## Building

### Mac
```bash
cd KeyframeMac
open KeyframeMac.xcodeproj
# Build and run in Xcode
```

### iOS
```bash
cd iOS/Keyframe
open Keyframe.xcodeproj
# Build and run in Xcode
```

## Project Structure

```
keyframe/
├── KeyframeMac/                 # Mac app
│   ├── Engine/                  # Audio, MIDI, Plugin engines
│   ├── Models/                  # Session, Song, Preset models
│   ├── Network/                 # Bonjour discovery, TCP server
│   └── Views/                   # SwiftUI views
│
├── iOS/Keyframe/                # iOS app
│   ├── Engine/                  # Audio, MIDI, Looper engines
│   ├── Models/                  # Session, PerformanceSong models
│   ├── Network/                 # Bonjour browser, TCP client
│   └── Views/                   # SwiftUI views
│
└── README.md
```

## Design

Keyframe uses a design language inspired by Teenage Engineering:
- Minimal, focused interface
- Orange, cream, and black color palette
- Monospace typography
- High contrast for stage visibility

## License

Copyright © 2026. All rights reserved.

## Author

Built by Josh with Claude.
