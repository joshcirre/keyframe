# Keyframe MK I

A custom iOS MIDI controller app designed for live performance with AUM. Features:

- **Virtual MIDI Controller**: Send presets to AUM with one tap
- **AUv3 Scale Filter**: Keep your playing in key with block or snap modes
- **NM2 Chord Triggers**: Turn your This is Noise NM2 into a diatonic chord pad

## Requirements

- iOS 15.0+
- Xcode 15.0+
- Apple Developer Account (required for App Groups and AUv3)

## Setup

### 1. Configure Signing

1. Open `KeyframeMKI.xcodeproj` in Xcode
2. Select the KeyframeMKI target
3. Set your Development Team
4. Do the same for the ScaleFilterAU target
5. Update the bundle identifiers if needed:
   - Main app: `com.yourname.keyframemki`
   - Extension: `com.yourname.keyframemki.ScaleFilterAU`

### 2. Configure App Group

The App Group ID is set to `group.com.keyframe.mki`. If you changed the bundle identifier, update:
- `KeyframeMKI/KeyframeMKI.entitlements`
- `ScaleFilterAU/ScaleFilterAU.entitlements`
- `Shared/Constants.swift` (AppConstants.appGroupID)

### 3. Build & Run

1. Connect your iPhone
2. Select your device in Xcode
3. Build and run (⌘R)

## AUM Configuration

### Add Keyframe MK I as MIDI Source

1. In AUM, go to **MIDI Sources**
2. Add **"Keyframe MK I"** as a control source
3. Map CC numbers to channel faders:
   - CC 70 → Channel 1 Volume
   - CC 71 → Channel 2 Volume
   - CC 72 → Channel 3 Volume
   - CC 73 → Channel 4 Volume
4. Map CC numbers to plugin bypass:
   - CC 80-87 → Plugin 1-8 bypass

### Add Scale Filter AUv3

1. On each MIDI track receiving controller input:
2. Add an audio effect
3. Find **"Keyframe: Scale Filter"** under MIDI Effects
4. The filter will automatically use the current song's scale

### Configure NM2 Controller

1. Set your NM2 to transmit on MIDI Channel 10 (or configure in app Settings)
2. The Scale Filter will convert single notes to diatonic triads

## Usage

### Song Management

- **Tap** a song button to activate it and send the preset
- **Long press** to edit the song
- **Tap +** to add a new song

### Each Song Contains

- **Name**: Display name
- **Key**: Root note (C-B) and scale (Major/Minor)
- **Filter Mode**: 
  - Block: Drop notes outside the scale
  - Snap: Quantize to nearest scale note
- **Channel Levels**: Volume presets for 4 channels
- **Plugin States**: On/off states for 8 plugins

### Chord Map (NM2)

- Tap the piano icon to configure NM2 button → chord mappings
- Each button can trigger any scale degree (I-VII)
- Chords automatically transpose to the active song's key

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      iPhone                                  │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────┐    ┌──────────────────────────────┐  │
│  │  Keyframe MK I   │    │           AUM                 │  │
│  │      App         │    │                               │  │
│  │                  │    │  ┌────────┐ ┌────────┐       │  │
│  │ ┌──────────────┐ │    │  │ Ch 1   │ │ Ch 2   │       │  │
│  │ │ Song Grid    │ │    │  │ + AU   │ │ + AU   │       │  │
│  │ └──────────────┘ │    │  └────────┘ └────────┘       │  │
│  │        │         │    │  ┌────────┐ ┌────────┐       │  │
│  │        ▼         │    │  │ Ch 3   │ │ Ch 4   │       │  │
│  │ ┌──────────────┐ │    │  │ + AU   │ │ + AU   │       │  │
│  │ │ MIDI Service │─┼────┼─▶└────────┘ └────────┘       │  │
│  │ │ (Virtual Src)│ │    │                               │  │
│  │ └──────────────┘ │    │  Scale Filter AUv3 on each   │  │
│  │        │         │    │  track filters/triggers chords│  │
│  └────────┼─────────┘    └──────────────────────────────┘  │
│           │                             ▲                   │
│           ▼                             │                   │
│  ┌──────────────────┐                   │                   │
│  │  App Group       │                   │                   │
│  │  (Shared Data)   │───────────────────┘                   │
│  │                  │                                       │
│  │  • Active Song   │                                       │
│  │  • Chord Mapping │                                       │
│  └──────────────────┘                                       │
│                                                              │
│  USB MIDI Controllers ──────────▶ AUM ──▶ Scale Filter AUv3 │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Files Overview

### Main App

| File | Purpose |
|------|---------|
| `KeyframeMKIApp.swift` | App entry point |
| `ContentView.swift` | Main song grid UI |
| `SongButton.swift` | Tappable song buttons |
| `SongEditorView.swift` | Song configuration |
| `ChordMapView.swift` | NM2 chord mapping |
| `SettingsView.swift` | App settings |
| `MIDIService.swift` | CoreMIDI virtual source |

### Shared Framework

| File | Purpose |
|------|---------|
| `Constants.swift` | App configuration, scale/chord definitions |
| `ScaleEngine.swift` | Scale filtering logic |
| `ChordEngine.swift` | Diatonic triad generation |
| `SharedSongStore.swift` | App Group data persistence |
| `ChordMapping.swift` | NM2 button → chord mapping |

### AUv3 Extension

| File | Purpose |
|------|---------|
| `ScaleFilterAU.swift` | Audio Unit entry point |
| `ScaleFilterAudioUnit.swift` | MIDI processing kernel |
| `ScaleFilterAUView.swift` | Plugin UI |

## Troubleshooting

### MIDI not showing in AUM
- Ensure the app is running in the foreground at least once
- Check that "Keyframe MK I" appears in MIDI Sources
- Try restarting AUM

### Scale Filter not loading
- Ensure you've run the app at least once
- Check that the extension is enabled in Settings → Privacy → Extensions → Audio Unit Extensions

### Chords not triggering
- Verify NM2 is sending on the correct channel (default: Ch 10)
- Check that buttons are mapped in the Chord Map view
- Ensure a song is selected in the main app

## License

MIT License - Use freely for your own live rig!
