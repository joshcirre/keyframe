import Link from "next/link";
import type { CSSProperties } from "react";
import { site } from "@/lib/site";

const features = [
  {
    number: "01",
    title: "Songs that think in sections",
    copy: "Build a set around intros, verses, choruses, and transitions. Recall the right sound, mix, key, tempo, and MIDI messages in one move.",
    tag: "SCENES + SETLISTS",
  },
  {
    number: "02",
    title: "Your plug-ins. Your sound.",
    copy: "Host instruments and effects, shape keyboard zones, filter scales, and turn simple notes into playable chords without rebuilding your rig.",
    tag: "AU + VST3",
  },
  {
    number: "03",
    title: "A mixer made for muscle memory",
    copy: "Keep layers, mutes, levels, routing, and meters visible. The interface stays high-contrast and direct when the room goes dark.",
    tag: "STAGE MIXER",
  },
  {
    number: "04",
    title: "The remote already in your pocket",
    copy: "Use iPhone or iPad to switch scenes and control layer volume, pan, mute, and master level—with authoritative two-way sync.",
    tag: "LOCAL NETWORK",
  },
] as const;

const performers = [
  "Keyboardists carrying too many boxes",
  "Music directors running complex setlists",
  "Live electronic and hybrid performers",
  "Small teams that need a repeatable rig",
] as const;

function ArrowIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 20 20" width="18" height="18">
      <path d="M4 10h11M11 5l5 5-5 5" fill="none" stroke="currentColor" strokeWidth="1.8" />
    </svg>
  );
}

function AppleIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24" width="18" height="18">
      <path
        fill="currentColor"
        d="M16.7 12.8c0-2.4 2-3.6 2.1-3.7a4.5 4.5 0 0 0-3.5-1.9c-1.5-.2-2.9.9-3.7.9-.8 0-2-1-3.3-1-1.7 0-3.3 1-4.2 2.5-1.8 3.1-.5 7.8 1.3 10.3.9 1.2 1.9 2.6 3.3 2.5 1.3-.1 1.8-.8 3.4-.8s2 .8 3.4.8c1.4 0 2.3-1.2 3.1-2.5a11 11 0 0 0 1.4-2.9 4.2 4.2 0 0 1-3.3-4.2ZM14.3 5.6A4.2 4.2 0 0 0 15.2 2a4.3 4.3 0 0 0-2.9 1.7 4 4 0 0 0-1 3.5 3.6 3.6 0 0 0 3-1.6Z"
      />
    </svg>
  );
}

