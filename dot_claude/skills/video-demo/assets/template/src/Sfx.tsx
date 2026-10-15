import { Audio, Sequence, staticFile } from "remotion";
import { clipPlayback, FPS, Segment, segmentFrames, segments, segmentStart, triggerFrame } from "./timing";

type Cue = { frame: number; file: string; volume: number };

const push = (cues: Cue[], frame: number, file: string, volume: number) => {
  if (frame >= 0) {
    cues.push({ frame: Math.round(frame), file, volume });
  }
};

const clipCues = (cues: Cue[], segment: Segment, start: number) => {
  if (!segment.clip) return;
  const { meta, clipStart, rate } = clipPlayback(segment);
  const frames = segmentFrames(segment);
  const toFrame = (clipTime: number) => ((clipTime - clipStart) / rate) * FPS;
  for (const event of meta.events) {
    if (event.type === "down") {
      const frame = toFrame(event.t);
      if (frame > 0 && frame < frames - 6) push(cues, start + frame, "sfx/click.wav", 0.5);
    }
    if (event.type === "type-start" && event.text) {
      const begin = toFrame(event.t);
      const step = (0.095 / rate) * FPS;
      for (let index = 0; index < event.text.length; index += 1) {
        const frame = begin + index * step;
        if (frame > 0 && frame < frames - 6) push(cues, start + frame, "sfx/tick.wav", 0.22);
      }
    }
  }
};

export const buildCues = (): Cue[] => {
  const cues: Cue[] = [];
  segments.forEach((segment, index) => {
    const start = segmentStart(index);
    if (index > 0 && segment.kind !== "compare") {
      push(cues, start + 2, "sfx/whoosh.wav", segment.kind === "clip" ? 0.35 : 0.5);
    }
    switch (segment.kind) {
      case "title":
        push(cues, start + 10, "sfx/chime.wav", 0.4);
        push(cues, start + 4, "sfx/swell.wav", 0.35);
        break;
      case "compare": {
        const wipe = start + triggerFrame(segment, segment.wipe?.at ?? 0.4);
        push(cues, wipe - Math.round(3.1 * FPS), "sfx/riser.wav", 0.6);
        push(cues, wipe, "sfx/thud.wav", 0.8);
        push(cues, wipe + 2, "sfx/whoosh.wav", 0.5);
        break;
      }
      case "clip":
        clipCues(cues, segment, start);
        break;
      case "cards":
      case "closing":
        (segment.cards ?? []).forEach((card) => push(cues, start + triggerFrame(segment, card.at), "sfx/click.wav", 0.22));
        if (segment.endcard) push(cues, start + triggerFrame(segment, segment.endcard.at), "sfx/chime.wav", 0.45);
        break;
      default:
        break;
    }
  });
  return cues;
};

export const Sfx = () => {
  const cues = buildCues();
  return (
    <>
      {cues.map((cue, index) => (
        <Sequence key={`${cue.file}-${cue.frame}-${index}`} from={cue.frame} durationInFrames={Math.round(3.5 * FPS)}>
          <Audio src={staticFile(cue.file)} volume={cue.volume} />
        </Sequence>
      ))}
    </>
  );
};
