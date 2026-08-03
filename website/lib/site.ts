const fallbackSiteUrl = "http://localhost:3000";

export const site = {
  name: "Keyframe",
  description:
    "A complete live performance rig for Mac, iPhone, and iPad—sessions, plug-ins, MIDI, mixing, and remote control in one focused system.",
  url: process.env.NEXT_PUBLIC_SITE_URL ?? fallbackSiteUrl,
  macDownloadUrl: process.env.NEXT_PUBLIC_MAC_DOWNLOAD_URL,
  macReleasesUrl: "https://github.com/joshcirre/keyframe/releases",
  iosTestFlightUrl: process.env.NEXT_PUBLIC_IOS_TESTFLIGHT_URL,
  iosAppStoreUrl: process.env.NEXT_PUBLIC_IOS_APP_STORE_URL,
  repositoryUrl: "https://github.com/joshcirre/keyframe",
  issuesUrl: "https://github.com/joshcirre/keyframe/issues",
} as const;