function RigPreview() {
  const channelLevels = [68, 84, 47, 73];

  return (
    <div className="rig-preview" aria-label="A stylized preview of the Keyframe Mac and iPhone interfaces">
      <div className="preview-glow" />
      <div className="mac-window">
        <div className="window-bar">
          <div className="window-dots" aria-hidden="true"><i /><i /><i /></div>
          <span>KEYFRAME / SUNDAY PM</span>
          <span className="run-state"><i /> RUN</span>
        </div>
        <div className="window-body">
          <aside className="setlist-rail">
            <span className="tiny-label">SETLIST 06</span>
            <strong>THE LONG<br />WAY HOME</strong>
            <ol>
              <li><span>01</span> Open Hands</li>
              <li className="is-current"><span>02</span> Joy</li>
              <li><span>03</span> Always</li>
              <li><span>04</span> Reprise</li>
            </ol>
            <div className="tempo-chip"><small>TEMPO</small><b>124</b><small>BPM</small></div>
          </aside>
          <section className="scene-area">
            <div className="scene-heading">
              <div><span className="tiny-label">NOW PLAYING</span><h3>JOY</h3></div>
              <span className="key-chip">D♭ MAJ</span>
            </div>
            <div className="scene-grid">
              {['INTRO', 'VERSE', 'CHORUS', 'BRIDGE'].map((scene, index) => (
                <div className={index === 2 ? "scene-pad is-live" : "scene-pad"} key={scene}>
                  <span>0{index + 1}</span><b>{scene}</b>{index === 2 && <i>LIVE</i>}
                </div>
              ))}
            </div>
            <div className="mixer-strip-row">
              {channelLevels.map((level, index) => (
                <div className="channel-strip" key={level}>
                  <span>CH {index + 1}</span>
                  <div className="meter"><i style={{ height: `${level}%` }} /></div>
                  <div className="fader"><i style={{ bottom: `${level}%` }} /></div>
                  <b>{level}</b>
                </div>
              ))}
              <div className="channel-strip master-strip"><span>MASTER</span><div className="meter"><i style={{ height: '78%' }} /></div><div className="fader"><i style={{ bottom: '78%' }} /></div><b>78</b></div>
            </div>
          </section>
        </div>
      </div>
      <div className="phone-shell">
        <div className="phone-speaker" />
        <div className="phone-screen">
          <div className="phone-status"><span><i /> LIVE</span><small>MAC STAGE</small></div>
          <strong>JOY</strong>
          <div className="phone-scenes">
            <span>INTRO</span><span>VERSE</span><span className="active">CHORUS</span><span>BRIDGE</span>
          </div>
          <div className="phone-layers">
            {[66, 82, 48].map((level, index) => <i key={level} style={{ "--level": `${level}%` } as CSSProperties}><b>0{index + 1}</b></i>)}
          </div>
          <small className="sync-label">TWO-WAY SYNC</small>
        </div>
      </div>
      <span className="preview-caption">SYSTEM VIEW / 001</span>
    </div>
  );
}

