# Keyframe — App Store Screenshots Plan (Mac)

Goal: produce a coherent set of Mac App Store screenshots that communicate value fast and avoid review issues (no personal data, no copyrighted plugin branding unless you own rights, no external accounts).

## Target sizes (Mac App Store)
Apple accepts multiple sizes; easiest is to export at least:
- 1280×800
- 1440×900
- 2560×1600
- 2880×1800

Tip: capture at native resolution for the chosen simulator/display scale, then crop to exact aspect ratio.

## Global capture rules
- Use a **demo session** with fictional song names (no real setlist venues, no personal notes).
- Disable notifications (Do Not Disturb) during capture.
- Keep the app window clean: no debug overlays, no transient toasts.
- Avoid showing 3rd‑party plugin UIs if branding/licensing is unclear; prefer showing Keyframe’s own plugin hosting chrome.
- Capture both Light and Dark mode if it helps; otherwise pick the most readable mode.

## Screenshot set (recommended 6)

### 1) "Professional Mixer"
**Screen:** Mixer view with multiple channels, meters active.
- Show 3–4 channels with instrument slots + insert slots populated.
- If CPU meter exists, keep it reasonable.

### 2) "Songs → Sections"
**Screen:** Song list with sections expanded.
- Use names like: "Neon Skyline" → Intro / Verse / Chorus / Bridge.
- Make sure selection highlights a section.

### 3) "Instant Recall"
**Screen:** A section/preset editor showing per-section parameters.
- Show that each section stores state (plugin chain, levels, scale/chord settings).

### 4) "Keyboard Zones"
**Screen:** Zone editor with visual keyboard.
- Show at least two colored ranges.
- Include transposition labels if possible.

### 5) "Setlists for the gig"
**Screen:** Setlist view with ordering and notes.
- Notes should be generic ("Count-in", "Pad only", etc.).

### 6) "iPad Remote Connected"
**Screen:** Mac UI showing connected iOS remote indicator + section switching UI.
- Avoid including IP addresses if possible.

## Capture checklist (per screenshot)
- [ ] App in final theme + typography
- [ ] No permission dialogs visible
- [ ] Cursor positioned intentionally (or hidden)
- [ ] Window size set to match target aspect ratio before capture
- [ ] Export PNG

## Post-processing
- Crop to exact pixel sizes above.
- Optional: add short caption strips (if you have a template), but keep consistent.
- Name files predictably:
  - `mac_01_mixer_2880x1800.png`
  - `mac_02_songs_sections_2880x1800.png`
  - etc.

## Blocker / prerequisites
Requires a Mac machine (physical or node) with KeyframeMac buildable, plus a known-good demo session file.
