import clipMetaJson from "./clipMeta.json";
import manifestJson from "./manifest.json";

export type Word = { text: string; start: number; end: number };
export type Trigger = string | number;
export type Tone = "accent" | "amber" | "red";
export type CardSpec = { at: Trigger; title: string; note?: string; eyebrow?: string; chip?: string; tone?: Tone };
export type LineSpec = { at: Trigger; text: string; tone?: Tone };
export type CameraSpec = { at: Trigger; cx?: number; cy?: number; zoom: number; target?: string };
export type FocusSpec = { at: Trigger; target?: string; rect?: [number, number, number, number]; hold?: number; label?: string; tone?: Tone };
export type EndCard = { at: Trigger; title: string; subtitle: string };
export type Kind = "title" | "clip" | "compare" | "cards" | "closing";

export type Segment = {
  id: string;
  kind: Kind;
  chapter: string;
  text: string;
  audio: string;
  duration: number;
  words: Word[];
  eyebrow?: string;
  title?: string;
  accent?: string;
  subtitle?: LineSpec;
  kicker?: string;
  layout?: "row" | "column" | "grid";
  cards?: CardSpec[];
  banner?: LineSpec;
  footnote?: LineSpec;
  signoff?: LineSpec;
  endcard?: EndCard;
  clip?: string;
  image?: string;
  clipStart?: number;
  camera?: CameraSpec[];
  focus?: FocusSpec[];
  before?: string;
  after?: string;
  wipe?: { at: Trigger };
};

export type ClipEvent = {
  type: "cursor" | "down" | "up" | "type-start" | "type-end" | "target" | "end";
  t: number;
  x?: number;
  y?: number;
  x0?: number;
  y0?: number;
  x1?: number;
  y1?: number;
  label?: string;
  text?: string;
};
export type ClipMeta = { name: string; width: number; height: number; fps: number; duration: number; events: ClipEvent[] };

type Manifest = { coordinateSpace: [number, number]; segments: Segment[] };

const manifest = manifestJson as unknown as Manifest;

export const FPS = 30;
export const LEAD_IN = 0.5;
export const TAIL = 0.7;
export const TRANSITION = 14;
export const segments = manifest.segments;
export const coordinateSpace = manifest.coordinateSpace;
export const clipMeta = clipMetaJson as unknown as Record<string, ClipMeta>;

export const segmentFrames = (segment: Segment) => Math.ceil((LEAD_IN + segment.duration + TAIL) * FPS);

export const segmentStart = (index: number) =>
  segments.slice(0, index).reduce((sum, segment) => sum + segmentFrames(segment), 0) - index * TRANSITION;

export const totalFrames = segmentStart(segments.length - 1) + segmentFrames(segments[segments.length - 1]);

const normalize = (text: string) =>
  text
    .toLowerCase()
    .replace(/[.,:;?!]/g, "")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "");

export const triggerSeconds = (segment: Segment, trigger: Trigger): number => {
  if (typeof trigger === "number") {
    return LEAD_IN + trigger * segment.duration;
  }
  const [target, occurrence] = trigger.split("#");
  const wanted = Number(occurrence ?? 1);
  let seen = 0;
  for (const word of segment.words) {
    if (normalize(word.text) === normalize(target)) {
      seen += 1;
      if (seen === wanted) {
        return LEAD_IN + word.start;
      }
    }
  }
  throw new Error(`segment ${segment.id}: trigger word "${trigger}" is not in the narration`);
};

export const triggerFrame = (segment: Segment, trigger: Trigger) => Math.round(triggerSeconds(segment, trigger) * FPS);

const STILL: ClipMeta = { name: "", width: 2880, height: 1800, fps: FPS, duration: Number.POSITIVE_INFINITY, events: [] };

export const clipPlayback = (segment: Segment) => {
  if (!segment.clip) {
    if (!segment.image) {
      throw new Error(`segment ${segment.id}: a clip scene needs "clip" (recorded) or "image" (still)`);
    }
    return { meta: { ...STILL, name: segment.image }, clipStart: 0, rate: 1, remaining: Number.POSITIVE_INFINITY };
  }
  const meta = clipMeta[segment.clip];
  if (!meta) {
    throw new Error(`segment ${segment.id}: clip "${segment.clip}" has no metadata; run scripts/collect.cjs after recording`);
  }
  const clipStart = segment.clipStart ?? 0;
  const seconds = segmentFrames(segment) / FPS;
  const remaining = meta.duration - clipStart;
  const rate = Math.min(1.6, Math.max(0.9, remaining / seconds));
  return { meta, clipStart, rate, remaining };
};

export const findTargetBox = (meta: ClipMeta, target: string, nearClipTime: number) => {
  const plain = (text: string) => text.replace(/\\/g, "");
  const matches = meta.events.filter((event) => event.type === "target" && plain(event.label ?? "").includes(plain(target)));
  if (matches.length === 0) {
    throw new Error(`clip ${meta.name}: no recorded target contains "${target}" (a still scene needs "rect" instead of "target")`);
  }
  const before = matches.filter((event) => event.t <= nearClipTime + 0.6);
  const chosen = before.length > 0 ? before[before.length - 1] : matches[0];
  return [chosen.x0 ?? 0, chosen.y0 ?? 0, chosen.x1 ?? 0, chosen.y1 ?? 0].map((value) => value / 2) as [number, number, number, number];
};
