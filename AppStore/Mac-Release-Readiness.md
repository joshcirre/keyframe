# Keyframe Mac — Release Readiness Checklist

Use this as a preflight before cutting a Mac App Store build.

## 0) One-time setup
- [ ] Apple Developer account access
- [ ] App Store Connect app record exists (bundle id, SKU)
- [ ] Xcode signing set up for **Mac App Store** distribution
- [ ] Confirm required capabilities/entitlements (App Sandbox, Audio/MIDI/network as needed)

## 1) Build + archive sanity
- [ ] `KeyframeMac.xcodeproj` opens and builds cleanly on a fresh machine
- [ ] Archive succeeds (Product → Archive)
- [ ] No unexpected warnings that look like runtime issues (esp. sandbox/network)
- [ ] Version + build number bumped intentionally
- [ ] Confirm minimum macOS version matches listing (currently macOS 13+)

## 2) Sandboxing / permissions (common review blockers)
- [ ] App Sandbox enabled and the app still functions
- [ ] Local network discovery + connection works under sandbox (Bonjour + TCP)
- [ ] Microphone access is **not** requested unless actually needed
- [ ] Files: document-based workflow works (open/save, security-scoped bookmarks if used)
- [ ] MIDI device access works (CoreMIDI)
- [ ] Audio device access works (CoreAudio)

## 3) First-run UX + review mode
- [ ] App launches to a clean, non-empty state (sample session or empty-state UX)
- [ ] No crash on first run
- [ ] No "developer" UI exposed (debug menus, internal logging panels)
- [ ] Any network prompts are explained in-app (why local network is needed)

## 4) Regression sweep (15–30 min)
- [ ] Create new session → add song → add sections
- [ ] Mixer: adjust volume/pan/mute; meters animate
- [ ] Load at least one AU + one VST3 (if supported) and reopen session to verify restoration
- [ ] Keyboard zones: create at least 2 zones; verify routing/transposition
- [ ] Setlist: create setlist and reorder entries
- [ ] iOS Remote connects and can switch sections; volume sync stable

## 5) App Store artifacts
- [ ] Screenshots captured at required resolutions (see `Screenshots-Plan.md`)
- [ ] App description / keywords / promo text updated
- [ ] Support URL + Privacy Policy URL filled
- [ ] Notes for Review updated (local network / plugins / no account)

## 6) Submission sanity
- [ ] Run through App Store Connect checklist (`AppStoreConnect-Checklist.md`)
- [ ] Upload via Xcode Organizer
- [ ] Confirm processing completes; no ITMS errors

## Known current blocker
- Capturing screenshots + verifying Mac build requires access to a paired Mac node or an SSH tunnel to the loopback-only gateway.
  - Plan: see `Mac-Node-Pairing-and-Tunnel.md`.