export default function Home() {
  const macReleaseUrl = site.macDownloadUrl ?? site.macReleasesUrl;

  return (
    <>
      <header className="site-header">
        <Link className="wordmark" href="/" aria-label="Keyframe home">
          <span className="brand-mark" aria-hidden="true">KF</span>
          <span>KEYFRAME<small>LIVE PERFORMANCE SYSTEM</small></span>
        </Link>
        <nav aria-label="Primary navigation">
          <a href="#system">System</a>
          <a href="#performers">Who it’s for</a>
          <a href="#get-keyframe">Download</a>
        </nav>
        <a className="header-download" href={macReleaseUrl}>{site.macDownloadUrl ? "GET THE MAC APP" : "MAC RELEASES"} <ArrowIcon /></a>
      </header>

      <main id="main-content">
        <section className="hero">
          <div className="hero-grid" aria-hidden="true" />
          <div className="hero-copy">
            <div className="eyebrow"><span>MAC</span><span>IPHONE</span><span>IPAD</span><i /> ONE RIG</div>
            <h1>Your whole rig.<br /><em>One frame.</em></h1>
            <p className="hero-lede">
              Keyframe puts your songs, sections, plug-ins, keyboard zones, MIDI,
              and mix into one performance system—then puts the controls you need on the device in your hand.
            </p>
            <div className="hero-actions">
              <a className="button button--primary" href={macReleaseUrl}><AppleIcon /> {site.macDownloadUrl ? "DOWNLOAD FOR MAC" : "VIEW MAC RELEASES"} <ArrowIcon /></a>
              <a className="text-link" href="#system">EXPLORE THE SYSTEM <span>↓</span></a>
            </div>
            <dl className="hero-specs">
              <div><dt>HOST</dt><dd>AU + VST3</dd></div>
              <div><dt>CONTROL</dt><dd>MIDI + TOUCH</dd></div>
              <div><dt>SYNC</dt><dd>LOCAL + TWO-WAY</dd></div>
            </dl>
          </div>
          <RigPreview />
          <div className="signal-line" aria-hidden="true"><i /><i /><i /><i /><i /><i /><i /><i /><i /><i /><i /><i /></div>
        </section>

        <section className="manifesto" aria-label="Keyframe summary">
          <p>LESS GEAR TO BABYSIT.</p><p>MORE ROOM TO PERFORM.</p><span>KEYFRAME / 2026</span>
        </section>

        <section className="system-section" id="system">
          <div className="section-intro">
            <span className="section-index">01 / THE SYSTEM</span>
            <h2>Everything between the first note and the last.</h2>
            <p>Designed around the way a live set actually moves—not around a studio timeline.</p>
          </div>
          <div className="feature-grid">
            {features.map((feature) => (
              <article className="feature-card" key={feature.number}>
                <div className="feature-top"><span>{feature.number}</span><i /></div>
                <p className="feature-tag">{feature.tag}</p>
                <h3>{feature.title}</h3>
                <p>{feature.copy}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="comparison-section">
          <div className="comparison-statement">
            <span className="section-index">02 / A FOCUSED ALTERNATIVE</span>
            <h2>The live-rig idea,<br />without the cockpit.</h2>
          </div>
          <div className="comparison-copy">
            <p>
              If Apple MainStage is the category reference, Keyframe is the focused two-screen take:
              your Mac runs the performance engine while iPhone or iPad keeps scene and mixer control close.
            </p>
            <div className="flow-diagram" aria-label="Keyframe signal flow">
              <div><span>01</span><b>PLAY</b><small>Keys · MIDI · Audio</small></div>
              <i>→</i>
              <div><span>02</span><b>PROCESS</b><small>Plug-ins · Zones · Chords</small></div>
              <i>→</i>
              <div><span>03</span><b>PERFORM</b><small>Scenes · Mix · Remote</small></div>
            </div>
          </div>
        </section>

        <section className="performers-section" id="performers">
          <div className="performer-orbit" aria-hidden="true"><div className="orbit-core">KF</div><i /><i /><i /></div>
          <div className="performer-copy">
            <span className="section-index">03 / WHO IT’S FOR</span>
            <h2>For people who need the rig to disappear.</h2>
            <ul>{performers.map((performer, index) => <li key={performer}><span>0{index + 1}</span>{performer}</li>)}</ul>
          </div>
        </section>

        <section className="download-section" id="get-keyframe">
          <div className="download-heading">
            <span className="section-index">04 / GET KEYFRAME</span>
            <h2>Build the set.<br />Then play it.</h2>
          </div>
          <div className="release-cards">
            <article className={site.macDownloadUrl ? "release-card release-card--available" : "release-card release-card--soon"}>
              <div><AppleIcon /><span>MACOS</span><i>{site.macDownloadUrl ? "AVAILABLE" : "RELEASE PREP"}</i></div>
              <h3>Keyframe for Mac</h3>
              <p>The full performance workstation: sessions, setlists, sections, plug-ins, zones, and mixer.</p>
              <a className="button button--dark" href={macReleaseUrl}>{site.macDownloadUrl ? "DOWNLOAD MAC APP" : "VIEW MAC RELEASES"} <ArrowIcon /></a>
              <small>macOS 13 or later · Apple silicon and Intel</small>
            </article>
            <article className="release-card release-card--soon">
              <div><span className="device-glyph">▯</span><span>IPHONE + IPAD</span><i>UP NEXT</i></div>
              <h3>Keyframe for iOS</h3>
              <p>A standalone AUv3 performance engine and a two-way remote for your Mac or iPad rig.</p>
              {site.iosAppStoreUrl ? (
                <a className="button button--outline" href={site.iosAppStoreUrl}>VIEW ON THE APP STORE <ArrowIcon /></a>
              ) : (
                <span className="button button--outline button--pending">APP STORE RELEASE IN PREPARATION</span>
              )}
              <small>One universal app · iPhone and iPad</small>
            </article>
          </div>
          <div className="release-links">
            <span>RELEASE RESOURCES</span>
            <Link href="/privacy">PRIVACY POLICY <ArrowIcon /></Link>
            <Link href="/support">SUPPORT <ArrowIcon /></Link>
          </div>
        </section>
      </main>
    </>
  );
}
