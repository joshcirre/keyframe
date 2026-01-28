# App Store Connect Submission Checklist

## Before You Start

### Developer Account Setup
- [ ] Apple Developer Program membership active ($99/year)
- [ ] Certificates created (Development + Distribution)
- [ ] App IDs registered in Developer Portal
- [ ] Provisioning profiles created

### App IDs to Register
```
iOS App: com.keyframe.mki (or your bundle ID)
Mac App: com.keyframe.mac (or your bundle ID)
App Group: group.com.keyframe.mki (for shared data)
```

---

## iOS App Submission

### 1. App Store Connect Setup
- [ ] Create new app in App Store Connect
- [ ] Select "iOS" platform
- [ ] Enter bundle ID: `com.keyframe.mki`
- [ ] Set primary language
- [ ] Set app name: "Keyframe - Live Performance"

### 2. App Information
- [ ] Subtitle: "Synths, MIDI & Live Control"
- [ ] Category: Music (Primary), Entertainment (Secondary)
- [ ] Content Rights: You own all content
- [ ] Age Rating: 4+

### 3. Pricing and Availability
- [ ] Set price (Free or Paid)
- [ ] Select availability (All countries or specific)
- [ ] Set pre-order if desired

### 4. App Privacy
- [ ] Privacy Policy URL (required)
- [ ] Data collection:
  - [ ] "Data Not Collected" (if no analytics)
  - [ ] OR specify: Audio Data (for looper, not shared)

### 5. Version Information
- [ ] Version number: 1.0 (or 1.1)
- [ ] Build number: Must be unique
- [ ] What's New text (for updates)
- [ ] Description (from iOS-AppStore.md)
- [ ] Keywords (100 chars max)
- [ ] Support URL
- [ ] Marketing URL (optional)

### 6. Screenshots (Required)
| Device | Size | Required |
|--------|------|----------|
| iPhone 6.7" | 1290 x 2796 | Yes |
| iPhone 6.5" | 1284 x 2778 | Yes |
| iPhone 5.5" | 1242 x 2208 | Optional |
| iPad Pro 12.9" | 2048 x 2732 | Yes (if iPad app) |

- [ ] Upload 3-10 screenshots per device
- [ ] App preview video (optional, 15-30 seconds)

### 7. Build Upload
```bash
# In Xcode:
# 1. Select "Any iOS Device" as destination
# 2. Product → Archive
# 3. Window → Organizer → Distribute App
# 4. Select "App Store Connect" → Upload
```
- [ ] Archive created
- [ ] Build uploaded via Xcode
- [ ] Build processing complete (wait for email)
- [ ] Build selected in App Store Connect

### 8. App Review Information
- [ ] Contact info (name, phone, email)
- [ ] Demo account (not needed for Keyframe)
- [ ] Notes for review:
  ```
  - Background audio is used for uninterrupted playback during performance
  - Network access is for Remote Mode (local network only, no internet)
  - Bluetooth is for wireless MIDI controllers
  - No account required
  ```

### 9. Submit
- [ ] All fields complete
- [ ] Submit for review
- [ ] Expected review time: 24-48 hours

---

## Mac App Submission

### 1. App Store Connect Setup
- [ ] Create new app (or add macOS platform to existing)
- [ ] Select "macOS" platform
- [ ] Enter bundle ID: `com.keyframe.mac`
- [ ] Set app name: "Keyframe - Live Performance"

### 2. macOS-Specific Requirements

#### Hardened Runtime
In Xcode → Target → Signing & Capabilities:
- [ ] Hardened Runtime enabled
- [ ] Audio Input entitlement (if recording)
- [ ] Network Client/Server entitlements

#### Sandbox (App Store requirement)
- [ ] App Sandbox enabled
- [ ] Network: Outgoing Connections (Server)
- [ ] Network: Incoming Connections (Client)
- [ ] Audio Input (if needed)
- [ ] User Selected File access (for sessions)

#### Notarization
```bash
# If distributing outside App Store:
xcrun notarytool submit YourApp.zip --apple-id YOUR_ID --team-id TEAM_ID --password APP_PASSWORD
```

### 3. Screenshots (Required)
| Size | Notes |
|------|-------|
| 1280 x 800 | Minimum |
| 1440 x 900 | Standard |
| 2560 x 1600 | Retina |
| 2880 x 1800 | Retina |

- [ ] Upload at least one size
- [ ] Show key features

### 4. Build Upload
```bash
# In Xcode:
# 1. Select "My Mac" as destination
# 2. Product → Archive
# 3. Window → Organizer → Distribute App
# 4. Select "App Store Connect" → Upload
```

### 5. Submit
- [ ] All fields complete
- [ ] Submit for review

---

## Common Rejection Reasons & Fixes

### 1. Metadata Issues
- **Missing privacy policy**: Host a simple privacy policy page
- **Misleading screenshots**: Use actual app screenshots, not mockups
- **Incomplete description**: Be specific about what the app does

### 2. Functionality Issues
- **Crashes on launch**: Test on clean device/simulator
- **Features don't work**: Test all advertised features
- **Placeholder content**: Remove "Coming Soon" or "TODO" items

### 3. Design Issues
- **Non-native UI**: Use standard iOS/macOS patterns
- **Low-res assets**: Use @2x and @3x images

### 4. Legal Issues
- **Third-party content**: Ensure you have rights to all content
- **Trademark issues**: Don't use others' trademarks

---

## Post-Submission

### After Approval
- [ ] App goes live (or scheduled release)
- [ ] Monitor reviews and ratings
- [ ] Respond to user feedback
- [ ] Plan next update

### If Rejected
- [ ] Read rejection reason carefully
- [ ] Fix the specific issue
- [ ] Resubmit with explanation in notes
- [ ] Use Resolution Center for questions

---

## Marketing Checklist

### Launch Preparation
- [ ] Website/landing page
- [ ] Press kit with screenshots
- [ ] Social media announcement
- [ ] Demo video for YouTube

### App Store Optimization (ASO)
- [ ] Research competitor keywords
- [ ] A/B test screenshots
- [ ] Localize for key markets
- [ ] Encourage reviews from beta testers

---

## Resources

- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Human Interface Guidelines - iOS](https://developer.apple.com/design/human-interface-guidelines/ios)
- [Human Interface Guidelines - macOS](https://developer.apple.com/design/human-interface-guidelines/macos)
- [App Store Connect Help](https://help.apple.com/app-store-connect/)
