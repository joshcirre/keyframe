# Website and App Release Integration

The `website/` package is the public marketing, download, privacy, and support surface for the Mac and universal iPhone/iPad apps. It can be deployed independently while the native apps remain in the same repository.

## What is ready

- Next.js Node application in `website/`
- Product page positioning Keyframe as a focused alternative to Apple MainStage
- Mac release link with an honest release-prep fallback
- iPhone/iPad early-access card with TestFlight, App Store, and pending states
- `/privacy` route for App Store Connect
- `/support` route for App Store Connect
- `robots.txt`, `sitemap.xml`, Open Graph image, and app icon
- iOS privacy manifest declaring no tracking or collected data
- Universal iOS target configured for iPhone and iPad (`TARGETED_DEVICE_FAMILY = "1,2"`)
- App Store Connect record created for `com.keyframe.mki` (Apple ID `6797355107`)
- Mac App ID registered as `com.keyframe.mac`
- Existing App Group `group.com.keyframe.mki` verified in the developer team
- App Store listing copy, subtitle, categories, copyright, and manual-release mode saved
- App Store base price set to Free across all price territories
- Internal TestFlight group `Keyframe Team` created
- Laravel Cloud production environment running the Next.js site on Node 24

## Production configuration

Set these variables when the website is deployed:

```dotenv
NEXT_PUBLIC_SITE_URL=https://keyframeapp.com
NEXT_PUBLIC_MAC_DOWNLOAD_URL=https://YOUR-SIGNED-MAC-ARTIFACT
NEXT_PUBLIC_IOS_TESTFLIGHT_URL=https://testflight.apple.com/join/YOUR-CODE
NEXT_PUBLIC_IOS_APP_STORE_URL=https://apps.apple.com/app/id6797355107
```

The Mac variable should remain unset until the linked `.dmg` or `.zip` is signed, notarized, published, and tested on a clean Mac. Set the TestFlight variable only after the public invitation link is enabled. Set the App Store variable only after the product page is public; it takes precedence over TestFlight. The website displays honest release-prep or early-access states when links are absent.

## Node deployment commands

Use Node 24 and run the package from the repository root:

```bash
cd website && npm ci && npm run build
cd website && npm run start
```

The production Laravel Cloud environment is configured with Node 24 and builds the `website/` package successfully. Push-to-deploy is enabled for `main`.

## Remaining release gates

1. Configure the Laravel Cloud DNS records for `keyframeapp.com` and `www.keyframeapp.com` at Namecheap, then verify HTTPS.
2. Add working contact information to `/support`.
3. Add an easily accessible link to the deployed `/privacy` page inside the iOS app.
4. Complete age rating, content-rights, availability, EU DSA status, privacy, and reviewer-contact fields in App Store Connect.
5. Capture current iPhone 6.9-inch and iPad 13-inch screenshots from real builds.
6. Archive with a unique build number, upload to App Store Connect, create internal then external TestFlight groups, and submit the first external build for beta review.
7. Sign and notarize the Mac release, publish it, test the public URL, and set `NEXT_PUBLIC_MAC_DOWNLOAD_URL`.
8. When the public beta link exists, set `NEXT_PUBLIC_IOS_TESTFLIGHT_URL`. After the iOS product page is public at `https://apps.apple.com/app/id6797355107`, set `NEXT_PUBLIC_IOS_APP_STORE_URL` and redeploy the site.

Do not replace the release-prep states with “available” until the public links resolve to installable production builds.
