# Keyframe Website

Marketing, download, privacy, and support site for Keyframe. This package lives beside the macOS and iOS apps in the repository and deploys as a standard Next.js Node server.

## Local development

```bash
cd website
npm install
cp .env.example .env.local
npm run dev
```

Open `http://localhost:3000`.

## Release links

The site is ready for the release URLs without a code change:

- `NEXT_PUBLIC_SITE_URL`: the production origin used by metadata, robots, and the sitemap.
- `NEXT_PUBLIC_MAC_DOWNLOAD_URL`: optional signed/notarized Mac download override. When unset, the site downloads the stable `Keyframe-Mac.zip` asset from the latest GitHub Release.
- `NEXT_PUBLIC_IOS_TESTFLIGHT_URL`: add after the public TestFlight invitation link is enabled; until then the iPhone/iPad card displays an early-access pending state.
- `NEXT_PUBLIC_IOS_APP_STORE_URL`: add after App Store approval. It takes precedence over the TestFlight URL.

The deployed `/privacy` and `/support` routes can be used for the corresponding App Store Connect fields.

## Node hosting

Use Node 24 (Node 20.9+ is supported by the package) and configure the repository commands to run from this directory:

```bash
cd website && npm ci && npm run build
cd website && npm run start
```

Set the relevant environment variables above in the production environment. Next.js reads the platform-provided `PORT` automatically when running `next start`.

### Laravel Cloud compatibility

The `keyframe` production environment is configured with a Node 24 web runtime and push-to-deploy from `main`. Laravel Cloud builds and serves this Next.js package successfully.
