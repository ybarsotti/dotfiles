---
name: annotated-screenshots
description: Produce annotated feature screenshots for a stakeholder, a PR, or a ticket. Captures the live app or a component rendered with fixture data at 2x through agent-browser, lists element boxes, then draws highlight boxes, numbered callouts with leader lines, and a caption banner that says whether the image is the live app or a fixture render. Use when the user asks for screenshots of a feature, annotated or highlighted screenshots, screenshots "with numbers", a visual walkthrough as images, or before/after images of a UI change. For a narrated demo video, use video-demo instead. For QA evidence tied to a test plan, use qa-test-plan.
---

# Annotated Screenshots

Each image shows one screen with up to five highlighted elements. Each highlight has a
numbered pill and a leader line. A banner under the image gives the title and the source.
The notes that go with the images use the same numbers.

## Dependencies

| Need | Check | Install |
|---|---|---|
| agent-browser CLI and its Chrome | `agent-browser --version` | `brew install agent-browser`, then `agent-browser install` |
| uv (runs `annotate.py` with Pillow) | `uv --version` | `brew install uv` |
| jq (`shoot.sh` decodes the box list) | `jq --version` | `brew install jq` |
| A bold and a regular font | Arial on macOS, DejaVu Sans on Linux | The script falls back to the Pillow default font |
| Component render only: the project's Node, jest and Testing Library | the project's test command | the project's install |

`annotate.py` declares Pillow as inline script metadata. `uv run` installs it in a cache, so
there is nothing to install in the project.

The scripts live in `~/.claude/skills/annotated-screenshots/scripts/`. The workflow runs in a
scratch directory, so call them by that full path. The examples below use `$SKILL` for it:
`SKILL=~/.claude/skills/annotated-screenshots`.

## Workflow

Keep the work in one directory outside the repository, for example `<scratch>/shots/`:
`raw/` for captures, `screenshots/` for the output, and `spec.json`.

1. **Plan the images.** Write one line per image: the screen, the state, and the 1 to 5
   things to point at. One image explains one idea.
2. **Choose the capture mode per image.**
   - Live page: the persona can reach the screen and the data is in the right state.
   - Component render: the screen is hard to reach, or the state is hard to create.
   Read [references/capture.md](references/capture.md) before the first capture of each mode.
3. **Capture.** Run `$SKILL/scripts/shoot.sh` for each image:
   ```bash
   # Live page in a logged-in session
   $SKILL/scripts/shoot.sh https://app.local/tasks/123 raw/task.png --session app-login
   # Component render: HTML fragment from the harness, wrapped with the app CSS
   $SKILL/scripts/shoot.sh out/tracker.html raw/tracker.png --css app.css --width 900 --height 760
   # The whole page, for an element below the fold
   $SKILL/scripts/shoot.sh out/tracker.html raw/tracker-full.png --css app.css --full
   ```
   The script writes `raw/<name>.png` at 2x and `raw/<name>.boxes.txt` with element boxes in CSS px.
   A fragment also writes `raw/<name>.page.html`, the wrapper page. Open it in a browser to
   check the render. Without `--session`, the script uses a new browser session and closes it.
4. **Look at the raw capture.** Confirm the state is right: no spinner, no login page,
   no error toast, the expected data.
5. **Write `spec.json`.** Copy each box from `*.boxes.txt`. Do not estimate coordinates from
   the image preview. Read [references/spec.md](references/spec.md) for the format, the tone
   convention and the placement rules.
6. **Annotate.** Run `$SKILL/scripts/annotate.py spec.json`. Add `--only <out-name>.png` to
   redraw one image.
7. **Check every output image.** Each box is on its target. No pill covers text that a mark
   points at. Leader lines do not cross pills. The text is readable at the size the reader sees.
   Move `label_at` or change `crop`, then run step 6 again.
8. **Deliver.** Give the image paths and the numbered notes. Use the legend that the script
   prints, so the numbers match.
9. **Clean up.** Close each session that you opened with `--session`:
   `agent-browser --session <name> close`. Delete the harness file if you copied it into a project.

## Rules

- Label the source of every image. A fixture render is `"source": "fixture"`, never live.
  The caption must not claim more than the image proves.
- Put the persona, environment and date in `source_note` for a live capture.
- Use local or test data. Do not create or change production data for a screenshot.
- Hide secrets, tokens, real customer emails and payment data. Crop them out or use fixtures.
- Delete the temporary harness test file after the capture. Never commit it.
- Name output files with a two-digit order prefix: `01-<screen>-<idea>.png`.
