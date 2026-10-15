# Capture details

## Contents

- Live page
- Component render
- Get the compiled CSS
- Known problems

## Live page

Use the live app when the persona can reach the screen and the data is in the right state.

1. Log in once in a named agent-browser session. Use `agent-browser --session app-login open <login-url>`.
   Reuse that session name with `$SKILL/scripts/shoot.sh --session app-login`. The script leaves
   that session open. Close it with `agent-browser --session app-login close` when the capture is done.
2. Put the page in the state to show: open the panel, apply the filter, hover the chip.
   Use `agent-browser --session shots click|hover|scrollintoview ...` before the capture.
3. To capture without a new navigation, give `shoot.sh` the current URL. The script
   opens it again, so a state that a reload loses must be recreated. For that case, run the
   steps of `shoot.sh` by hand: `set viewport`, `screenshot`, then
   `eval "$(cat $SKILL/scripts/boxes.js)" | jq -r .`.
4. Scroll the target into the top part of the viewport. Boxes are relative to the viewport,
   not the document, so capture and list boxes at the same scroll position.

Record the environment, the persona and the date in `source_note`. Use the data that
exists in a local or test environment. Do not create or change data in production for a
screenshot.

## Component render

Use a component render when the persona cannot reach the screen, the data state is hard
to create, or the app does not run. The image shows the real component code with fixture
data, so label it `"source": "fixture"`.

1. Copy `$SKILL/assets/render-harness.test.tsx` into a scratch directory outside the repository,
   for example `<scratch>/harness/shot.test.tsx`.
2. Import the component. Use the project's render helper and the fixture builders of the
   component's existing tests. Path aliases such as `@/` still resolve through the project config.
3. Run only that file from the project's frontend directory, with the scratch directory as an
   extra root:
   ```bash
   SHOT_DIR=<scratch>/shots/out SHOT=tracker TZ=UTC \
     <pm> jest --roots <scratch>/harness --modulePaths <frontend>/node_modules <scratch>/harness/shot.test.tsx
   ```
   Do not run the full suite.
4. Run `$SKILL/scripts/shoot.sh <SHOT_DIR>/<SHOT>.html raw/<name>.png --css app.css`.

Fallback: if the project's jest config rejects a root outside the repository, copy the harness
into the project's test directory, run it there, and delete it afterwards. Never commit it.

A jsdom render has no layout, so it cannot measure size. Components that measure the
DOM (virtual lists, charts, auto-sizing text) can render empty. Use the live page for them.

## Get the compiled CSS

The wrapper page needs the stylesheet the app serves, not the source CSS.

- Next.js dev server: open the app page, then list the stylesheets:
  `agent-browser eval "[...document.styleSheets].map(s => s.href).filter(Boolean).join('\n')"`.
  Download each with `curl -k -o app.css <href>`; concatenate them if there are several.
- A production build: use the CSS files under the build output, for example `.next/static/css/`.
- Tailwind without a running app: compile the entry CSS with the project's Tailwind CLI,
  for example `npx @tailwindcss/cli -i app/globals.css -o app.css`.

Tailwind compiles only the classes it finds in the sources at compile time. Get the CSS
again after you add a class, or the new class renders with no style.

## Known problems

| Symptom | Cause | Fix |
|---|---|---|
| Fonts fall back to the system font | `@font-face` URLs are root-relative and the page is `file://` | Pass `--base http://localhost:3000/` while the dev server runs, or accept the system font |
| An element has no style | The class was not in the compiled CSS | Get the CSS again |
| A date is one day off | The harness ran in the machine time zone | Run it with a fixed `TZ` |
| A tooltip or menu is missing | It renders in a portal only while open | Open it in the harness or the session before the capture |
| A dev overlay badge shows | Framework dev tools | `shoot.sh` hides `nextjs-portal`; hide others with an `eval` style rule |
| The image looks small in review | The image viewer scales large images down | Read coordinates from `*.boxes.txt`, never from the scaled preview |
