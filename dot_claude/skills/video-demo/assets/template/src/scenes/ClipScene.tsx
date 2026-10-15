import { Easing, Img, interpolate, OffthreadVideo, spring, staticFile, useCurrentFrame } from "remotion";
import { theme, TONES } from "../theme";
import { CameraSpec, clipPlayback, ClipEvent, coordinateSpace, findTargetBox, FPS, Segment, segmentFrames, triggerFrame } from "../timing";

export const VIEW_W = 1600;
export const VIEW_H = 1000;
export const VIEW_LEFT = (1920 - VIEW_W) / 2;
export const VIEW_TOP = 26;
const MOVE = 34;
const UNIT = VIEW_W / coordinateSpace[0];

type Camera = { cx: number; cy: number; zoom: number };

const cameraAt = (frame: number, keys: { frame: number; camera: Camera }[]): Camera => {
  let state: Camera = { ...keys[0].camera };
  for (let index = 1; index < keys.length; index += 1) {
    const key = keys[index];
    const progress = interpolate(frame, [key.frame - 6, key.frame - 6 + MOVE], [0, 1], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
      easing: Easing.inOut(Easing.cubic),
    });
    state = {
      cx: state.cx + (key.camera.cx - state.cx) * progress,
      cy: state.cy + (key.camera.cy - state.cy) * progress,
      zoom: state.zoom + (key.camera.zoom - state.zoom) * progress,
    };
  }
  return state;
};

const cursorAt = (events: ClipEvent[], clipTime: number) => {
  const points = events.filter((event) => event.type === "cursor" && event.x !== undefined);
  if (points.length === 0 || clipTime < points[0].t) return null;
  let previous = points[0];
  for (const point of points) {
    if (point.t > clipTime) {
      const span = Math.max(0.001, point.t - previous.t);
      const mix = Math.min(1, (clipTime - previous.t) / span);
      return { x: (previous.x ?? 0) + ((point.x ?? 0) - (previous.x ?? 0)) * mix, y: (previous.y ?? 0) + ((point.y ?? 0) - (previous.y ?? 0)) * mix };
    }
    previous = point;
  }
  return { x: previous.x ?? 0, y: previous.y ?? 0 };
};

const Cursor = ({ x, y, pressed }: { x: number; y: number; pressed: number }) => (
  <svg
    width={34}
    height={40}
    viewBox="0 0 17 20"
    style={{ position: "absolute", left: x - 2, top: y - 1, filter: "drop-shadow(0 2px 4px rgba(0,0,0,0.45))", transform: `scale(${1 - 0.12 * pressed})`, transformOrigin: "2px 2px" }}
  >
    <path d="M1.5 1.2 L1.5 16.6 L5.4 12.8 L8.1 18.6 L10.9 17.3 L8.2 11.6 L13.6 11.3 Z" fill="#fff" stroke="#0b0b12" strokeWidth={1.1} strokeLinejoin="round" />
  </svg>
);

