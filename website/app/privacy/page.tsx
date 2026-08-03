import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description: "How Keyframe handles data across the Mac, iPhone, iPad, and website.",
};

export default function PrivacyPage() {
  return (
    <main id="main-content" className="legal-page">
      <div className="legal-nav"><Link href="/">← KEYFRAME</Link><span>PRIVACY / REV. 2026.08</span></div>
      <header><span className="section-index">PRIVACY POLICY</span><h1>Your performance stays yours.</h1><p>Effective August 2, 2026</p></header>
      <div className="legal-layout">
        <aside><span>SUMMARY</span><strong>No account.</strong><strong>No ads.</strong><strong>No tracking.</strong><strong>Local-first.</strong></aside>
        <article>
          <section><h2>Information we collect</h2><p>Keyframe does not require an account and does not collect personal information, usage analytics, advertising identifiers, or contact data through the Mac, iPhone, or iPad apps.</p></section>
          <section><h2>Audio and performance data</h2><p>Audio, MIDI messages, sessions, presets, plug-in state, setlists, and recordings are processed and stored on your devices. Keyframe does not upload this content to our servers.</p></section>
          <section><h2>Local network access</h2><p>Keyframe uses Bonjour and local network connections so an iPhone or iPad can discover and control another Keyframe device. Performance state is exchanged directly between devices on your local network and is not routed through Keyframe servers.</p></section>
          <section><h2>Bluetooth and MIDI</h2><p>Bluetooth permission may be used to connect compatible wireless MIDI hardware. MIDI device names and messages are used only to provide the controls you configure.</p></section>
          <section><h2>Website</h2><p>This website does not use advertising cookies or behavioral analytics. Our hosting provider may process routine request information such as IP address, browser type, and server logs for security and reliable delivery.</p></section>
          <section><h2>Third-party plug-ins and links</h2><p>Audio Unit and VST plug-ins are provided by their respective developers and may have their own privacy practices. Links to Apple, GitHub, or download providers are governed by those services’ policies.</p></section>
          <section><h2>Children’s privacy</h2><p>Keyframe does not knowingly collect personal information from children.</p></section>
          <section><h2>Changes and contact</h2><p>We may update this policy as Keyframe evolves. The effective date above will change when revisions are published. Questions can be submitted through the <Link href="/support">Keyframe support page</Link>.</p></section>
        </article>
      </div>
    </main>
  );
}
