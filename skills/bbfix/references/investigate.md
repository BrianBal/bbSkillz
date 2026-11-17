# Investigate: the step between review and fix

Review finds, investigate decides, fix executes. **Nothing gets fixed without a completed investigation entry**, and every finding ends up in exactly one bucket, so nothing is held back silently. Both `bbimprove` (pre-PR findings) and `bbfix` (PR feedback, issue lists) use this contract.

Why it matters: a stricter review reports dozens of findings per PR. Fixing all of them blind adds code, and that code draws the next round of findings. Investigation keeps the fix list to the findings that are real and that matter, and makes each fix planned rather than reflexive.

## Who investigates

An agent that didn't write the code: a fresh subagent per finding, or per small group of findings in the same file or with an obviously shared cause. Give it the finding verbatim, the worktree path, the repo rules (`AGENTS.md` / `CLAUDE.md` / `REVIEW_GUIDELINES.md`) and the **direction sources** below. Don't give it the coding conversation. It changes no code, but it may write and run a throwaway test to prove a finding, and must remove that test afterwards.

## Direction sources

The finding is checked against what the user has already decided. For Brian's HQ work, that means:
- the project file's Goal and Decisions, the experiment's Judge, and the plan page (the brief names them);
- the core principles in `~/hq/hq-policy.md` and the hard rules in `~/hq/CLAUDE.md`. Examples: TraceBot is shared by default (nothing is private, so no access-control framing), local behaves like dev, one PR per project, forward-only (no rollbacks or history rewrites);
- the repo's own `AGENTS.md` and review guidelines.

If the brief gives none of these, say so in the entry; don't guess the direction.

## Per finding, in order

1. **Prove it.** Reproduce it or prove it from the code: file:line evidence for each step of the failure, plus a failing test where practical (always for a Must about behaviour). Read the unchanged callers and readers too. Verdict: `real`, `false` (say exactly why the claim doesn't hold) or `unclear` (say what would settle it).
2. **Root cause.** Separate the cause from the symptom, then grep for **every other instance** of the same cause in the branch and list them. A finding is a class until proven otherwise.
3. **Direction check.** Does fixing it undo or contradict a recorded decision or principle, widen scope beyond the plan, or take on a named follow-up? If so, it's `push-back` whatever its tier.
4. **Disposition:** exactly one of these.
   - **fix now:** every confirmed Must, and every confirmed Should that a reviewer would block on. "Block on" means TraceBot or a teammate would request changes for this alone: a realistic failure path, a race, wrong behaviour on a path people run, a missing test for new behaviour, a doc or PR-body claim that misleads, unbounded work, or a migration or sibling conflict.
   - **list in PR body:** confirmed but minor, for example a stale comment, duplication that hasn't drifted yet, a non-blocking cleanup, or a Nit. It goes in the PR description's "Known follow-ups" with one line each, so reviewers see we know.
   - **drop:** proven false, with the one-line reason recorded. If a reviewer could make the same mistake again, record the context where reviewers will read it (bbimprove's Document step).
   - **push back:** conflicts with direction. Don't fix it. Cite the decision or principle (with a link) and draft a short, polite reply in the user's voice.
   - `unclear` findings: if it could be a Must (security, data loss, a broken consumer), dig once more by running it or writing the test. If it's still unclear, it goes to **list in PR body**, marked "unverified", and the report flags it. Otherwise list it.
5. **Fix plan** (fix now only):
   - the smallest change;
   - the files and symbols it touches;
   - its **blast radius**: the callers, readers and other writers of what it changes, deploy or build consumers, migrations, docs and claims that must change with it;
   - the test that proves it, written first;
   - what could break.

   A fix that would add a lock, a new convention or a large rewrite is a smell: say so, and prefer the narrow change. A plan you can't scope goes to the caller as a decision instead.

## Entry format

One entry per finding in the ledger:

```
F<n> [tier · persona] path:line — <finding, shortened>
  verdict: real | false | unclear — <evidence: file:line chain; test name if written>
  root cause: <one line>; other instances: <path:line, … | none>
  direction: ok | conflict — <decision/principle cited>
  disposition: fix now | list in PR body | drop | push back — <one-line reason>
  fix plan: <change> · touches <files> · blast radius <…> · test first <…> · risk <…>
```

Fixes are applied **only** from `fix now` entries with a fix plan, test-first, and each fix is checked against its plan's blast radius. Report the bucket counts: `R1: 41 findings → 9 fix now, 22 listed, 7 dropped, 3 push back`.

## Re-review rounds

A later review round's findings get investigated too. If a finding matches an earlier entry and the code at that location hasn't changed since, carry the entry forward and say so; don't re-investigate it. A finding at a line a fix touched is always investigated fresh.
