import { ReactNode } from "react";
import { interpolate, spring, useCurrentFrame } from "remotion";
import { theme, TONES } from "./theme";
import { FPS, LineSpec, Segment, Tone, triggerFrame } from "./timing";

export const useReveal = (start: number, distance = 36) => {
  const frame = useCurrentFrame();
  const progress = spring({ frame: frame - start, fps: FPS, config: { damping: 18, stiffness: 110 } });
  const blur = interpolate(progress, [0, 1], [10, 0]);
  return {
    opacity: Math.min(1, Math.max(0, progress)),
    transform: `translateY(${(1 - progress) * distance}px)`,
    filter: `blur(${Math.max(0, blur)}px)`,
  };
};

export const Reveal = ({ start, children, style, distance }: { start: number; children: ReactNode; style?: React.CSSProperties; distance?: number }) => (
  <div style={{ ...useReveal(start, distance), ...style }}>{children}</div>
);

export const Kicker = ({ text, start = 2 }: { text: string; start?: number }) => (
  <Reveal start={start} distance={18}>
    <div style={{ fontFamily: theme.sans, fontSize: 24, fontWeight: 700, letterSpacing: 4, color: theme.accentBright, textTransform: "uppercase" }}>{text}</div>
  </Reveal>
);

export const Heading = ({ text, start = 6, size = 64 }: { text: string; start?: number; size?: number }) => (
  <Reveal start={start} distance={28}>
    <div style={{ fontFamily: theme.serif, fontSize: size, fontWeight: 500, letterSpacing: -1.2, lineHeight: 1.08, color: theme.text, marginTop: 10 }}>{text}</div>
  </Reveal>
);

export const Chip = ({ text, tone = "accent", size = 22 }: { text: string; tone?: Tone; size?: number }) => (
  <span
    style={{
      display: "inline-block",
      fontFamily: theme.sans,
      fontSize: size,
      fontWeight: 700,
      padding: "6px 14px",
      borderRadius: 999,
      color: TONES[tone],
      border: `1.5px solid ${TONES[tone]}`,
      whiteSpace: "nowrap",
    }}
  >
    {text}
  </span>
);

export const Line = ({ segment, line, kind }: { segment: Segment; line: LineSpec; kind: "banner" | "footnote" | "signoff" }) => {
  const reveal = useReveal(triggerFrame(segment, line.at), 22);
  const accent = TONES[line.tone ?? "accent"];
  if (kind === "banner") {
    return (
      <div
        style={{
          ...reveal,
          display: "inline-block",
          marginTop: 30,
          padding: "20px 30px",
          borderRadius: 14,
          fontFamily: theme.sans,
          fontSize: 32,
          fontWeight: 700,
          border: `2px solid ${accent}`,
          color: accent,
          background: "rgba(0,0,0,0.25)",
        }}
      >
        {line.text}
      </div>
    );
  }
  if (kind === "signoff") {
    return <div style={{ ...reveal, marginTop: 26, fontFamily: theme.serifItalic, fontSize: 48, fontWeight: 500, color: accent }}>{line.text}</div>;
  }
  return <div style={{ ...reveal, marginTop: 22, fontFamily: theme.sans, fontSize: 27, color: theme.muted }}>{line.text}</div>;
};

export const SceneFrame = ({ children, top = 72 }: { children: ReactNode; top?: number }) => (
  <div style={{ position: "absolute", left: 140, right: 140, top, bottom: 140, color: theme.text }}>{children}</div>
);

export const ChapterChip = ({ chapter }: { chapter: string }) => {
  const [section, name] = chapter.split(" · ");
  const reveal = useReveal(8, 14);
  return (
    <div style={{ ...reveal, position: "absolute", left: 184, top: 48, padding: "10px 20px", borderRadius: 999, background: "rgba(9,9,15,0.82)", border: `1px solid ${theme.panelLine}`, fontFamily: theme.sans, display: "flex", alignItems: "center", gap: 14 }}>
      <div style={{ width: 8, height: 8, borderRadius: 4, background: section === "Before" ? theme.amber : theme.accentBright }} />
      <div style={{ fontSize: 20, fontWeight: 700, letterSpacing: 3, textTransform: "uppercase", color: section === "Before" ? theme.amber : theme.accentBright }}>{section}</div>
      {name ? <div style={{ fontSize: 20, fontWeight: 500, color: theme.muted }}>{name}</div> : null}
    </div>
  );
};
