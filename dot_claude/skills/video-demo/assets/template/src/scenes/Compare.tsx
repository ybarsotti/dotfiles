import { Easing, Img, interpolate, spring, staticFile, useCurrentFrame } from "remotion";
import { theme } from "../theme";
import { FPS, Segment, segmentFrames, triggerFrame } from "../timing";
import { VIEW_H, VIEW_LEFT, VIEW_TOP, VIEW_W } from "./ClipScene";

const source = (name: string | undefined) => (/\.(png|jpe?g|svg|webp)$/i.test(name ?? "") ? `shots/${name}` : `clips/${name}-last.png`);

export const Compare = ({ segment }: { segment: Segment }) => {
  const frame = useCurrentFrame();
  const frames = segmentFrames(segment);
  const wipeAt = triggerFrame(segment, segment.wipe?.at ?? 0.4);
  const wipe = interpolate(frame, [wipeAt, wipeAt + 42], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.inOut(Easing.cubic) });
  const divider = VIEW_W * (1 - wipe);
  const enter = spring({ frame, fps: FPS, config: { damping: 200 }, durationInFrames: 20 });
  const zoom = 1 + 0.06 * (frame / frames);
  const shake = frame >= wipeAt && frame < wipeAt + 10 ? Math.sin(frame * 9) * (10 - (frame - wipeAt)) * 0.6 : 0;
  const label = (text: string, color: string, left: number, visible: number) => (
    <div
      style={{
        position: "absolute",
        left,
        top: 36,
        padding: "10px 22px",
        borderRadius: 999,
        background: "rgba(9,9,15,0.78)",
        border: `1.5px solid ${color}`,
        color,
        fontFamily: theme.sans,
        fontSize: 24,
        fontWeight: 800,
        letterSpacing: 4,
        opacity: visible,
      }}
    >
      {text}
    </div>
  );
  return (
    <div
      style={{
        position: "absolute",
        left: VIEW_LEFT,
        top: VIEW_TOP,
        width: VIEW_W,
        height: VIEW_H,
        borderRadius: 18,
        overflow: "hidden",
        boxShadow: "0 40px 120px rgba(0,0,0,0.6), 0 0 0 1px rgba(140,140,200,0.18)",
        opacity: enter,
        transform: `translateX(${shake}px)`,
        background: "#fff",
      }}
    >
      <div style={{ position: "absolute", inset: 0, transform: `scale(${zoom})`, transformOrigin: "50% 40%" }}>
        <Img src={staticFile(source(segment.before))} style={{ position: "absolute", width: VIEW_W, height: VIEW_H, filter: "saturate(0.6) brightness(0.9)" }} />
        <div style={{ position: "absolute", inset: 0, clipPath: `inset(0 0 0 ${divider}px)` }}>
          <Img src={staticFile(source(segment.after))} style={{ position: "absolute", width: VIEW_W, height: VIEW_H }} />
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          left: divider - 3,
          top: 0,
          width: 6,
          height: VIEW_H,
          background: theme.accentBright,
          boxShadow: `0 0 40px ${theme.accentBright}`,
          opacity: wipe > 0 && wipe < 1 ? 1 : 0,
        }}
      />
      {label("BEFORE", theme.amber, 36, 1 - wipe)}
      {label("AFTER", theme.accentBright, VIEW_W - 170, wipe)}
    </div>
  );
};
