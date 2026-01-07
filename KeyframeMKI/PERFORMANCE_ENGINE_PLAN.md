# Keyframe Performance Engine

Transform Keyframe MK I from an AUM controller into a **standalone AUv3 host** - your personal performance instrument.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        KEYFRAME PERFORMANCE ENGINE                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────┐    ┌─────────────────┐    ┌─────────────────────────┐    │
│  │ MIDI Input   │───▶│  Scale Filter   │───▶│  Channel Router         │    │
│  │ (Controllers)│    │  + Chord Engine │    │  (Route to instruments) │    │
│  └──────────────┘    └─────────────────┘    └───────────┬─────────────┘    │
│                                                          │                   │
│  ┌──────────────────────────────────────────────────────┼──────────────┐   │
│  │                     CHANNEL STRIPS                    ▼              │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │   │
│  │  │ Channel 1   │  │ Channel 2   │  │ Channel 3   │  │ Channel 4   │ │   │
│  │  │ ─────────── │  │ ─────────── │  │ ─────────── │  │ ─────────── │ │   │
│  │  │ Instrument  │  │ Instrument  │  │ Instrument  │  │ Instrument  │ │   │
│  │  │ (AUv3)      │  │ (AUv3)      │  │ (AUv3)      │  │ (AUv3)      │ │   │
│  │  │     ↓       │  │     ↓       │  │     ↓       │  │     ↓       │ │   │
│  │  │ Insert FX 1 │  │ Insert FX 1 │  │ Insert FX 1 │  │ Insert FX 1 │ │   │
│  │  │ Insert FX 2 │  │ Insert FX 2 │  │ Insert FX 2 │  │ Insert FX 2 │ │   │
│  │  │     ↓       │  │     ↓       │  │     ↓       │  │     ↓       │ │   │
│  │  │ Vol/Pan/Mute│  │ Vol/Pan/Mute│  │ Vol/Pan/Mute│  │ Vol/Pan/Mute│ │   │
│  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘ │   │
│  └─────────┼────────────────┼────────────────┼────────────────┼────────┘   │
│            └────────────────┴────────┬───────┴────────────────┘            │
│                                      ▼                                      │
│                           ┌─────────────────┐                               │
│                           │   MASTER BUS    │                               │
│                           │  Master FX      │                               │
│                           │  Master Volume  │                               │
│                           │  Limiter        │                               │
│                           └────────┬────────┘                               │
│                                    ▼                                        │
│                           ┌─────────────────┐                               │
│                           │  Audio Output   │                               │
│                           │  (Headphones/   │                               │
│                           │   Interface)    │                               │
│                           └─────────────────┘                               │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. Audio Engine (`AudioEngine.swift`)
- Built on `AVAudioEngine`
- Manages the entire audio graph
- Handles latency and buffer configuration
- Background audio support

### 2. Channel Strip (`ChannelStrip.swift`)
- Instrument slot (AUv3 synthesizer/sampler)
- Insert effects chain (up to 4 AUv3 effects)
- Volume, Pan, Mute, Solo controls
- MIDI channel assignment
- Meter levels

### 3. AUv3 Host Manager (`AUv3HostManager.swift`)
- Discover installed AUv3 plugins
- Categorize: Instruments vs Effects
- Instantiate and configure plugins
- Present plugin UIs
- Save/restore plugin state

### 4. MIDI Engine (`MIDIEngine.swift`)
- External MIDI input handling
- Per-channel MIDI routing
- **Built-in scale filtering** (no separate plugin needed!)
- **Built-in chord engine** for NM2
- Virtual MIDI ports for external apps

### 5. Preset System (`PerformancePreset.swift`)
- **Song presets now control everything directly:**
  - Channel volumes (instant, no MIDI CC needed)
  - Plugin bypass states
  - Scale/key settings
  - BPM (sent to plugins that support tempo)
- Entire session configurations can be saved

