import { interpolate, spring, useCurrentFrame } from "remotion";
import { theme, TONES } from "../theme";
import { CardSpec, FPS, Segment, segmentFrames, triggerFrame } from "../timing";
import { Heading, Kicker, Line, SceneFrame, useReveal } from "../ui";

const Card = ({ segment, card, index, layout }: { segment: Segment; card: CardSpec; index: number; layout: string }) => {
  const reveal = useReveal(triggerFrame(segment, card.at), 30);
  const accent = TONES[card.tone ?? "accent"];
  return (
    <div
      style={{
        ...reveal,
        boxSizing: "border-box",
        flex: layout === "grid" ? "0 0 48.5%" : layout === "row" ? 1 : undefined,
        display: "flex",
        gap: 24,
        alignItems: "flex-start",
        padding: "24px 28px",
        borderRadius: 18,
        background: theme.panel,
        border: `1px solid ${theme.panelLine}`,
      }}
    >
      {layout === "grid" ? <div style={{ fontFamily: theme.serif, fontSize: 56, fontWeight: 500, color: accent, lineHeight: 1 }}>{index + 1}</div> : null}
      <div style={{ flex: 1 }}>
        <div style={{ fontFamily: theme.serif, fontSize: layout === "column" ? 36 : 33, fontWeight: 500, color: theme.text, lineHeight: 1.15 }}>{card.title}</div>
        {card.note ? <div style={{ fontFamily: theme.sans, fontSize: 24, color: theme.muted, marginTop: 8, lineHeight: 1.3 }}>{card.note}</div> : null}
      </div>
    </div>
  );
};

export const Cards = ({ segment, top }: { segment: Segment; top?: number }) => {
  const layout = segment.layout ?? "column";
  return (
    <SceneFrame top={top}>
      {segment.kicker ? <Kicker text={segment.kicker} /> : null}
      {segment.title ? <Heading text={segment.title} size={56} /> : null}
      <div style={{ marginTop: 36, display: "flex", gap: 20, flexDirection: layout === "column" ? "column" : "row", flexWrap: layout === "grid" ? "wrap" : "nowrap" }}>
        {(segment.cards ?? []).map((card, index) => (
          <Card key={card.title} segment={segment} card={card} index={index} layout={layout} />
        ))}
      </div>
      {segment.banner ? <Line segment={segment} line={segment.banner} kind="banner" /> : null}
      {segment.footnote ? <Line segment={segment} line={segment.footnote} kind="footnote" /> : null}
      {segment.signoff ? <Line segment={segment} line={segment.signoff} kind="signoff" /> : null}
    </SceneFrame>
  );
};

export const Closing = ({ segment }: { segment: Segment }) => {
  const frame = useCurrentFrame();
  const frames = segmentFrames(segment);
  const endAt = segment.endcard ? triggerFrame(segment, segment.endcard.at) : frames;
  const toEnd = spring({ frame: frame - endAt, fps: FPS, config: { damping: 22, stiffness: 50 } });
  const fadeOut = interpolate(frame, [frames - 24, frames - 2], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return (
    <>
      <div style={{ position: "absolute", inset: 0, opacity: 1 - toEnd }}>
        <Cards segment={{ ...segment, endcard: undefined }} top={160} />
      </div>
      {segment.endcard ? (
        <div
          style={{
            position: "absolute",
            inset: 0,
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            justifyContent: "center",
            opacity: toEnd * fadeOut,
            transform: `scale(${0.96 + 0.04 * toEnd})`,
          }}
        >
          <div style={{ fontFamily: theme.serif, fontSize: 150, fontWeight: 500, letterSpacing: -5, color: theme.text, lineHeight: 1 }}>
            {segment.endcard.title.split(" ")[0]} <span style={{ fontFamily: theme.serifItalic, fontWeight: 400, color: theme.accentBright }}>{segment.endcard.title.split(" ").slice(1).join(" ")}</span>
          </div>
          <div style={{ fontFamily: theme.sans, fontSize: 28, fontWeight: 600, letterSpacing: 5, color: theme.muted, marginTop: 30, textTransform: "uppercase" }}>{segment.endcard.subtitle}</div>
        </div>
      ) : null}
    </>
  );
};
