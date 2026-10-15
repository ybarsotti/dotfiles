import { interpolate, spring, useCurrentFrame } from "remotion";
import { LightLeak } from "../Grade";
import { theme } from "../theme";
import { FPS, Segment, triggerFrame } from "../timing";
import { Reveal } from "../ui";

const Letters = ({ text, start, step, style }: { text: string; start: number; step: number; style: React.CSSProperties }) => {
  const frame = useCurrentFrame();
  return (
    <span style={{ display: "inline-block", whiteSpace: "pre", ...style }}>
      {text.split("").map((letter, index) => {
        const progress = spring({ frame: frame - start - index * step, fps: FPS, config: { damping: 14, stiffness: 90 } });
        return (
          <span
            key={index}
            style={{
              display: "inline-block",
              opacity: Math.min(1, progress),
              transform: `translateY(${(1 - progress) * 70}px)`,
              filter: `blur(${Math.max(0, (1 - progress) * 14)}px)`,
            }}
          >
            {letter}
          </span>
        );
      })}
    </span>
  );
};

export const Title = ({ segment }: { segment: Segment }) => {
  const frame = useCurrentFrame();
  const sweep = interpolate(frame, [26, 70], [0, 520], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: (t) => 1 - Math.pow(1 - t, 3) });
  return (
    <>
      <LightLeak />
      <LightLeak hue="242, 181, 68" speed={0.6} />
      <div style={{ position: "absolute", left: 180, right: 180, top: 300, color: theme.text }}>
        {segment.eyebrow ? (
          <Reveal start={4} distance={18}>
            <span style={{ fontFamily: theme.sans, fontSize: 22, fontWeight: 700, letterSpacing: 5, color: theme.accentBright, textTransform: "uppercase" }}>{segment.eyebrow}</span>
          </Reveal>
        ) : null}
        <div style={{ marginTop: 18, lineHeight: 1 }}>
          <Letters text={segment.title ?? ""} start={10} step={3} style={{ fontFamily: theme.serif, fontSize: 250, fontWeight: 500, letterSpacing: -8 }} />
          {segment.accent ? (
            <Letters text={` ${segment.accent}`} start={24} step={3} style={{ fontFamily: theme.serifItalic, fontSize: 250, fontWeight: 400, letterSpacing: -6, color: theme.accentBright }} />
          ) : null}
        </div>
        <div style={{ height: 4, width: sweep, borderRadius: 2, background: theme.accentBright, marginTop: 24, opacity: 0.9 }} />
        {segment.subtitle ? (
          <Reveal start={triggerFrame(segment, segment.subtitle.at)} distance={20} style={{ marginTop: 34 }}>
            <div style={{ fontFamily: theme.sans, fontSize: 36, fontWeight: 500, color: theme.muted, letterSpacing: 1 }}>{segment.subtitle.text}</div>
          </Reveal>
        ) : null}
      </div>
    </>
  );
};
