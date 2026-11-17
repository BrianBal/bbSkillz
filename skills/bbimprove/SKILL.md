---
name: bbimprove
description: Self-improvement loop built on bbreview and bbfix. Runs bbreview in folder mode on a local repo/worktree, hands the findings to bbfix to root-cause and fix them, and repeats the review until it comes back clean. Documents false positives in AGENTS.md/CLAUDE.md (or a short why-comment) instead of coding around them. Never posts to GitHub, commits, or pushes. Use when the user asks to "bbimprove" a folder, or to keep fixing bbreview findings until none remain.
---

# BB Improve

Input: a local directory (repo or worktree). Default to cwd if none is given. A PR URL is not accepted: if given, say this skill only works on a local checkout and ask for the folder.

Read `bbreview` and `bbfix` first (siblings of this skill: `../bbreview/SKILL.md`, `../bbfix/SKILL.md`, or via your agent's skill loader). This skill is the loop around them: **bbreview finds, bbfix fixes, bbimprove decides what to do when fixing is the wrong answer.**

Keep a ledger at `/tmp/bb-skillz/bbimprove-ledger.md`: per round, each finding (`persona path:line - issue`), the action taken (fixed / documented / deferred), and the file(s) changed.

## Who runs this

The reviewer must not be the coder.
- If you wrote or edited this branch's code earlier in this session, say so in one line and ask the caller to run bbimprove from a fresh agent, such as the `reviewer` agent. Continue only if the caller insists, and then mark the Report `self-reviewed`.
- The review subagents are always fresh. They never see the coding conversation, the plan's reasoning or this ledger.

## Green

The run is **green** only when one complete review round finds zero Must and zero Should findings and the mechanical checks pass, **and** that round reviewed the final code, with nothing changed after it. Nits never block. A round that ends with fixes is never the last round: the fixes need their own review.

## Loop (max 5 rounds)

1. **Review.** Run `bbreview` in **pre-PR mode**, Phases 1-3 only (gather, persona subagents including `blast-radius`, the tiered list). Every round reviews the **whole branch against its merge-base**, not just what changed since the last round. Fix commits caused a large share of our PR review findings, and a delta-only review misses what a fix broke nearby. Use fresh subagents, and don't give them the ledger or say what was fixed: reviewers must judge the current code and docs cold, or doc updates are never actually tested. Don't stop for the user after Phase 3; this skill replaces that step.
2. **Green?** If the round meets the Green rule, stop and go to Report.
3. **Fix.** Hand every Must and Should finding, plus any `unsure` one, to `bbfix` in list mode with the folder path. Pass them verbatim; bbfix settles `unsure` items by reading or running the code. Also fix a Nit when it is a one-line change in a file you are already touching; leave the rest listed. bbfix owns the investigation (root cause, apply, verify); don't re-litigate its reasoning. Ask bbfix to grep for **every other instance** of each root cause, not just the reported line. A reviewer's finding is a class of bug until proven otherwise.
4. **Handle bbfix's leftovers.** bbfix reports anything it judged invalid, not reproducible, or needing a decision. Decide per item:
   - **Document**: the finding is wrong or the code is intentional, and the reviewer flagged it because it lacked context. Verify this by reading the code; never document away a real bug, security issue, or failing check. Put the context where the reviewers read it:
     - a repo-wide convention or rule -> one concise line in the root `AGENTS.md` / `CLAUDE.md` (whichever the repo uses; prefer an existing section), or that directory's `CLAUDE.md` if it is directory-specific
     - a one-off non-obvious choice -> a one-line comment at the site saying *why*
     - keep it short: bbreview's repo-rules persona flags verbose docs. One line per rule; no duplicates.
   - **Defer**: it needs a product/design decision only the user can make, or the fix is large/risky (schema change, public API break, cross-team code). Change nothing; note it for the Report.
5. **Re-check.** Re-run the mechanical checks touched by the fixes (build/tests/lint). Failures go back to bbfix within this round.
6. **Recurrence check.** Compare against earlier rounds in the ledger. A finding that reappears after being "fixed" or "documented" means that approach did not work: on its second appearance try the other approach (a stronger fix, or a clearer/better-placed doc line); on its third, defer it. Deferred findings that reappear later are ignored for the "clean" decision.
7. Next round. Stop when a round meets the Green rule, when a round's only findings are already-deferred items, or after round 5.

## At the cap

If round 5 ends with fixes applied, or with Must/Should findings still open, the result is **NOT GREEN**. Never call the branch ready or clean.
1. Run one last review round (round 6, review only, no fixes). The cap must never leave fixes unreviewed.
2. Report `NOT GREEN at cap` with every open finding, deferred or not, and with what kept recurring. Repeated findings in one area usually mean a design problem, not a bug, so say which area.
3. The caller (HQ) decides: re-plan that area, take it to the user, or explicitly accept the listed findings. Don't open the PR without that decision.

## Rules

- Never commit, push, post to GitHub, or switch branches. All changes stay uncommitted in the folder.
- Don't edit files outside the folder, and don't touch bbreview's or bbfix's SKILL.md (repo docs are the place for repo context).
- Stay in scope: resolve findings, don't refactor beyond them. If a fix keeps spawning findings in unrelated code, defer.
- One-line status after each round (e.g. "Round 2: 6 findings - 4 fixed, 1 documented, 1 deferred").
- If your host has no subagent tool, run bbreview and bbfix sequentially rather than skipping steps, and say so.

## Report
Short summary:

- First line: `GREEN after N rounds`, or `NOT GREEN at cap`, or `self-reviewed` (see Who runs this).
- Every round's counts by tier (`R1: 3 Must, 7 Should, 4 Nit`). **Every finding from every round** is in the ledger with its outcome, and the Report links the ledger. Nothing is held back: list the Nits left unfixed, too.
- Code fixes: file list, one line each, taken from bbfix's report.
- Doc changes: quote each line added to CLAUDE.md/AGENTS.md so the user can veto any.
- Findings rejected by bbfix as invalid, with the one-line reason.
- Deferred findings, numbered, each with a one-line reason and suggested fix, so the user can reply with numbers to have them done.
- Final build/tests/lint status.
