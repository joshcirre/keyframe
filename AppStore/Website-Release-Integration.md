# Website and App Release Integration

The `website/` package is the public marketing, download, privacy, and support surface for the Mac and universal iPhone/iPad apps. It can be deployed independently while the native apps remain in the same repository.

## What is ready

- Next.js Node application in `website/`
- Product page positioning Keyframe as a focused alternative to Apple MainStage
- Mac release link with an honest release-prep fallback
- iPhone/iPad App Store card with a release-prep fallback
- `/privacy` route for App Store Connect
- `/support` route for App Store Connect
- `robots.txt`, `sitemap.xml`, Open Graph image, and app icon
- iOS privacy manifest declaring no tracking or collected data
- Universal iOS target configured for iPhone and iPad (`TARGETED_DEVICE_FAMILY = "1,2"`)
- App Store Connect record created for `com.keyframe.mki` (Apple ID `6797355107`)
- Mac App ID registered as `com.keyframe.mac`
- Existing App Group `group.com.keyframe.mki` verified in the developer team
- App Store listing copy, subtitle, categories, copyright, and manual-release mode saved

## Production configuration

Set these variables when the website is deployed:

```dotenv
NEXT_PUBLIC_SITE_URL=https://YOUR-PRODUCTION-DOMAIN
NEXT_PUBLIC_MAC_DOWNLOAD_URL=https://YOUR-SIGNED-MAC-ARTIFACT
NEXT_PUBLIC_IOS_APP_STORE_URL=https://apps.apple.com/app/id6797355107
```

The Mac variable should remain unset until the linked `.dmg` or `.zip` is signed, notarized, published, and tested on a clean Mac. The iOS variable should remain unset until the App Store product page is available. The website displays release-prep states when either link is absent.

## Node deployment commands

Use Node 24 and run the package from the repository root:

```bash
cd website && npm ci && npm run build
cd website && npm run start
```

Next.js supports this as a standard Node deployment. Laravel Cloud's current public documentation only promises Node for frontend build commands and describes Laravel/PHP as the web runtime. Use these commands on Laravel Cloud only if the target account explicitly offers a Node web runtime. Otherwise, deploy the package to a general Node host or add a Laravel wrapper that serves a static export.

## Remaining release gates

1. Confirm the production host/runtime, choose the domain, and deploy the site.
2. Add working contact information to `/support`.
3. Add an easily accessible link to the deployed `/privacy` page inside the iOS app.
4. Complete age rating, content-rights, pricing/availability, privacy, and reviewer-contact fields in App Store Connect.
5. Capture current iPhone 6.9-inch and iPad 13-inch screenshots from real builds.
6. Archive with a unique build number, upload to App Store Connect, and complete TestFlight testing.
7. Sign and notarize the Mac release, publish it, test the public URL, and set `NEXT_PUBLIC_MAC_DOWNLOAD_URL`.
8. After the iOS product page is public at `https://apps.apple.com/app/id6797355107`, set `NEXT_PUBLIC_IOS_APP_STORE_URL` and redeploy the site.

Do not replace the release-prep states with “available” until the public links resolve to installable production builds.
