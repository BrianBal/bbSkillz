---
name: bb-improve
description: Self-improvement loop on top of bb-review. Runs bb-review in folder mode on a local repo/worktree, then resolves every finding without asking - fixing the code when the finding is real, or updating CLAUDE.md/AGENTS.md (or a short why-comment) when it is a false positive so future reviews stop raising it - and repeats the review until it comes back clean. Never posts to GitHub, commits, or pushes. Use when the user asks to "bb-improve" a folder, or to keep fixing bb-review findings until none remain.
---

# BB Improve

Input: a local directory (repo or worktree). Default to cwd if none is given. A PR URL is not accepted: if given, say this skill only works on a local checkout and ask for the folder.

Read the `bb-review` skill first (sibling directory: `<skills>/bb-review/SKILL.md`, or via your agent's skill loader). Each round runs its **folder mode, Phases 1-3 only** (gather, persona subagents (Task tool, or sequentially if your agent has no subagent tool), dedupe into a numbered list). Skip its Phase 4 and do not stop to wait for the user after Phase 3; this skill replaces that step.

Keep a ledger at `/tmp/bb-skillz/bb-improve-ledger.md`: per round, each finding (`persona path:line - issue`), the action taken (fixed / documented / deferred), and the file(s) changed.

## Loop (max 5 rounds)

1. **Review.** Run bb-review folder mode Phases 1-3 with fresh subagents (Task tool). Do not give them the ledger or tell them what was fixed; the reviewers must judge the current code and docs cold, otherwise doc updates aren't actually tested.
2. **Clean?** If the list is empty (mechanical checks pass and no findings), stop and go to Report.
3. **Resolve every finding.** For each, decide:
   - **Fix** (default): the finding is real. Make the smallest change that resolves it, matching surrounding code. Includes build/test/lint failures.
   - **Document**: the finding is wrong or the code is intentional, and the reviewer flagged it because it lacked context. Verify this by reading the code; never document away a real bug, security issue, or failing check. Put the context where the reviewers read it:
     - A repo-wide convention or rule -> a concise line in the root `AGENTS.md` / `CLAUDE.md` (whichever the repo uses; prefer an existing section). If a directory-specific one, the `CLAUDE.md` in that directory.
     - A one-off non-obvious choice -> a one-line comment at the site saying *why*.
     - Keep it short: bb-review's repo-rules persona flags verbose docs. One line per rule; no duplicates of existing rules.
   - **Defer**: needs a product/design decision only the user can make, or the fix is large/risky (schema change, public API break, cross-team code). Don't change anything; note it for the Report.
4. **Re-check.** Re-run the mechanical checks touched by the fixes (build/tests/lint). Failures go back into step 3 within this round.
5. **Recurrence check.** Compare against earlier rounds in the ledger. A finding that reappears after being "fixed" or "documented" means that approach didn't work: on its second appearance try the other approach (a stronger fix, or a clearer/better-placed doc line); on its third, defer it. Deferred findings that reappear in later rounds are ignored for the "clean" decision.
6. Next round. Stop when a round's findings are all already-deferred items, or after round 5.

## Rules

- Never commit, push, post to GitHub, or switch branches. All changes stay uncommitted in the folder.
- Don't edit files outside the folder, and don't touch bb-review's SKILL.md (repo docs are the place for repo context).
- Stay in scope: resolve findings, don't refactor beyond them. If a fix keeps spawning new findings in unrelated code, defer.
- Give a one-line status after each round (e.g. "Round 2: 6 findings - 4 fixed, 1 documented, 1 deferred").

## Report

Short summary:
- Rounds run, and whether the last review was clean or the cap was hit.
- Code fixes (file list, one line each).
- Doc changes (quote each line added to CLAUDE.md/AGENTS.md so the user can veto any).
- Deferred findings, numbered, each with a one-line reason and a suggested fix, so the user can reply with numbers to have them done.
- Final build/tests/lint status.