### 6. Master Bus (`MasterBus.swift`)
- Sum of all channels
- Master insert effects (reverb, delay sends)
- Master limiter for protection
- Master volume control

## Data Models

### Session
```swift
struct Session: Codable {
    var name: String
    var channels: [ChannelConfiguration]
    var masterEffects: [PluginState]
    var masterVolume: Float
    var songs: [Song]  // Existing song model with presets
}
```

### ChannelConfiguration
```swift
struct ChannelConfiguration: Codable {
    var id: UUID
    var name: String
    var instrumentPlugin: PluginState?
    var insertEffects: [PluginState]
    var midiChannel: Int  // Which MIDI channel routes here (1-16, 0 = omni)
    var volume: Float     // 0.0 - 1.0
    var pan: Float        // -1.0 to 1.0
    var isMuted: Bool
    var isSoloed: Bool
    var scaleFilterEnabled: Bool
    var isNM2ChordChannel: Bool  // For the NM2 chord trigger
}
```

### PluginState
```swift
struct PluginState: Codable {
    var audioComponentDescription: Data  // Encoded AudioComponentDescription
    var manufacturerName: String
    var pluginName: String
    var presetData: Data?  // AUv3 full state
    var isBypassed: Bool
}
```

### Updated Song/Preset
```swift
struct Song {
    // ... existing fields ...
    
    // Now controls channels directly (not MIDI CC)
    var channelStates: [ChannelPresetState]
}

struct ChannelPresetState: Codable {
    var channelId: UUID
    var volume: Float?      // nil = don't change
    var pan: Float?
    var muted: Bool?
    var effectBypasses: [Bool]?  // Per-effect bypass states
}
```

## UI Updates

### Main Performance View
```
┌─────────────────────────────────────────────┐
│  KEYFRAME PERFORMANCE              ⚙️  │
├─────────────────────────────────────────────┤
│  NOW PLAYING: Chorus | G Major | 128 BPM    │
├─────────────────────────────────────────────┤
│                                             │
│  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐           │
│  │ CH1 │ │ CH2 │ │ CH3 │ │ CH4 │  ← Tap    │
│  │ Pad │ │Bass │ │Keys │ │Lead │    for    │
│  │ ▮▮▮ │ │ ▮▮  │ │▮▮▮▮ │ │ ▮   │    detail │
│  │ 80% │ │100% │ │ 70% │ │ 50% │           │
│  │ [M] │ │ [M] │ │ [M] │ │ [M] │           │
│  └─────┘ └─────┘ └─────┘ └─────┘           │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │          SONG PRESETS               │   │
│  │  [Intro] [Verse] [Chorus] [Bridge]  │   │
│  │  [Outro] [+Add]                     │   │
│  └─────────────────────────────────────┘   │
│                                             │
├─────────────────────────────────────────────┤
│  🎹 MIDI: 4 devices  |  CPU: 12%  |  🔊 -3dB │
└─────────────────────────────────────────────┘
```

### Channel Detail View (slide up)
```
┌─────────────────────────────────────────────┐
│  CHANNEL 1: Synth Pad              [Close]  │
├─────────────────────────────────────────────┤
│  INSTRUMENT                                 │
│  ┌─────────────────────────────────────┐   │
│  │  🎹 Moog Model D                    │   │
│  │  [Open UI]  [Change]  [Bypass]      │   │
│  └─────────────────────────────────────┘   │
│                                             │
│  INSERT EFFECTS                             │
│  ┌─────────────────────────────────────┐   │
│  │  1. Valhalla Delay    [UI] [⏻]      │   │
│  │  2. FabFilter Pro-R   [UI] [⏻]      │   │
│  │  3. [Empty Slot]      [+ Add]       │   │
│  └─────────────────────────────────────┘   │
│                                             │
│  CHANNEL SETTINGS                           │
│  Volume: ════════════●══  80%              │
│  Pan:    ════●══════════  -20              │
│  MIDI Channel: [3 ▼]                        │
│  Scale Filter: [ON]                         │
│                                             │
└─────────────────────────────────────────────┘
```

