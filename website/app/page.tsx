import Image from "next/image";
import Link from "next/link";
import { site } from "@/lib/site";

const appIcon = "/keyframe-app-icon.png";

function ProductPreview() {
  return (
    <figure className="product-preview" aria-label="Keyframe running on Mac and iPhone">
      <div className="mac-capture">
        <Image
          src="/keyframe-mac-app.png"
          alt="The real Keyframe Mac mixer with Piano, Pad, Lead, and Backing channels"
          width={1200}
          height={669}
          priority
          sizes="(max-width: 1100px) 92vw, 62vw"
        />
      </div>

      <div className="iphone-capture">
        <Image
          src="/keyframe-ios-app.png"
          alt="The real Keyframe iPhone app offering local performance and remote control modes"
          width={1206}
          height={2622}
          priority
          sizes="(max-width: 720px) 26vw, 12vw"
        />
      </div>
      <figcaption>CAPTURED FROM THE CURRENT MAC + IPHONE BUILDS</figcaption>
    </figure>
  );
}

export default function Home() {
  const macReleaseUrl = site.macDownloadUrl ?? site.macReleasesUrl;
  const iosReleaseUrl = site.iosAppStoreUrl ?? site.iosTestFlightUrl;

  return (
    <div className="home-page">
      <header className="home-header">
        <Link className="home-brand" href="/" aria-label="Homepage">
          <Image src={appIcon} alt="" width={512} height={512} priority sizes="44px" />
          <span><strong>KEYFRAME</strong><small>LIVE PERFORMANCE SYSTEM</small></span>
        </Link>
        <nav className="home-nav" aria-label="Primary navigation">
          <Link href="/support">Support</Link>
          <Link href="/privacy">Privacy</Link>
          <a href={site.repositoryUrl}>GitHub</a>
        </nav>
        <a className="header-action" href={macReleaseUrl}>{site.macDownloadUrl ? "Download" : "Mac release"}</a>
        <details className="mobile-menu">
          <summary>Menu</summary>
          <nav aria-label="Mobile navigation"><Link href="/support">Support</Link><Link href="/privacy">Privacy</Link><a href={site.repositoryUrl}>GitHub</a></nav>
        </details>
      </header>

      <main id="main-content" className="home-main">
        <section className="keyframe-frame">
          <div className="hero-copy">
            <Image className="hero-icon" src={appIcon} alt="Keyframe app icon" width={512} height={512} priority sizes="(max-width: 720px) 96px, 120px" />
            <p className="eyebrow">MAC · IPHONE · IPAD</p>
            <h1>Your whole live rig.<br />One frame.</h1>
            <p className="hero-description">
              Songs, scenes, plug-ins, MIDI, mixing, and a two-way remote—built as one focused performance instrument.
            </p>
            <div className="hero-actions">
              <a className="button button--primary" href={macReleaseUrl}>{site.macDownloadUrl ? "Download for Mac" : "View Mac release"}</a>
              {iosReleaseUrl ? (
                <a className="secondary-action" href={iosReleaseUrl}>{site.iosAppStoreUrl ? "iPhone + iPad on the App Store" : "Join the iPhone + iPad beta"} <span>↗</span></a>
              ) : (
                <span className="secondary-action secondary-action--pending">iPhone + iPad beta coming soon</span>
              )}
            </div>
            <p className="availability"><i /> Free during early access</p>
          </div>

          <ProductPreview />

          <dl className="system-strip">
            <div><dt>ENGINE</dt><dd>AU + VST3</dd></div>
            <div><dt>CONTROL</dt><dd>MIDI + TOUCH</dd></div>
            <div><dt>REMOTE</dt><dd>LOCAL + TWO-WAY</dd></div>
            <div><dt>WORKFLOW</dt><dd>SONGS + SCENES</dd></div>
          </dl>
        </section>
      </main>
    </div>
  );
}
