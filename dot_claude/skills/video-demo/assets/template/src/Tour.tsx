import { linearTiming, TransitionPresentation, TransitionSeries } from "@remotion/transitions";
import { fade } from "@remotion/transitions/fade";
import { slide } from "@remotion/transitions/slide";
import { wipe } from "@remotion/transitions/wipe";
import { Fragment, ReactElement } from "react";
import { AbsoluteFill, Audio, Sequence, staticFile } from "remotion";
import { Captions } from "./Captions";
import { Grain, Letterbox, Scrim, Vignette } from "./Grade";
import { Cards, Closing } from "./scenes/Cards";
import { ClipScene } from "./scenes/ClipScene";
import { Compare } from "./scenes/Compare";
import { Title } from "./scenes/Title";
import { Sfx } from "./Sfx";
import { theme } from "./theme";
import { FPS, LEAD_IN, Segment, segmentFrames, segments, TRANSITION } from "./timing";
import { ChapterChip } from "./ui";

const SCENES: Record<Segment["kind"], (props: { segment: Segment }) => ReactElement | null> = {
  title: Title,
  clip: ClipScene,
  compare: Compare,
  cards: Cards,
  closing: Closing,
};

const LETTERBOXED: Segment["kind"][] = ["title", "closing"];
const FOOTAGE: Segment["kind"][] = ["clip", "compare"];

const Scene = ({ segment }: { segment: Segment }) => {
  const Component = SCENES[segment.kind];
  const frames = segmentFrames(segment);
  const letterboxed = LETTERBOXED.includes(segment.kind);
  return (
    <AbsoluteFill style={{ background: `radial-gradient(1400px 800px at 18% 0%, ${theme.accentDeep} 0%, ${theme.ink} 64%)` }}>
      <Component segment={segment} />
      {FOOTAGE.includes(segment.kind) ? <Scrim /> : null}
      {segment.kind === "clip" ? <ChapterChip chapter={segment.chapter} /> : null}
      <Vignette />
      <Letterbox frames={frames} visible={letterboxed} />
      <Captions segment={segment} top={letterboxed ? 870 : 962} />
      <Sequence from={Math.round(LEAD_IN * FPS)}>
        <Audio src={staticFile(segment.audio)} />
      </Sequence>
    </AbsoluteFill>
  );
};

const transitionFor = (previous: Segment, next: Segment): TransitionPresentation<Record<string, unknown>> => {
  if (next.kind === "compare") return fade() as TransitionPresentation<Record<string, unknown>>;
  if (previous.kind === "compare") return wipe({ direction: "from-right" }) as TransitionPresentation<Record<string, unknown>>;
  if (previous.kind === "clip" && next.kind === "clip") return slide({ direction: "from-right" }) as TransitionPresentation<Record<string, unknown>>;
  return fade() as TransitionPresentation<Record<string, unknown>>;
};

export const Tour = () => (
  <AbsoluteFill style={{ background: theme.ink }}>
    <TransitionSeries>
      {segments.map((segment, index) => (
        <Fragment key={segment.id}>
          {index > 0 ? (
            <TransitionSeries.Transition presentation={transitionFor(segments[index - 1], segment)} timing={linearTiming({ durationInFrames: TRANSITION })} />
          ) : null}
          <TransitionSeries.Sequence durationInFrames={segmentFrames(segment)}>
            <Scene segment={segment} />
          </TransitionSeries.Sequence>
        </Fragment>
      ))}
    </TransitionSeries>
    <Grain opacity={0.13} />
    <Sfx />
  </AbsoluteFill>
);