## Implementation Phases

### Phase 1: Audio Engine Foundation
- [ ] Create `AudioEngine` with `AVAudioEngine`
- [ ] Implement basic channel strips (4 channels)
- [ ] Master bus with volume control
- [ ] Background audio entitlement
- [ ] Basic audio output routing

### Phase 2: AUv3 Hosting
- [ ] Create `AUv3HostManager`
- [ ] Plugin discovery and categorization
- [ ] Load instrument AUv3 into channel
- [ ] Load effect AUv3 into insert slots
- [ ] Plugin UI presentation (in-app hosting)
- [ ] Save/restore plugin state

### Phase 3: MIDI Integration
- [ ] Create integrated `MIDIEngine`
- [ ] Route MIDI to channels based on channel assignment
- [ ] Built-in scale filtering (move from AUv3 to engine)
- [ ] Built-in NM2 chord triggering
- [ ] MIDI activity indicators

### Phase 4: Preset System
- [ ] Update `Song` model for direct channel control
- [ ] Instant channel state changes on song select
- [ ] Plugin bypass state per song
- [ ] Session save/load

### Phase 5: UI Polish
- [ ] Performance view with channel strips
- [ ] Channel detail view
- [ ] Plugin browser
- [ ] Meters and visual feedback
- [ ] CPU/memory monitoring

### Phase 6: Advanced Features
- [ ] Send/Return effects buses
- [ ] Audio input channels (for external synths)
- [ ] MIDI output to external hardware
- [ ] Setlist mode (ordered song playback)
- [ ] Tap tempo

## Technical Notes

### Audio Session Configuration
```swift
let session = AVAudioSession.sharedInstance()
try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
try session.setPreferredIOBufferDuration(0.005) // 5ms for low latency
try session.setActive(true)
```

### AUv3 Discovery
```swift
let componentDescription = AudioComponentDescription(
    componentType: kAudioUnitType_MusicDevice,  // For instruments
    componentSubType: 0,
    componentManufacturer: 0,
    componentFlags: 0,
    componentFlagsMask: 0
)

AVAudioUnitComponentManager.shared().components(matching: componentDescription)
```

### Connecting AUv3 to Audio Graph
```swift
// Instantiate the plugin
AVAudioUnit.instantiate(with: description, options: []) { audioUnit, error in
    guard let audioUnit = audioUnit else { return }
    
    // Attach to engine
    engine.attach(audioUnit)
    
    // Connect in chain
    engine.connect(audioUnit, to: channelMixer, format: format)
}
```

## Benefits Over AUM Setup

| Feature | AUM + Keyframe | Keyframe Performance |
|---------|---------------|---------------------|
| Preset switching | MIDI CC messages | Instant direct control |
| Scale filtering | Separate AUv3 per channel | Built-in, zero latency |
| Setup complexity | Configure AUM + app | Single app |
| Preset recall | Limited to MIDI CC | Full channel state |
| CPU efficiency | Two apps running | Single optimized app |
| Customization | Limited by AUM | Fully customizable |

## File Structure

```
KeyframeMKI/
├── Engine/
│   ├── AudioEngine.swift
│   ├── ChannelStrip.swift
│   ├── MasterBus.swift
│   ├── MIDIEngine.swift
│   └── AUv3HostManager.swift
├── Models/
│   ├── Session.swift
│   ├── ChannelConfiguration.swift
│   ├── PluginState.swift
│   └── Song.swift (updated)
├── Views/
│   ├── PerformanceView.swift
│   ├── ChannelStripView.swift
│   ├── ChannelDetailView.swift
│   ├── PluginBrowserView.swift
│   ├── PluginHostView.swift
│   └── SongPresetView.swift
└── ...
```

## Getting Started

Ready to transform Keyframe into a performance engine? Let's start with Phase 1!
