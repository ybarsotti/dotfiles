import { AbsoluteFill, interpolate, staticFile, useCurrentFrame } from "remotion";

const BAR = 118;

export const Vignette = () => (
  <AbsoluteFill
    style={{
      pointerEvents: "none",
      background: "radial-gradient(ellipse 72% 68% at 50% 46%, rgba(0,0,0,0) 48%, rgba(0,0,0,0.42) 100%)",
    }}
  />
);

export const Grain = ({ opacity = 0.16 }: { opacity?: number }) => {
  const frame = useCurrentFrame();
  const tile = frame % 8;
  const offsetX = (frame * 37) % 512;
  const offsetY = (frame * 23) % 512;
  return (
    <AbsoluteFill
      style={{
        pointerEvents: "none",
        backgroundImage: `url(${staticFile(`grain/g${tile}.png`)})`,
        backgroundRepeat: "repeat",
        backgroundPosition: `${offsetX}px ${offsetY}px`,
        mixBlendMode: "overlay",
        opacity,
      }}
    />
  );
};

export const Letterbox = ({ frames, visible }: { frames: number; visible: boolean }) => {
  const frame = useCurrentFrame();
  const reveal = visible
    ? interpolate(frame, [0, 22], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" })
    : interpolate(frame, [0, 22], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const out = visible ? interpolate(frame, [frames - 20, frames], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" }) : 1;
  const height = BAR * reveal * out;
  return (
    <>
      <div style={{ position: "absolute", left: 0, top: 0, width: "100%", height, background: "#000" }} />
      <div style={{ position: "absolute", left: 0, bottom: 0, width: "100%", height, background: "#000" }} />
    </>
  );
};

export const Scrim = () => (
  <div
    style={{
      position: "absolute",
      left: 0,
      right: 0,
      bottom: 0,
      height: 260,
      pointerEvents: "none",
      background: "linear-gradient(180deg, rgba(8,8,14,0) 0%, rgba(8,8,14,0.62) 70%, rgba(8,8,14,0.8) 100%)",
    }}
  />
);

export const LightLeak = ({ hue = "129, 140, 248", speed = 1 }: { hue?: string; speed?: number }) => {
  const frame = useCurrentFrame();
  const x = 20 + 55 * (0.5 + 0.5 * Math.sin(frame / (140 / speed)));
  const y = 15 + 40 * (0.5 + 0.5 * Math.cos(frame / (190 / speed)));
  return (
    <AbsoluteFill
      style={{
        pointerEvents: "none",
        background: `radial-gradient(900px 620px at ${x}% ${y}%, rgba(${hue}, 0.22) 0%, rgba(${hue}, 0.06) 38%, rgba(0,0,0,0) 70%)`,
      }}
    />
  );
};
