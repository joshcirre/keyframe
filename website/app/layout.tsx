import type { Metadata, Viewport } from "next";
import Image from "next/image";
import Link from "next/link";
import type { ReactNode } from "react";
import { site } from "@/lib/site";
import "./globals.css";

const appIcon = "/keyframe-app-icon.png";

export const metadata: Metadata = {
  metadataBase: new URL(site.url),
  title: {
    default: "Keyframe — Your whole live rig, in one frame",
    template: "%s — Keyframe",
  },
  description: site.description,
  applicationName: site.name,
  keywords: [
    "live performance software",
    "MainStage alternative",
    "AU plugin host",
    "MIDI performance",
    "keyboard rig",
    "setlist software",
    "iPhone remote",
    "iPad music app",
  ],
  authors: [{ name: "Keyframe" }],
  creator: "Keyframe",
  icons: {
    icon: appIcon,
    apple: appIcon,
  },
  openGraph: {
    type: "website",
    title: "Keyframe — Your whole live rig, in one frame",
    description: site.description,
    siteName: site.name,
  },
  twitter: {
    card: "summary_large_image",
    title: "Keyframe — Your whole live rig, in one frame",
    description: site.description,
  },
};

export const viewport: Viewport = {
  colorScheme: "light",
  themeColor: "#faf5eb",
};

export default function RootLayout({ children }: Readonly<{ children: ReactNode }>) {
  return (
    <html lang="en">
      <body>
        <a className="skip-link" href="#main-content">
          Skip to content
        </a>
        {children}
        <footer className="site-footer">
          <div className="footer-brand">
            <Image src={appIcon} alt="" width={512} height={512} sizes="28px" />
            <div>
              <strong>KEYFRAME</strong>
              <span>Built for the moment the lights come up.</span>
            </div>
          </div>
          <nav aria-label="Footer navigation">
            <Link href="/privacy">Privacy</Link>
            <Link href="/support">Support</Link>
            <a href={site.repositoryUrl}>GitHub</a>
          </nav>
          <p className="legal-note">
            © {new Date().getFullYear()} Keyframe. MainStage is a trademark of Apple Inc.
            Keyframe is not affiliated with Apple.
          </p>
        </footer>
      </body>
    </html>
  );
}
