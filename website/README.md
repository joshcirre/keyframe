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
- `NEXT_PUBLIC_MAC_DOWNLOAD_URL`: the signed/notarized Mac download URL. Until it is set, the site links to the GitHub releases page and labels the Mac build as release prep.
- `NEXT_PUBLIC_IOS_APP_STORE_URL`: add after App Store approval; until then the iPhone/iPad card displays release-in-preparation state.

The deployed `/privacy` and `/support` routes can be used for the corresponding App Store Connect fields.

## Laravel Cloud / Node hosting

Use Node 24 (Node 20.9+ is supported by the package) and configure the repository commands to run from this directory:

```bash
cd website && npm ci && npm run build
cd website && npm run start
```

Set the three environment variables above in the production environment. Next.js reads the platform-provided `PORT` automatically when running `next start`.
