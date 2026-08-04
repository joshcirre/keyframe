# Website and App Release Integration

The `website/` package is the public marketing, download, privacy, and support surface for the Mac and universal iPhone/iPad apps. It can be deployed independently while the native apps remain in the same repository.

## What is ready

- Next.js Node application in `website/`
- Product page positioning Keyframe as a focused alternative to Apple MainStage
- Mac download link that tracks the latest GitHub Release asset
- iPhone/iPad early-access card with TestFlight, App Store, and pending states
- `/privacy` route for App Store Connect
- `/support` route for App Store Connect
- `robots.txt`, `sitemap.xml`, Open Graph image, and app icon
- iOS privacy manifest declaring no tracking or collected data
- Universal iOS target configured for iPhone and iPad (`TARGETED_DEVICE_FAMILY = "1,2"`)
- App Store Connect record created for `com.keyframe.mki` (Apple ID `6797355107`)
- Mac App ID registered as `com.keyframe.mac`
- Mac 1.0 signed, notarized, and published as GitHub Release `v1.0.0`
- Existing App Group `group.com.keyframe.mki` verified in the developer team
- App Store listing copy, subtitle, categories, copyright, and manual-release mode saved
- App Store base price set to Free across all price territories
- Internal TestFlight group `Keyframe Team` created
- Laravel Cloud production environment running the Next.js site on Node 24

## Production configuration

Set these variables when the website is deployed:

```dotenv
NEXT_PUBLIC_SITE_URL=https://keyframeapp.com
# Optional override; otherwise the site uses the latest Keyframe-Mac.zip GitHub Release asset.
NEXT_PUBLIC_MAC_DOWNLOAD_URL=https://YOUR-SIGNED-MAC-ARTIFACT
NEXT_PUBLIC_IOS_TESTFLIGHT_URL=https://testflight.apple.com/join/YOUR-CODE
NEXT_PUBLIC_IOS_APP_STORE_URL=https://apps.apple.com/app/id6797355107
```

Every GitHub Release should upload the signed and notarized Mac build with the stable asset name `Keyframe-Mac.zip`. The website then resolves `https://github.com/joshcirre/keyframe/releases/latest/download/Keyframe-Mac.zip`, so routine releases do not require a Laravel Cloud environment change. `NEXT_PUBLIC_MAC_DOWNLOAD_URL` remains available as an override. Set the TestFlight variable only after the public invitation link is enabled. Set the App Store variable only after the product page is public; it takes precedence over TestFlight.

## Node deployment commands

Use Node 24 and run the package from the repository root:

```bash
cd website && npm ci && npm run build
cd website && npm run start
```

The production Laravel Cloud environment is configured with Node 24 and builds the `website/` package successfully. Push-to-deploy is enabled for `main`.

## Remaining release gates

1. Wait for App Review on iOS 1.0 build 1, respond to any review feedback, and manually release the approved version.
2. Wait for external TestFlight beta review. Once approved, set `NEXT_PUBLIC_IOS_TESTFLIGHT_URL=https://testflight.apple.com/join/1t2dse4k` and redeploy the site.
3. After the iOS product page is public at `https://apps.apple.com/app/id6797355107`, set `NEXT_PUBLIC_IOS_APP_STORE_URL` and redeploy the site.

The Mac build is public. Keep the iPhone/iPad early-access state until its TestFlight or App Store link resolves to an installable approved build.
