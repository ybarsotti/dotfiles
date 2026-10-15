---
name: video-demo
description: "Make a short narrated demo video of a feature: a brief introduction, then the real flow on screen with the real cursor and clicks, camera moves and focus boxes timed to the spoken word, and captions synced word by word. Built on a Remotion template driven by one narration.json, with free edge-tts voices (English and pt-BR). Use when the user asks for a demo video, a video of a feature or a flow, a walkthrough video, a screen recording with narration, or a video for a stakeholder or a customer. Prefer it to guided-tour-video when the video is an edited, narrated demo for a stakeholder or a customer, not a quick evidence recording for a ticket or a pull request. For still images, use annotated-screenshots."
---

# Video Demo

Show a feature as a person uses it. Give a brief introduction, then let the flow carry the video. Keep the narration plain, short and non-technical.

## Rules for the video

- Start with a brief introduction: one or two sentences that say what the feature is and why a person uses it.
- Then show the flow, step by step, on the real screen. Show the result of each action.
- Say what the person does and sees. Do not name tickets, pull requests, branches, components, endpoints or code.
- Do not talk about how the video was made. Do not say "mock", "fixture", "seed", "demo data" or "test environment".
- Do not address a team and do not thank the audience.
- Use the words the screen shows. Do not explain the implementation.
- Make one short video per distinct flow (about one to three minutes each). Do not join unrelated flows into one long video.
- Narrate in English unless the user asks for another language.
- Never fake a state. If a step cannot be shown truthfully, leave it out and name it in a short closing card.

## Pipeline

```
record clips (or capture stills) -> narration.json -> voice -> render -> finish -> verify
```

The template in `assets/template/` renders everything from `narration.json`. Do not edit the React code to make a new video. Read [references/playbook.md](references/playbook.md) before you record or write the narration. It has the recorder API, the `narration.json` schema and the known traps.

### 1. Copy the template and render the example

```bash
SKILL=~/.claude/skills/video-demo
cp -R "$SKILL/assets/template" <work-dir>/video-demo
cd <work-dir>/video-demo
cp narration.example.json narration.json
npm install
npm run assets && npm run voice && npm run collect
npm run render && npm run finish && npm run verify
```

The example renders from one still. If it does not render, fix the machine before you continue.

### 2. Plan the flows

1. List the flows of the feature. Each distinct flow becomes its own video.
2. For each flow, list the screens and actions in order. One clip per screen or action.
3. Prepare the data so each clip starts in the correct state. Use a local or disposable environment only.

### 3. Record one clip per step

Copy `scripts/steps.example.cjs` to `scripts/steps.cjs` and write the flows. Then:

```bash
node scripts/record.cjs scripts/steps.cjs            # every clip
node scripts/record.cjs scripts/steps.cjs 02-save    # one clip
node scripts/collect.cjs
```

- Keep each clip 10 to 25 seconds. Glide to the element, hold, act, hold on the result.
- Hover every element that the narration points at. The hover records its box for the camera and the focus boxes.
- When the page cannot be recorded (for example, single sign-on blocks the automated browser), capture stills at 1440x900 and 2x into `public/shots/`. Use `image` instead of `clip` in the scene.

### 4. Write `narration.json`

Use these scene kinds for a demo:

| Kind | Use it for |
|---|---|
| `title` | The brief introduction: the feature name and one line. |
| `clip` | One step of the flow, recorded or as a still, with camera moves and focus boxes. |
| `compare` | Optional. The same screen before and after an action, with a wipe. |
| `cards` | Optional. A short recap of the steps. |
| `closing` | The end card. |

Every camera move and focus box has an `at`: a word from that segment's text, or a fraction of the segment. A word that is not in the text stops the render and names the segment.

Order: `title`, then one `clip` per step, then `closing`.

### 5. Voice

The default voices are `en-US-AndrewMultilingualNeural` (English) and `pt-BR-ThalitaMultilingualNeural` (pt-BR), through `edge-tts`. They are free and give the word timing that drives the captions. Use ElevenLabs only when the user asks for it and supplies the key. Never ask for a key in chat.

Write for the ear: short sentences, one action per sentence, numbers as words, absolute dates.

### 6. Preview, render and verify

```bash
npm run typecheck
npm run stills -- 02-filter=300 03-save=500   # frame numbers, writes work/stills
npm run render && npm run finish && npm run verify
```

Open `work/verify/chapters.png`. Check each still: no login screen, no spinner, no black frame, and each focus box on its target. Tell the user that you cannot hear the audio, and ask them to listen to it.

## Dependencies

| Tool | Why | Install |
|---|---|---|
| Node 20+ and npm | Remotion and the recorder | `mise` or Homebrew `node` |
| Remotion 4 | Renders the video | `npm install` in the copied template |
| `uv` | Runs the Python scripts, with `edge-tts`, `numpy` and `Pillow` on demand. No system Python is needed. | `brew install uv` |
| `ffmpeg`, `ffprobe` | Encodes clips, mixes audio, verifies | `brew install ffmpeg` |
| Playwright and Chrome for Testing | Records the clips | Any project's `@playwright/test`, then `npx playwright install chromium` |

Remotion is free for individuals and for companies of up to 3 people. A larger company needs a company license for continued use. Tell the user before this becomes a routine.

## Deliverables

Give the user the path of each `out/tour-final.mp4` and its length. For chat tools, also make a 720p copy:

```bash
ffmpeg -i out/tour-final.mp4 -vf scale=1280:-2 -crf 26 -c:a copy out/tour-720p.mp4
```
