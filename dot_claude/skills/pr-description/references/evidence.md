# Evidence section (Phase 2.5)

**A UI change without a picture is not reviewable.** Decide first whether this diff changes
anything a user sees — a new screen, an altered layout, new copy, a changed interaction or
state. `git diff --name-only main...HEAD` hitting component/template/style/page paths is the
signal; when it is ambiguous, assume it does.

If it does not, write exactly `_no UI change — no visual evidence_` under `## Evidence` and
move on. Never leave the section out and never invent a screenshot.

If it does, the section carries, in this order:

1. **A GIF or recording of the flow working end to end** — the whole path a user takes, not a
   still of the end state. New screen or changed flow ⇒ this is required.
2. **Before / after screenshots** for anything that changed on an existing screen.
   Run `~/.claude/skills/_shared/scripts/video-check.sh <file>` on each video and GIF first.
   A file that fails shows a still screen, not a flow: never attach it. Record the flow with
   the `video-demo` skill, or attach screenshots and say that no video exists.
3. **A link to the QA evidence report** (`index.html`) that these came from, plus the commit
   SHA it was captured against.

Source them, in order of preference: the `--evidence` artifacts; the QA run this PR follows
(the `qa-business` agent and `/qa-execute` already capture annotated screenshots and
WebVTT-captioned videos); a fresh `agent-browser` pass over the changed flow if neither exists and the app runs
locally.

**Embedding.** Never commit media to the repository, on any branch. Upload it with the
`--attach` flag of `gh pr create` or `gh pr edit` (gh 2.99.0 or later):

1. Write the body with relative references, such as `![Login error state](./qa/login.png)`.
2. Pass each referenced file once: `--attach ./qa/login.png`.

gh uploads each file to `github.com/user-attachments/assets/` and rewrites the reference to that
URL. The asset has the repository's visibility, so a private repository stays private. Formats:
PNG, JPEG, GIF, WebP, SVG, MP4, MOV and WebM. Size: 10 MB per image, and 10 MB per video on Free
or 100 MB on a paid plan. Compress a GIF or video that exceeds the limit; do not drop it.

When `gh` exits nonzero, read which files failed and retry them with `gh pr edit --attach`. When
`gh` is older than 2.99.0 or the host is GitHub Enterprise Server, list each asset by filename
with what it demonstrates, say the media is local, and tell the user in Phase 4 to drag it in.

Evidence is captured against the frozen SHA. If the branch moved after the capture, say so
rather than presenting stale media as current.