export const ClipScene = ({ segment }: { segment: Segment }) => {
  const frame = useCurrentFrame();
  const frames = segmentFrames(segment);
  const { meta, clipStart, rate } = clipPlayback(segment);
  const clipTime = clipStart + (frame / FPS) * rate;
  const cameras = segment.camera ?? [{ at: 0, cx: coordinateSpace[0] / 2, cy: coordinateSpace[1] / 2, zoom: 1 }];
  const keys = cameras.map((spec) => {
    const at = triggerFrame(segment, spec.at);
    if (spec.target) {
      const [x0, y0, x1, y1] = findTargetBox(meta, spec.target, clipStart + (at / FPS) * rate);
      const visible = coordinateSpace[0] / spec.zoom;
      const wide = x1 - x0 > visible * 0.9;
      const cx = spec.cx ?? (wide ? x0 + visible / 2 - 16 : (x0 + x1) / 2);
      return { frame: at, camera: { cx, cy: spec.cy ?? (y0 + y1) / 2, zoom: spec.zoom } };
    }
    return { frame: at, camera: { cx: spec.cx ?? coordinateSpace[0] / 2, cy: spec.cy ?? coordinateSpace[1] / 2, zoom: spec.zoom } };
  });
  keys[0].frame = 0;
  const camera = cameraAt(frame, keys);
  const drift = 1 + 0.045 * (frame / frames);
  const zoom = camera.zoom * drift;
  const x = Math.min(0, Math.max(VIEW_W - VIEW_W * zoom, VIEW_W / 2 - camera.cx * UNIT * zoom));
  const y = Math.min(0, Math.max(VIEW_H - VIEW_H * zoom, VIEW_H / 2 - camera.cy * UNIT * zoom));
  const enter = spring({ frame, fps: FPS, config: { damping: 200 }, durationInFrames: 22 });
  const tilt = (1 - enter) * 5;
  const cursor = cursorAt(meta.events, clipTime);
  const lastDown = meta.events.filter((event) => event.type === "down" && event.t <= clipTime).pop();
  const sinceDown = lastDown ? (clipTime - lastDown.t) / rate : 99;
  const pressed = sinceDown < 0.12 ? 1 : 0;
  const ripple = sinceDown < 0.55 ? sinceDown / 0.55 : null;
  const still = !segment.clip;
  const showVideo = !still && clipTime < meta.duration - 0.08;
  const grade = "saturate(1.02) contrast(1.03)";

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
        transform: `perspective(2400px) rotateX(${tilt}deg) scale(${0.97 + 0.03 * enter})`,
        transformOrigin: "50% 60%",
        background: "#fff",
        filter: grade,
      }}
    >
      <div
        style={{
          position: "absolute",
          width: VIEW_W,
          height: VIEW_H,
          transformOrigin: "0 0",
          transform: `translate(${x}px, ${y}px) scale(${zoom})`,
        }}
      >
        <Img src={staticFile(still ? `shots/${segment.image}` : `clips/${meta.name}-last.png`)} style={{ position: "absolute", width: VIEW_W, height: VIEW_H }} />
        {showVideo ? (
          <OffthreadVideo
            src={staticFile(`clips/${meta.name}.mp4`)}
            startFrom={Math.round(clipStart * FPS)}
            playbackRate={rate}
            muted
            style={{ position: "absolute", width: VIEW_W, height: VIEW_H }}
          />
        ) : null}
        {(segment.focus ?? []).map((focus, index) => {
          const start = triggerFrame(segment, focus.at);
          const end = start + Math.round((focus.hold ?? 4) * FPS);
          if (frame < start - 2 || frame > end) return null;
          const rect = focus.rect ?? findTargetBox(meta, focus.target ?? "", clipStart + (start / FPS) * rate);
          const appear = spring({ frame: frame - start, fps: FPS, config: { damping: 16, stiffness: 140 } });
          const fade = interpolate(frame, [end - 10, end], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
          const color = TONES[focus.tone ?? "accent"];
          const [x0, y0, x1, y1] = rect;
          const pad = 8;
          const left = x0 * UNIT - pad;
          const top = y0 * UNIT - pad;
          const width = (x1 - x0) * UNIT + pad * 2;
          const height = (y1 - y0) * UNIT + pad * 2;
          const grow = 1.5 - 0.5 * Math.min(1, appear);
          return (
            <div key={index}>
              <div
                style={{
                  position: "absolute",
                  left: left + (width - width * grow) / 2,
                  top: top + (height - height * grow) / 2,
                  width: width * grow,
                  height: height * grow,
                  borderRadius: 10 / zoom + 4,
                  boxShadow: `0 0 0 ${6000 / zoom}px rgba(6, 6, 12, ${0.52 * Math.min(1, appear) * fade})`,
                  border: `${2.2 / zoom}px solid ${color}`,
                  opacity: fade,
                }}
              />
              {focus.label ? (
                <div
                  style={{
                    position: "absolute",
                    left,
                    top: top + height + 10 / zoom,
                    padding: `${5 / zoom}px ${12 / zoom}px`,
                    borderRadius: 8 / zoom,
                    background: color,
                    color: "#0B0B1A",
                    fontFamily: theme.sans,
                    fontSize: 20 / zoom,
                    fontWeight: 700,
                    whiteSpace: "nowrap",
                    opacity: Math.min(1, appear) * fade,
                  }}
                >
                  {focus.label}
                </div>
              ) : null}
            </div>
          );
        })}
      </div>
      {cursor ? (
        <>
          {ripple !== null ? (
            <div
              style={{
                position: "absolute",
                left: x + (cursor.x / 2) * UNIT * zoom - 26 - 26 * ripple,
                top: y + (cursor.y / 2) * UNIT * zoom - 26 - 26 * ripple,
                width: 52 + 52 * ripple,
                height: 52 + 52 * ripple,
                borderRadius: 999,
                border: `3px solid ${theme.accentBright}`,
                opacity: 0.9 * (1 - ripple),
              }}
            />
          ) : null}
          <Cursor x={x + (cursor.x / 2) * UNIT * zoom} y={y + (cursor.y / 2) * UNIT * zoom} pressed={pressed} />
        </>
      ) : null}
    </div>
  );
};
