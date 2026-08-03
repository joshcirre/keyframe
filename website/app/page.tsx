import Image from "next/image";
import Link from "next/link";
import type { CSSProperties } from "react";
import appIcon from "../../iOS/Keyframe/Assets.xcassets/AppIcon.appiconset/AppIcon.png";
import { site } from "@/lib/site";

const scenes = ["INTRO", "VERSE", "CHORUS", "BRIDGE"] as const;
const channels = [
  { name: "PIANO", level: 72, color: "orange" },
  { name: "PAD", level: 58, color: "blue" },
  { name: "LEAD", level: 81, color: "green" },
  { name: "LOOP", level: 46, color: "yellow" },
] as const;

function ProductPreview() {
  return (
    <div className="product-preview" aria-label="Keyframe running on Mac with its connected iPhone remote">
      <div className="mac-app">
        <div className="app-toolbar">
          <div className="window-controls" aria-hidden="true"><i /><i /><i /></div>
          <strong>KEYFRAME</strong>
          <div className="mode-switch"><span className="is-selected">PERFORM</span><span>EDIT</span></div>
          <span className="engine-state"><i /> AUDIO</span>
        </div>
        <div className="app-workspace">
          <aside className="song-browser">
            <span className="app-label">SETLIST / 06</span>
            <h2>SUNDAY<br />PM</h2>
            <ol role="list">
              <li><span>01</span> Open Hands</li>
              <li className="is-current"><span>02</span> Joy</li>
              <li><span>03</span> Always</li>
              <li><span>04</span> Reprise</li>
            </ol>
            <dl>
              <div><dt>TEMPO</dt><dd>124</dd></div>
              <div><dt>KEY</dt><dd>D♭</dd></div>
            </dl>
          </aside>
          <section className="performance-surface">
            <div className="now-playing">
              <div><span className="app-label">NOW PLAYING</span><h2>JOY</h2></div>
              <span className="sync-state"><i /> REMOTE CONNECTED</span>
            </div>
            <div className="scene-row">
              {scenes.map((scene, index) => (
                <div className={index === 2 ? "scene-button is-live" : "scene-button"} key={scene}>
                  <span>0{index + 1}</span><strong>{scene}</strong>{index === 2 && <small>LIVE</small>}
                </div>
              ))}
            </div>
            <div className="mixer-row">
              {channels.map((channel, index) => (
                <div className="mixer-channel" key={channel.name}>
                  <div className="channel-heading"><span>0{index + 1}</span><strong>{channel.name}</strong></div>
                  <div className="channel-control">
                    <div className="level-meter"><i style={{ "--meter": `${channel.level}%` } as CSSProperties} /></div>
                    <div className="fader-track"><i style={{ "--fader": `${channel.level}%` } as CSSProperties} /></div>
                  </div>
                  <div className="channel-footer"><span className={`channel-color channel-color--${channel.color}`} /><strong>{channel.level}</strong></div>
                </div>
              ))}
            </div>
          </section>
        </div>
      </div>

      <div className="iphone-app" aria-hidden="true">
        <div className="dynamic-island" />
        <div className="phone-header"><span><i /> LIVE</span><small>MAC STAGE</small></div>
        <strong>JOY</strong>
        <div className="phone-scenes">
          {scenes.map((scene, index) => <span className={index === 2 ? "is-live" : ""} key={scene}>{scene}</span>)}
        </div>
        <div className="phone-mix">
          {channels.slice(0, 3).map((channel, index) => <i key={channel.name} style={{ "--phone-level": `${channel.level}%` } as CSSProperties}><span>0{index + 1}</span></i>)}
        </div>
        <small className="phone-sync">TWO-WAY SYNC</small>
      </div>
    </div>
  );
}

export default function Home() {
  const macReleaseUrl = site.macDownloadUrl ?? site.macReleasesUrl;
  const iosReleaseUrl = site.iosAppStoreUrl ?? site.iosTestFlightUrl;

  return (
    <div className="home-page">
      <header className="home-header">
        <Link className="home-brand" href="/" aria-label="Homepage">
          <Image src={appIcon} alt="" priority sizes="44px" />
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
            <Image className="hero-icon" src={appIcon} alt="Keyframe app icon" priority sizes="(max-width: 720px) 96px, 120px" />
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
