# Video demo playbook

Contents: 1. Recording · 2. narration.json · 3. Voice and assets · 4. Preview · 5. Render · 6. Traps

The template is in `assets/template/`. One file, `narration.json`, drives what the video says and shows.

## 1. Recording

`scripts/record.cjs` opens the page in a 2880x1800 viewport with CSS `zoom: 2`, so the screencast is 2x and stays sharp when the camera zooms. It starts a Chrome screencast through CDP and logs, with timestamps, the cursor path, every click, and the box of every element that it hovers or clicks (as `target` events, labelled with the Playwright locator text). `rec.stop()` encodes `public/clips/<name>.mp4` at a constant 30 fps and writes `public/clips/<name>.json`.

The steps file (copy `scripts/steps.example.cjs`) sets:

| Key | Meaning |
|---|---|
| `playwright` | Path to a `node_modules/@playwright/test` directory. |
| `chrome` | Optional. Path to a Chrome or Chrome for Testing executable. Without it, Playwright uses the browser that it installed. |
| `storageState` | A logged-in session saved with `context.storageState()`. Omit it for a public page. |
| `base` | The base URL that `open(path, waitMs)` uses. |
| `locale`, `timezoneId` | Optional. The locale and the time zone for dates on screen. |
| `clips` | A map from clip name to `async ({ page, rec, open, W, H }) => { ... }`. |

Recorder calls: `rec.start(name)`, `rec.click(locator, glideMs)`, `rec.hover(locator, glideMs, { x, y })`, `rec.type(text)`, `rec.hold(ms)`, `rec.fixPoppers()`, `rec.stop()`.

Choreography:

- One clip per screen or action, 10 to 25 seconds. Glide to the element, hold one second, act, hold on the result.
- The narration sets the scene length. The clip plays at 0.9x to 1.6x to fit, and freezes on its last frame if it is shorter.
- Hover every element that the narration points at. A hover is also a measurement for the camera and the focus boxes.
- Keep the mouse still while the page loads. The screencast sends frames only when something changes.
- Put the data in the correct state before each take, and read the state back before you record. A clip in the wrong state costs the most time.

Traps the recorder already handles:

| Trap | What the recorder does |
|---|---|
| A screencast at `deviceScaleFactor: 2` returns 1x frames. | It uses a 2880x1800 viewport at scale 1 with CSS `zoom: 2`. |
| Radix popovers land at twice their offset under CSS zoom. | Call `rec.fixPoppers()` after you open one. |
| `locator.click()` times out under CSS zoom. | `rec.click` moves the real mouse to the box and presses. |
| Frames of the wrong size. | `rec.stop()` checks the last frame and throws if it is not 2880x1800. |

If a locator does not resolve, query the DOM for the accessible name. Do not guess twice.

**Stills.** When the page cannot be recorded, capture stills at 1440x900 and 2x into `public/shots/` (Playwright `page.screenshot()` with `deviceScaleFactor: 2`). To join four browser zoom tiles into one still, run `uv run --no-project --with pillow python scripts/stitch.py <tiles dir> <scenes.json> <output dir>`. Use `image` instead of `clip` in the scene. Focus boxes then take a `rect` measured on the still: read the pixel position on the 2x image and divide by two.

## 2. narration.json

Top level:

| Key | Meaning |
|---|---|
| `coordinateSpace` | `[1440, 900]`. Camera centres and rects use this space. Recorded boxes convert automatically. |
| `voice.edge` | The edge-tts voice. |
| `voice.eleven` | Optional ElevenLabs `voice_id` and `model`. |
| `spelled` | Map from a spoken form to a caption form, for example `{"C S V": "CSV"}`. |
| `segments` | The scenes, in order. One paragraph of narration each. |

Every segment has `id`, `kind`, `chapter` and `text` (the exact words the voice says). The id is also the audio file name, so keep ids sortable (`01-intro`, `02-filter`). A `clip` chapter written as `Flow · Save the view` shows a chip with both parts on screen.

