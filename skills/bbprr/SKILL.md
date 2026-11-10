---
name: bbprr
description: Find open GitHub PRs where the user has a review request via `gh` CLI and work through the whole queue autonomously — reviewing each with `bbreview` and posting/approving per a fixed decision policy, only stopping to ask when genuinely in doubt. Use when the user invokes `/bbprr`, says "bbprr", or asks to find and review PRs requesting their review.
---

# BB PRs (`bbprr`)

Finds open GitHub pull requests where a review is requested from `@me` using the `gh` CLI and runs the `bbreview` skill on them. By default it works through **the whole queue in a loop, without human involvement**, deciding approve vs request-changes on its own (see "Decision policy"). It only stops to ask when a case is genuinely in doubt.

Optional input filter (text passed with the request): a repo name (e.g. `web-trace`, `tracevision/aws-lambda`), author, keyword, or PR number. "next" / no filter means: continue from where the previous run stopped, or start from the top of the queue.

## Step 0: Understand the mode

- **One PR** (a PR URL/number, or a filter that narrows to one) → process just that PR.
- **Loop / "next" / no filter** → process every eligible PR in the queue once, newest-updated first, no questions for the auto-decided cases.
- Track which PRs this session already handled (kept in the running log) so the loop never revisits one.

## Step 1: Query GitHub for review requests

```bash
gh search prs --review-requested=@me --state=open --draft=false --sort=updated --order=desc --json url,number,title,repository,author,updatedAt
```

Apply the optional filter (repo → `--repo <owner>/<repo>`; PR number / author / title keyword → filter results). If no non-draft PRs are found, re-check without `--draft=false` and note if only drafts are waiting. If none exist at all, say the review queue is empty and stop.

## Step 2: Decision policy (authoritative — overrides bbreview Phase 3/4)

For each PR, after `bbreview` Phase 2 has produced the deduped, bar-filtered findings:

| Situation | Action |
|---|---|
| Repo name starts with **`tracebot`** / **`TraceBot`** (case-insensitive: `TraceBot`, `tracebot-workers`, …) | **Auto-approve immediately. Do not review at all** — no checkout, no diff, no sub-agents. Just post `APPROVE`. |
| **No findings** | `APPROVE`. |
| **Only `Docs` findings** | `APPROVE` (no request-changes). Put the doc notes in the review body so they are still visible. |
| **Any `Code Quality` or `Performance` finding** | `REQUEST_CHANGES`, posting those as inline comments (plus any other accepted findings). |
| **Any `Security` or build/test-failure (`Build`) finding** | `REQUEST_CHANGES` (blocking by nature), same as code/perf. |
| **Only `Docs` / `Repo rules` / `Tests` findings** (any mix of them, no Code Quality/Performance/Security/Build) | `APPROVE`, with the notes in the review body. (Learned: the user asked twice for exactly this and chose APPROVE both times.) |
| Review could not run (checkout/diff failed, wrong base, etc.) | **ASK** with what was tried and the error. |

Rules of thumb:
- Findings were already bar-filtered by bbreview; do not re-adjudicate substance here.
- Never invent findings just to avoid approving. An empty list is a good outcome.
- If the user is the PR author, GitHub blocks approve/request-changes: fall back to event `COMMENT` and say so (bbreview Phase 4).
- Do **not** ask "which numbers?" for the auto-decided cases above — post them as-is.
- When a case is in doubt, that is the *only* time a run pauses for a human.

## Step 3: Run the queue

For each eligible PR (skip ones already handled this session):

1. If the repo name starts with `tracebot`/`TraceBot` (case-insensitive): post `APPROVE` and continue.
2. Otherwise run `bbreview` PR mode:
   - **Phase 1**: PR metadata, worktree, annotate diff, read `AGENTS.md` / `CLAUDE.md`.
     - Use a **per-PR directory** under `/tmp/bb-skillz/`, e.g. `/tmp/bb-skillz/pr<number>/` with its own `raw.diff`, `annotated.patch`, `pr.json`, and `wt` worktree. **Do not** put a PR's `annotated.patch` at the shared `/tmp/bb-skillz/bb-diff-annotated.patch` — concurrent runs overwrite each other (seen in practice).
   - **Phase 2**: launch the parallel sub-agents (`checks`, `code-security-perf`, `rules-and-tests`, `docs`) in one message (sequentially if no subagent tool).
   - **Phase 3**: dedupe, apply the substantive bar. Then **apply Step 2's decision policy instead of stopping to ask.**
   - **Phase 4**: post the review, upgrade to permanent comment links, remove the worktree/branch, delete the per-PR temp dir.
3. Print one concise line per PR: `<owner>/<repo>#<n> — <APPROVE|REQUEST_CHANGES|ASK|SKIP tracebot> — <n> findings [personas]`.
4. Continue to the next PR **without waiting**. Only pause the loop for an `ASK` case.

If the loop hits an `ASK`, stop and ask the user about that PR; after their answer, post for it and resume the remaining queue.

## Step 4: Self-improvement (always run at the end of a pass)

After the queue is done (or blocked on an `ASK`), report:

- **Handled:** each PR with its outcome and finding count.
- **Human involvement:** every `ASK`, every correction the user gave earlier in the run (wrong action, missed finding, false positive), and why it happened.
- **Proposed skill changes:** for each cause, the smallest rule that would have avoided the question/correction (e.g. a new row in the decision policy, a repo to auto-approve, a bar tweak). Apply clearly-correct one-line changes to this `SKILL.md` and say so; list anything uncertain as a suggestion and ask before changing.

The goal: each human intervention should reduce the next run's need for one.

## Notes

- `bbreview`'s "stop and wait" in Phase 3/4 is replaced by this skill's decision policy for the cases in the table. Every other bbreview step stands.
- Keep the per-PR workspace isolated; the same machine may run other reviews (human or automated) against `/tmp/bb-skillz` at the same time.
