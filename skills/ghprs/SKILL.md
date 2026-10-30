---
name: ghprs
description: Find an open GitHub PR where the user has a review request via `gh` CLI and run `bb-review` on it. Use when the user invokes `/ghprs`, says "ghprs", or asks to find a PR requesting their review and review it with bb-review.
---

# GH PRs (`ghprs`)

Finds open GitHub pull requests where a review is requested from `@me` using the `gh` CLI, selects a PR, and runs the `bb-review` skill on it.

Optional input filter (the text the user passed with the request): a repo name (e.g. `web-trace`, `tracevision/aws-lambda`), author, keyword, or PR number.

## Step 1: Query GitHub for review requests

Run `gh search prs`:

```bash
gh search prs --review-requested=@me --state=open --draft=false --sort=updated --order=desc --json url,number,title,repository,author,updatedAt
```

If an optional filter was passed with the request:
- If it matches a repo name or `<owner>/<repo>`, filter to that repo (or pass `--repo <owner>/<repo>`).
- If it matches a PR number, author, or title keyword, filter the results to matching PRs.

If no non-draft PRs are found, re-check without `--draft=false` and note if only draft PRs are waiting. If none exist at all, tell the user their review queue is empty and stop.

## Step 2: Pick the PR

- **Single match** (or the user asked for "a PR" / "the latest" / gave a filter that narrows to one): pick the most recently updated PR and state which PR is being reviewed (`<owner>/<repo>#<n>: <title> (<url>)`).
- **Multiple matches and no filter**: show a concise numbered list of the open review-requested PRs (`N. <owner>/<repo>#<num> - <title> (@<author>, updated <date>) — <url>`) and either:
  - Immediately start `bb-review` on `#1` (the most recently updated PR) if the user asked to find **a** PR and review it, OR
  - If the user asked to choose from the list first, ask which number to review.
  Default behavior when invoked as `/ghprs` with no extra instructions: list the queue briefly, pick `#1` (most recently updated non-draft PR), and proceed directly into `bb-review` for its URL.

## Step 3: Trigger `bb-review`

Load the `bb-review` skill (or read its `SKILL.md` from the sibling `bb-review` directory) and execute its full **PR mode** workflow on the chosen PR's `url` (`https://github.com/<owner>/<repo>/pull/<n>`):
1. **Phase 1**: Gather PR metadata, checkout worktree in `/tmp/bb-skillz`, annotate diff into `/tmp/bb-skillz/bb-diff-annotated.patch`, read `AGENTS.md` / `CLAUDE.md`.
2. **Phase 2**: Launch the parallel sub-agents (`checks`, `code-security-perf`, `rules-and-tests`, `docs`) via the Task tool (sequentially if your agent has no subagent tool).
3. **Phase 3**: Dedupe, apply the substantive bar, present the numbered findings list + checks status, and wait for the user's reply.
4. **Phase 4**: Post the review (`APPROVE` or `REQUEST_CHANGES`) via `gh api` once the user responds, then clean up the temporary worktree/clone.
