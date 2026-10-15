import { loadFont as loadFraunces } from "@remotion/google-fonts/Fraunces";
import { loadFont as loadInterTight } from "@remotion/google-fonts/InterTight";

const fraunces = loadFraunces("normal", { weights: ["400", "500", "700"], subsets: ["latin"] });
const frauncesItalic = loadFraunces("italic", { weights: ["400", "500"], subsets: ["latin"] });
const interTight = loadInterTight("normal", { weights: ["400", "500", "600", "700", "800"], subsets: ["latin"] });

export const theme = {
  accent: "#4F46E5",
  accentBright: "#818CF8",
  accentDeep: "#14123A",
  ink: "#09090F",
  panel: "rgba(22, 22, 40, 0.72)",
  panelLine: "rgba(129, 140, 248, 0.28)",
  text: "#F5F5FA",
  muted: "#B3B5C8",
  dim: "#7A7C93",
  amber: "#F2B544",
  red: "#F0605D",
  serif: fraunces.fontFamily,
  serifItalic: frauncesItalic.fontFamily,
  sans: interTight.fontFamily,
};

export const TONES: Record<"accent" | "amber" | "red", string> = { accent: theme.accentBright, amber: theme.amber, red: theme.red };
