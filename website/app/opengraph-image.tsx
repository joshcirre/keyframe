import { ImageResponse } from "next/og";

export const alt = "Keyframe — Your whole live rig, in one frame";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function Image() {
  return new ImageResponse(
    <div style={{ width: "100%", height: "100%", display: "flex", flexDirection: "column", justifyContent: "space-between", background: "#11110f", color: "#f4efe5", padding: "62px 72px", fontFamily: "sans-serif", position: "relative" }}>
      <div style={{ position: "absolute", inset: 0, display: "flex", backgroundImage: "linear-gradient(rgba(244,239,229,.07) 1px, transparent 1px), linear-gradient(90deg, rgba(244,239,229,.07) 1px, transparent 1px)", backgroundSize: "48px 48px" }} />
      <div style={{ display: "flex", alignItems: "center", gap: 22 }}><div style={{ display: "flex", width: 88, height: 88, background: "#ff681f", color: "#11110f", fontWeight: 900, fontSize: 38, alignItems: "center", justifyContent: "center" }}>KF</div><div style={{ display: "flex", flexDirection: "column" }}><strong style={{ fontSize: 34, letterSpacing: 8 }}>KEYFRAME</strong><span style={{ color: "#aaa69d", letterSpacing: 3, fontSize: 15 }}>LIVE PERFORMANCE SYSTEM</span></div></div>
      <div style={{ display: "flex", flexDirection: "column" }}><span style={{ color: "#ff681f", letterSpacing: 4, fontWeight: 700, fontSize: 18 }}>MAC / IPHONE / IPAD</span><div style={{ display: "flex", flexDirection: "column", fontSize: 86, lineHeight: 1, letterSpacing: -4, fontWeight: 800, marginTop: 18 }}><span>Your whole rig.</span><span>One frame.</span></div></div>
      <div style={{ display: "flex", justifyContent: "space-between", fontSize: 18, color: "#aaa69d", letterSpacing: 2 }}><span>SCENES · PLUG-INS · MIDI · MIXER · REMOTE</span><span>KEYFRAME / 2026</span></div>
    </div>,
    size,
  );
}