| Kind | Fields |
|---|---|
| `title` | `eyebrow`, `title`, `accent`, `subtitle: { at, text }` |
| `clip` | `clip` or `image`, `clipStart`, `camera`, `focus` |
| `compare` | `before`, `after` (clip names or files in `public/shots`), `wipe: { at }` |
| `cards` | `kicker`, `title`, `layout` (`row`, `column`, `grid`), `cards`, `banner`, `footnote`, `signoff` (optional last line) |
| `closing` | like `cards`, plus `endcard: { at, title, subtitle }` |

A card is `{ "at", "title", "note", "eyebrow", "chip", "tone" }`. A banner, footnote or subtitle is `{ "at", "text", "tone" }`. Tones are `accent` (the default), `amber` and `red`.

**Timing.** `at` is a word from the segment text (`"button"`, or `"button#2"` for the second time it is said) or a fraction of the segment (`0.1`). The match ignores case, accents and punctuation. A spelled acronym is several words, so trigger on a neighbouring word.

For a `clip`:

- `camera` is a list of `{ "at", "zoom", "cx", "cy" }` or `{ "at", "zoom", "target" }`. With `target`, the camera centres on the recorded box whose locator text contains the string. Add `cx` or `cy` to override one axis. The first entry is the start frame. Each later entry starts an eased move of about one second.
- `focus` is a list of `{ "at", "target" | "rect": [x0, y0, x1, y1], "hold", "label", "tone" }`. The area outside the box is dimmed. `label` adds a tag under the box. `hold` is seconds on screen (default 4).
- `clipStart` skips the first seconds of the clip, for example a page load.

**Writing the narration.**

- Introduction: say what the feature is and why a person uses it, in one or two sentences.
- Each clip: say what the person does, then what they see. One action per sentence.
- Use the labels that the screen shows. Do not name code, tickets or pull requests.
- Write numbers as words. Use absolute dates, never "yesterday".
- In pt-BR, use the Portuguese word for what the voice must say, and keep on-screen names as they appear.
- Closing: one sentence that names what the video did not show, if anything.

## 3. Voice and assets

```bash
npm run assets   # once: public/sfx and public/grain
npm run voice    # public/audio/<id>.mp3 and src/manifest.json with the start of each word
```

The voice step reuses unchanged segments. To redo some segments only: `uv run --with edge-tts python scripts/tts.py edge 02-filter 04-closing`.

ElevenLabs is optional and only on request. The user supplies the key in `~/.config/elevenlabs.env` (mode 600). Load it with `set -a; . ~/.config/elevenlabs.env; set +a`, set `voice.eleven.voice_id`, then run `uv run --no-project python scripts/tts.py eleven`. Iterate with `edge` first. The narration text goes to a third party, so keep customer names out of it.

The video has no music bed. `scripts/finish.sh` normalizes the voice and the sound effects only. Add music only when the user asks and listens to the result.

## 4. Preview

```bash
npm run typecheck
npm run stills -- 01-intro=120 02-filter=300   # frame numbers, writes work/stills
npm run studio
```

`tts.py` prints the length of each segment. A segment lasts its audio plus 1.2 seconds, at 30 fps. Consecutive scenes overlap by 14 frames. Render a still inside each `clip` after its focus box appears. A box beside its target means that the `target` string matched the wrong element, or that a `rect` was measured on the wrong image.

## 5. Render

```bash
npm run render    # out/tour.mp4
npm run finish    # out/tour-final.mp4 at -16 LUFS, 48 kHz stereo, yuv420p
npm run verify    # streams, duration, loudness, work/verify/chapters.png
```

Open `chapters.png`: one still per scene, with no login screen, no spinner and no black frame.

## 6. Traps

| Trap | Fix |
|---|---|
| No progress output during the render. | Do not pass `--log=error`. |
| The mp4 is missing during the render. | Remotion writes it at the end. Wait for the process to exit. |
| A clip recorded in the wrong data state. | Reset, read the state back, record again. |
| A focus box on the wrong element. | Make the `target` string more specific, or use `rect`. |
| A trigger on a spelled acronym never fires. | Trigger on the word next to it. |
| English terms in a pt-BR narration sound wrong. | Use the Portuguese word, or keep the term on screen only. |
| `src/manifest.json` is missing at typecheck. | Run `npm run voice` first. It writes the manifest. |
| Low disk space. | A raw 1080p render is about 1.2 MB per second. Delete `out/tour.mp4` after `tour-final.mp4` is verified. |
