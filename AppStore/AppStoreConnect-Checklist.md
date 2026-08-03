# App Store Connect Submission Checklist

## Before You Start

### Developer Account Setup
- [x] Apple Developer Program membership active through March 23, 2027
- [x] Development certificate valid through January 6, 2027
- [x] Developer ID Application certificate valid through April 25, 2031
- [ ] Apple Distribution certificate available for App Store/TestFlight uploads
- [x] App IDs registered in Developer Portal
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
- [x] Create new app in App Store Connect (Apple ID `6797355107`)
- [x] Select "iOS" platform
- [x] Enter bundle ID: `com.keyframe.mki`
- [x] Set primary language: English (U.S.)
- [x] Set app name: "Keyframe - Live Performance"
- [x] Set internal SKU: `KEYFRAME-IOS-001`

### 2. App Information
- [x] Subtitle: "Synths, MIDI & Live Control"
- [x] Category: Music (Primary), Entertainment (Secondary)
- [ ] Content Rights: You own all content
- [ ] Age Rating: 4+

### 3. Pricing and Availability
- [ ] Set price (Free or Paid)
- [ ] Select availability (All countries or specific)
- [ ] Set pre-order if desired

### 4. App Privacy
- [ ] Deploy the website to the production domain
- [ ] Privacy Policy URL: `https://YOUR-PRODUCTION-DOMAIN/privacy` (required)
- [ ] Add the same privacy-policy link inside the iOS app in an easily accessible location
- [ ] Data collection:
  - [ ] Confirm the shipped app and every third-party SDK still match `PrivacyInfo.xcprivacy`
  - [ ] Select "No, we do not collect data from this app" while all audio, MIDI, session, and performance data remains on-device

### 5. Version Information
- [ ] Build number: Must be unique
- [ ] What's New text (for updates)
- [x] Version number: 1.0
- [x] Description (from iOS-AppStore.md)
- [x] Keywords (99 of 100 characters)
- [ ] Support URL: `https://YOUR-PRODUCTION-DOMAIN/support`
- [ ] Confirm the support page contains working contact information before submission
- [ ] Marketing URL: `https://YOUR-PRODUCTION-DOMAIN` (optional)

### 6. Screenshots (Required)
| Device | Size | Required |
|--------|------|----------|
| iPhone 6.9" | 1260 x 2736, 1290 x 2796, or 1320 x 2868 | Yes |
| iPhone 6.5" | 1284 x 2778 or 1242 x 2688 | Only if 6.9" isn't supplied |
| iPad 13" | 2064 x 2752 or 2048 x 2732 | Yes |

- [ ] Upload 1-10 screenshots per required device family, with no alpha channel
- [ ] App preview video (optional, 15-30 seconds)
- [ ] Recheck [Apple's screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) before upload

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
  - Network access is for Remote Mode between Keyframe devices (local network only, no internet)
  - Bluetooth is for wireless MIDI controllers
  - No account required
  ```

### 9. Submit
- [ ] All fields complete
- [ ] Submit for review
- [x] Manual release selected to prevent automatic publication after approval

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
- [x] Website/landing page package created (`website/`)
- [ ] Production domain and Laravel Cloud environment configured
- [ ] Signed and notarized Mac artifact published
- [ ] `NEXT_PUBLIC_MAC_DOWNLOAD_URL` points to that artifact
- [ ] Add `NEXT_PUBLIC_IOS_APP_STORE_URL` after the App Store product page is available
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
