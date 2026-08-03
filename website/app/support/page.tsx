import type { Metadata } from "next";
import Link from "next/link";
import { site } from "@/lib/site";

export const metadata: Metadata = {
  title: "Support",
  description: "Help with Keyframe for Mac, iPhone, and iPad.",
};

const topics = [
  ["Remote device not appearing", "Open Local Mode on the host device, Remote Mode on the controller, allow Local Network access, and confirm both devices are on the same network."],
  ["A plug-in is missing", "Confirm the Audio Unit or VST3 is installed for the current user, then restart Keyframe so the plug-in catalog can refresh."],
  ["No MIDI input", "Check the channel’s MIDI source and channel assignment. Bluetooth MIDI devices must be paired before they appear as an input."],
  ["Audio changes after reconnecting hardware", "Open Audio Settings and reselect the intended input and output. Save the session again after confirming the route."],
] as const;

export default function SupportPage() {
  return (
    <main id="main-content" className="legal-page support-page">
      <div className="legal-nav"><Link href="/">← KEYFRAME</Link><span>SUPPORT / SYSTEM CHECK</span></div>
      <header><span className="section-index">SUPPORT</span><h1>Let’s get the rig back online.</h1><p>Fast checks for the things that matter five minutes before downbeat.</p></header>
      <div className="support-grid">
        {topics.map(([title, copy], index) => <article key={title}><span>0{index + 1}</span><h2>{title}</h2><p>{copy}</p></article>)}
      </div>
      <section className="support-contact">
        <div><span className="section-index">STILL STUCK?</span><h2>Send the details.</h2><p>Include your device model, OS version, Keyframe version, audio/MIDI hardware, and the steps that reproduce the problem.</p></div>
        <a className="button button--primary" href={site.issuesUrl}>OPEN A SUPPORT REQUEST →</a>
      </section>
    </main>
  );
}
