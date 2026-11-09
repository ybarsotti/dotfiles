---
name: release
description: Use when the user asks to cut, ship or tag a release of the current repository, bump a version, merge a release-please Release PR, or asks what the next version is or what a release would ship. Detects the release mechanism (a release-please Release PR, another release tool, or plain semver tags per app), reviews what ships, runs the project's checks, and creates the tag and the GitHub release only after the user confirms. Then hands off to the release-announce skill. Works in any repository. Never force-pushes and never tags without confirmation.
---

# Release

Cut a release of the current repository. The skill finds how the repository releases, shows
what the release ships, runs the checks, and asks before it changes anything. Merging a Release
PR, pushing a tag and publishing a GitHub release each wait for the user's "yes" for that exact
version.

**Arguments:** an optional app (a name or a folder) and an optional bump: `auto`, `patch`,
`minor`, `major` or an explicit `X.Y.Z`. The default bump is `auto`.

## Never

- Force-push, move a tag, delete a tag, or delete a release.
- Create a tag, merge a Release PR, or publish a release before the user confirms that version
  in this conversation. A request to "cut a release" authorizes the review, not the tag.
- Push a commit to the default branch. A version bump that no tool owns goes through a PR.
- Edit a file that a release tool owns, such as `CHANGELOG.md` or a release-please manifest.
- Deploy. A deploy is outside this skill.
- Merge with `--admin` or skip a required check.

## 1. Check the environment

```bash
git status -sb
BRANCH=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)
git fetch origin --tags --quiet
git rev-parse HEAD "origin/$BRANCH"
gh auth status
```

- Stop on uncommitted changes. Ask before you stash, switch branches or pull.
- Release from the default branch only. When `HEAD` differs from `origin/$BRANCH`, ask before
  `git switch "$BRANCH" && git pull --ff-only`.
- When `gh` is not signed in, ask the user to run `gh auth login`.

## 2. Detect the mechanism

Check in this order. Report the mechanism and the file or tag that proves it.

1. **A project recipe.** A `release` recipe in the `justfile`, the `Makefile` or the
   `package.json` scripts, or a release procedure in `CLAUDE.md`, `AGENTS.md` or
   `CONTRIBUTING.md`. Read it. Follow it instead of this skill's mechanism, and keep the rules
   of this skill.
2. **release-please.** `release-please-config.json` or `.release-please-config.json`, plus a
   manifest. Find the open Release PR:

   ```bash
   gh pr list --state open --label 'autorelease: pending' \
     --json number,title,url,headRefName,baseRefName
   ```

3. **Another release tool.** `.changeset/` (changesets), `.releaserc*` or `release.config.*`
   (semantic-release), `.goreleaser.y*ml` (GoReleaser). Follow that tool's own flow. This skill
   still reviews, runs the checks and asks first.
4. **Tags only.** List the tags: `git tag --list --sort=-v:refname | head -20`.
   - `vX.Y.Z` means one version for the repository.
   - `<app>-vX.Y.Z` means one version per app. The app folders are in `apps/*/`, in
     `project.json`, or in the release-please `packages`.
5. **No release yet.** Propose `v0.1.0`, or `<app>-v0.1.0` for each app, and ask.

Ignore pre-release tags such as `v1.2.0-rc.1` when you look for the last release.

## 3. Review what ships

Find the last release tag of each app, then read every commit after it:

```bash
LAST=$(git describe --tags --abbrev=0 --match "${PREFIX}v[0-9]*" --exclude '*-rc*' "origin/$BRANCH")
git log --oneline "$LAST..origin/$BRANCH" -- "$APP_PATH"
```

`PREFIX` is empty for `vX.Y.Z` tags and `<app>-` for per-app tags. `APP_PATH` is `.` for one
version.

- **Release PR current.** For release-please, `git merge-base origin/$BRANCH
  origin/<Release PR head>` must equal `origin/$BRANCH`. When it differs, list the commits that
  the PR lacks and say that the PR is stale. The release-please workflow refreshes it after the
  next push to the default branch.
- **The PRs.** Take the PR number from `(#123)` in a squash subject, or from
  `gh api repos/{owner}/{repo}/commits/<sha>/pulls --jq '.[].number'`. For each PR, read the
  author, the approvals (`gh pr view <n> --json reviews`) and the body. Count the PRs merged
  with no approval.
- **The risks.** Name each migration, each change to authentication or permissions, each
  change to money or billing, each new environment variable, and each major dependency bump.
  Copy every post-release step that a PR body lists, in order.
- **CI.** Read the runs on the release commit:
  `gh run list --commit <sha> --json name,status,conclusion`. A failed or missing run stops
  the release until the user decides.

Report a short table: app, current version, next version, commits by type, PRs, risks and
post-release steps.

## 4. Compute the next version

release-please computes the version itself. Read it from the Release PR title or body. A
forced bump is a `Release-As: X.Y.Z` footer on a commit, or the release-please CLI
`--release-as` flag. Ask before you use either.

For tags only, compute it from the Conventional Commits since the last tag, per app:

| The commits contain | The bump |
|---|---|
| `!` after the type, or a `BREAKING CHANGE:` or `BREAKING-CHANGE:` footer | major (minor before 1.0.0) |
| a `feat` | minor |
| a `fix`, `perf` or `revert` | patch |
| other types only | no release. Say so, and offer a patch. |

An explicit `patch`, `minor`, `major` or `X.Y.Z` argument wins. When the project has a
`release-notes` recipe (`just release-notes <app>`), use its output as the preview.

## 5. Run the checks

Run the gate that the project defines: read `CLAUDE.md`, `AGENTS.md` and the CI workflows to
find it, for example `just check` or `make check`. Run one full suite at a time, with capped
workers. A failure stops the release. Report the command and its result.

## 6. Ask for confirmation

Show, in one message:

- the mechanism;
- each tag to create, or the Release PR to merge, with its URL;
- the exact commit SHA that each tag points to;
- the notes preview;
- the result of the checks and of CI.

Ask one question: "Release `<tag>` at `<sha>`?" Then wait.

## 7. Release

**release-please.** Merge the Release PR with the merge method that the repository allows
(`gh repo view --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed`):

```bash
gh pr merge <n> --squash   # or --merge / --rebase
```

The release-please workflow then creates the tags and the GitHub releases. Wait for the run,
then confirm with `gh release list --limit 5`. When the repository has no such workflow, run the
CLI. Export the token on its own line: in `GH_TOKEN=$(gh auth token) npx ... --token="$GH_TOKEN"`
the shell expands `$GH_TOKEN` before the assignment, so the CLI gets an empty token.

```bash
export GH_TOKEN=$(gh auth token)
npx -y release-please@17 github-release --token="$GH_TOKEN" \
  --repo-url=<owner>/<repo> --config-file=<config> --manifest-file=<manifest>
```

**Tags only.** For each app that changed:

```bash
git tag -a "$TAG" -m "$TAG" "$SHA"
git push origin "refs/tags/$TAG"
gh release create "$TAG" --verify-tag --title "$TAG" --notes-file "$NOTES"
```

`$NOTES` is a file with the notes preview that the user confirmed in step 6. Without a preview,
use `--generate-notes` instead of `--notes-file`. Push the tag ref only, never a branch. When a version file such as `package.json` or `pyproject.toml` must change
first, open a PR with the bump, wait for its merge, and tag the merge commit.

## 8. Hand off

1. Invoke the `release-announce` skill with the new tags. It drafts the team announcement, one
   comment per ticket and the changelog body. It never posts.
2. Report: the tags, the release URLs, the post-release steps in order, and what to watch
   after the deploy.
