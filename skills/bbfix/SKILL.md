---
name: bbfix
description: Fix a batch of issues - PR review comments or a free-text list - by investigating the real root cause of each, planning and applying a fix, then verifying the fix against the original complaint. Uses subagents to work the list in parallel where safe, and the main agent validates every fix and reports what was changed and how. Never commits, pushes, replies to threads or resolves them unless asked. Use when the user runs `/bbfix`, pastes a list of issues, or asks to address PR comments.
---

# BB Fix

Input is one of:

- **PR mode**: a GitHub PR URL or number (`.../pull/<n>`, `owner/repo#<n>`, or a bare number while in the repo). Fix the review comments and issue comments on it.
- **List mode**: a free-text list of issues (pasted feedback, a QA report, a bug list).

Never commit, push, post replies, or resolve threads unless the user explicitly asks.

Keep a ledger at `/tmp/bb-skillz/bbfix-ledger.md`: per issue, the original claim, verdict, root cause, files changed, and verification result.

## Phase 1: Collect

**PR mode.** Get the code locally without disturbing the user's working tree: use an existing clone, else `gh repo clone` into `/tmp/bb-skillz`; check out the PR head in a worktree, never by switching branches in the user's checkout. Then gather:

- `gh api repos/<owner>/<repo>/pulls/<n>/comments` - inline review comments (note `in_reply_to_id` and `path`/`line`)
- `gh api repos/<owner>/<repo>/issues/<n>/comments` - general PR comments
- `gh api repos/<owner>/<repo>/pulls/<n>/reviews` - review bodies, and whether each said approve/request-changes
- unresolved review threads (GraphQL `reviewThreads { isResolved }`) so already-resolved threads can be skipped

Skip bot noise, pure praise, and already-resolved threads. Also read the PR title/body: a comment may be explicitly out of scope.

**List mode.** Split the text into discrete issues. If two entries are clearly the same complaint, merge them; if an entry is too vague to act on, ask one clarifying question rather than guessing.

Number every issue (`#1`, `#2`, ...) and keep the author, link, and verbatim wording - you need the original words later for verification.

## Phase 2: Investigate each issue (parallel, read-only)

Launch one subagent per issue in parallel (multiple Task calls, `subagent_type: "general"`). If your host has no subagent tool, work through them yourself sequentially in the same order and say so.

Give each subagent: the issue verbatim and its source, the repo/worktree path, the inline `AGENTS.md` / `CLAUDE.md` rules, and this instruction:

> Work out what is actually wrong before changing anything. Reproduce or prove the claim from the code: read the file, its callers, its tests, and any interlocking system. Distinguish the root cause from the symptom. Decide whether the comment is correct - reviewers are sometimes wrong, out of date, or asking for something the code intentionally does. Change nothing. Return `{issue_id, verdict (valid | invalid | partially_valid), root_cause, evidence (path:line), plan (files and the smallest change each), test_plan, risks, scope_conflicts}`.

Merge issues that share a root cause into one fix, and say so in the report.

## Phase 3: Apply

Apply in an order that avoids collisions:

- Issues whose files are disjoint may be applied in parallel by separate subagents.
- Issues touching the same file, or the same symbol, are applied by the main agent sequentially - never let two agents edit one file at once.
- Skip issues marked `invalid` unless the user insisted; record why instead.

Each fix: the smallest change that resolves the root cause, matching surrounding style and the repo's rules. Add or adjust tests when the repo tests that behaviour, and run the relevant checks as you go.

## Phase 4: Verify each fix (fresh eyes)

For every applied fix, take the **original comment verbatim** and check the diff against it, not against your own summary. Confirm each part of the complaint is addressed, including anything the comment asked for beyond the first sentence. Also check the fix did not break the nearby contract (callers, tests, types).

Run the relevant tests / lint / typecheck, and state what you ran. Use a fresh subagent for verification when available, so the verifier is not grading its own fix.

Verdict per issue: `addressed`, `partially addressed` (say what is left), `not addressed` (say why - e.g. it needs a product decision), or `not reproducible`.

## Report

One entry per issue, matching the requested order:

1. `#N [source link or author] "<original claim, shortened>"` - verdict
   - **Root cause**: what was actually wrong (or why the comment was wrong)
   - **Fix**: files changed and what changed, one or two lines
   - **Verified**: what you checked and which commands passed

Then: issues skipped or rejected with the evidence for rejecting them, anything left partially done, and the overall build/tests/lint status. Offer the obvious next step - reply to the PR threads, resolve them, commit, or open a PR - and do none of it unasked.
