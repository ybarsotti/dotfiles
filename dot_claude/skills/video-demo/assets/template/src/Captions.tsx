import { useCurrentFrame } from "remotion";
import { theme } from "./theme";
import { FPS, LEAD_IN, Segment, Word } from "./timing";

const MAX_CHARS = 52;

const chunkWords = (words: Word[]): Word[][] => {
  const chunks: Word[][] = [];
  let current: Word[] = [];
  let length = 0;
  for (const word of words) {
    const next = length + word.text.length + 1;
    if (current.length > 0 && next > MAX_CHARS) {
      chunks.push(current);
      current = [];
      length = 0;
    }
    current.push(word);
    length += word.text.length + 1;
    if (/[.?!:]$/.test(word.text) && length > 22) {
      chunks.push(current);
      current = [];
      length = 0;
    }
  }
  if (current.length > 0) {
    chunks.push(current);
  }
  return chunks;
};

export const Captions = ({ segment, top = 962 }: { segment: Segment; top?: number }) => {
  const frame = useCurrentFrame();
  const seconds = frame / FPS - LEAD_IN;
  const chunks = chunkWords(segment.words);
  const active =
    chunks.find((chunk, index) => {
      const next = chunks[index + 1];
      return seconds < (next ? next[0].start : Infinity);
    }) ?? chunks[chunks.length - 1];
  const started = seconds >= active[0].start - 0.35;

  return (
    <div
      style={{
        position: "absolute",
        left: 0,
        right: 0,
        top,
        height: 80,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        fontFamily: theme.sans,
        opacity: started ? 1 : 0,
      }}
    >
      <div
        style={{
          fontSize: 38,
          fontWeight: 600,
          letterSpacing: -0.4,
          whiteSpace: "nowrap",
          textShadow: "0 2px 18px rgba(0,0,0,0.85), 0 0 2px rgba(0,0,0,0.9)",
        }}
      >
        {active.map((word, index) => {
          const spoken = seconds >= word.start;
          const current = spoken && seconds < word.end + 0.08;
          return (
            <span
              key={`${word.start}-${index}`}
              style={{
                color: current ? theme.accentBright : spoken ? theme.text : "rgba(245,245,250,0.5)",
                marginRight: 11,
                transition: "color 80ms",
              }}
            >
              {word.text}
            </span>
          );
        })}
      </div>
    </div>
  );
};
