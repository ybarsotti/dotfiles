import { Composition } from "remotion";
import { Tour } from "./Tour";
import { FPS, totalFrames } from "./timing";

export const Root = () => (
  <Composition id="Tour" component={Tour} durationInFrames={totalFrames} fps={FPS} width={1920} height={1080} />
);
