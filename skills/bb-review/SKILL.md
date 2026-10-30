---
name: bb-review
description: Multi-persona code review of a GitHub PR URL or a local folder (self-review). Given a PR URL, checks out the PR, runs mechanical checks (build/tests/lint) in parallel with focused review subagents via the Task tool (subagent_type "general") covering code/security/perf, repo rules/web-trace/tests, and docs, presents a numbered findings list, then posts the user-approved findings as brief inline comments and submits request-changes or approve. For a folder, reviews the branch's changes locally and offers to fix accepted findings. Use when the user gives a GitHub PR link or a folder path to review.
---

# BB Review

Input is one of:
- **PR mode**: a GitHub PR URL (`https://github.com/<owner>/<repo>/pull/<n>`). Parse owner, repo, number. Follow the phases below as written.
- **Folder mode** (self-review): a local directory path (a repo or worktree). Differences from PR mode:
  - No checkout or worktree: work in the folder itself, read-only until the user accepts findings.
  - The diff is everything on the current branch not in the base: `git diff $(git merge-base HEAD <default-branch>)` (default branch from `origin/HEAD`, else main/master), which includes uncommitted and staged changes; list untracked files too. If a PR exists for the branch (`gh pr view`), use its title/body as context.
  - Line numbers refer to the working-tree file.
  - Phases 1-3 otherwise identical (same checks and personas, same numbered list; draft comments are just the short issue text).
  - **Phase 4 differs: nothing is posted to GitHub.** The user replies with numbers to accept; fix those findings in the folder (smallest change that resolves each), re-run the relevant checks, and report what changed. Do not commit or push unless asked. "approve" just means no changes wanted: say the review is clean and stop.

## Phase 1: Gather (fast, read-only)

Do NOT run build/tests/lint here — those run in parallel during Phase 2.

1. `gh pr view <n> --repo <owner>/<repo> --json title,body,author,baseRefName,headRefName,headRefOid,files` and save the diff under `/tmp/bb-skillz`.
2. Get the code locally without disturbing the user's working tree: use an existing local clone of the repo if one exists (look under cwd and siblings), else `gh repo clone` into `/tmp/bb-skillz`. Create a git worktree for the PR head (`gh pr checkout` inside the worktree, or `git fetch origin pull/<n>/head`). Never switch branches in the user's main checkout.
3. Pre-annotate the diff with right-side file line numbers into `/tmp/bb-skillz/bb-diff-annotated.patch` so sub-agents never have to read whole files just to compute line numbers:
   ```bash
   awk '/^(diff |index |--- |\+\+\+ )/{in_hunk=0; print; next} /^@@ /{in_hunk=1; split($3,a,","); ln=substr(a[1],2)-1; print; next} !in_hunk{next} /^\\/{next} /^-/{print "     " $0; next} {ln++; printf "%4d %s\n", ln, $0}' <raw-diff> > /tmp/bb-skillz/bb-diff-annotated.patch
   ```
4. Read root `AGENTS.md` / `CLAUDE.md` (and any in touched directories) once so their contents can be passed inline to the sub-agents.

## Phase 2: Parallel checks & review passes

Launch **all applicable sub-agents in parallel in a single message** (multiple Task tool calls, `subagent_type: "general"`).

**No subagent tool?** Not every host exposes a subagent/Task tool. If yours does not, do the same work yourself, one persona at a time, in this order: `checks`, `code-security-perf`, `rules-and-tests`, `docs`. Never claim parallel agents ran when they did not.

Give each review agent:
- PR title/body
- Path to `/tmp/bb-skillz/bb-diff-annotated.patch` (and note that right-side line numbers are already in the left column)
- Worktree/folder path
- Inline `CLAUDE.md` / `AGENTS.md` content
- Instruction: *"Read the annotated diff first. Only read full files or grep the repo when you need surrounding context or caller verification — do not re-read untouched files unnecessarily. Verify every claim in the code; do not post anything; apply the Bar for a finding verbatim."*

Each review agent returns findings as `{file, line (RIGHT side, must be in the diff), comment (draft, see voice), reason (1-2 lines for the user, not posted), persona}`.

**Bar for a finding** (pass verbatim to every review agent, and re-apply in Phase 3):
- **Flag**: bugs and wrong behavior; security issues; failing build/tests/lint; **bad patterns** (anti-patterns that cause real problems or will get copied: e.g. mocking internals instead of data, stale closures/missing deps, bypassing the data layer, cross-module coupling, duplicated logic that should be shared); repo-rule violations in the code; **docs that mismatch or conflict with the code** (stale docs, docs describing behavior the code no longer has, tracked-action docs that disagree with the code): these are never minor, they must be updated.
- **Drop (minor)**: anything that is merely a preference or polish: naming, small readability tweaks, "could be simpler" when the current code is fine, optional refactors, minor perf, extra test cases for trivial paths, doc wording/verbosity, formatting/prettier-only changes, missing or misplaced JSDoc/comments, unrelated cleanup/scope creep. Also drop:
  - **PR title/description style** (length, narrative, structure), even if a repo doc asks for a style. Only flag the description if it is wrong about what the code does.
  - **Anything the PR already names as a follow-up / out of scope**, and design improvements beyond the PR's goal ("could also coalesce/cache/batch X"). Review what the PR set out to do.
  - **Hedged or speculative findings**: rare failure paths (a cleanup step throwing after a successful commit, double faults), "unclear whether this is intended", "may just be a nudge". Only flag something you can state as a concrete, realistic failure. If the description of the *problem* needs "might" or "unclear", drop it (being unsure about the best *fix* is fine).
  - **Missing tests for edge paths** unless that path is likely to happen and would cause real damage.
  - **Edge-case bugs**: real bugs that only show up with a misconfiguration, an unusual env/flag combination, an uncommon input format or version, or a value that would have to drift out of sync later. Being true is not enough. Flag a bug only if it hits the normal path or a case people regularly run into, or if its damage is severe (data loss, security, broken prod). Fixing an edge case adds code and risk, and often creates more issues than it solves.
  - **Duplicated constants/literals** (e.g. a default repeated in two files), even when a repo rule asks for named constants, unless the copies already disagree.

  Findings must be **substantive**: something the author would clearly want to fix before merging. Before keeping one, ask "would a senior engineer on this team block or delay the merge for this?" If no, drop it. An empty list is a normal, good result; then recommend approve.

### Sub-agents to launch in parallel

**1. Mechanical Checks (`checks`)**:
Run the repo's own scripts in the worktree/folder (package.json, Makefile, CI config): install deps if needed, then **build, tests, lint**. Return pass/fail for each with the relevant error output. For `web-trace`, also check whether build chunk sizes hit warning level.

**2. Code, Security & Performance (`code-security-perf`)** (tag each finding with persona `Code Quality`, `Security`, or `Performance`):
- **Code Quality**: does the code do what it intends; best practices; easy to follow, not spaghetti; sane data model behind components. If a function/API changes, grep its callers/users and judge the impact. Check interlocking systems (shared state, registries, events, caches, things keyed on the changed values).
- **Security**: does the PR introduce security issues (authz/authn ordering, injection, secrets, unsafe input handling, data exposure).
- **Performance**: real improvements only. Should the touched files have been made faster? Is new code worse than it should be? No micro-optimizations.

**3. Rules, Web-Trace & Tests (`rules-and-tests`)** (tag each finding with persona `Repo rules`, `Web Trace`, or `Tests`):
- **Repo rules**: check the diff against every guideline in `CLAUDE.md` / `AGENTS.md`.
- **Tests**: are the right things mocked (in UI, mocking every internal component tests nothing: mock the data instead); mocks used well (DB mocks return the correct shape, function mocks return realistic values); tests give real value; coverage complete for high-impact paths.
- **Web Trace** (ONLY when repo is `web-trace`; skip otherwise):
  - New component `FancyButton` has class `FancyButton` on its root element
  - CSS is prefixed with the component class (`.FancyButton ...`)
  - New pages/updates use tracked actions, and there is a doc stating the tracked-action plan; verify the code's tracked actions actually match that doc
  - No cross-module linking between folders in the `modules` directory
  - No `import { x } from "trux"`; must be `from "trux/<subpackage>"` (e.g. `trux/atoms`) to avoid bloating chunks

**4. Docs (`docs`)** (tag findings with persona `Docs`; skip launching this agent ONLY if the diff is purely internal test/style/refactor with no touched docs and no renamed/changed symbols, APIs, config, flags, or user-visible behavior):
Check every doc related to the change — the ones the PR touches (`*.md`, `docs/**`, README, CHANGELOG, ADRs) and the ones that describe the changed code (grep the repo's docs for changed names/behavior). Verify that:
- **New docs are correct**: anything added matches what the code actually does, and is placed where the repo expects docs.
- **Stale docs are updated**: no doc still describes behavior the code no longer has, and no doc is missing an update the change requires (renamed things, moved files, changed APIs, changed config/flags, changed setup steps).
- **Docs describe how things work**: the docs are accurate and complete enough to explain the behavior they cover, not just a restatement of the code.

A doc that mismatches or conflicts with the code is never minor: flag it and name the file and the line, and say what the code does now. Same for a change that clearly needs a doc update the PR skipped. Drop doc wording/verbosity/formatting nits (see the bar).

Mechanical results (build/test/lint/chunk-size failures) are merged into the list as findings too.

## Phase 3: Present

Dedupe across agents, then re-apply the bar from Phase 2 and silently drop every minor finding (don't list them, don't mention how many were dropped). Keep bad patterns and doc mismatches. Then show a single numbered list. Each item: `N. [persona] path:line - draft comment` plus a short reason line. Put findings with no diff line (e.g. build failure) in a separate "general" group; those go in the review body. Also state build/tests/lint status in one line. Then **stop and wait**. Do not post anything yet.

## Phase 4: Post (after the user replies)

The user replies with numbers to accept (e.g. "1 3 5") and/or "approve". They may also edit comment wording; use their wording.

- Accepted numbers, no "approve": submit **REQUEST_CHANGES** with those comments.
- "approve" and no accepted numbers: submit **APPROVE**.
- Both given: ask which they want before posting.
- No numbers and no approve: ask; don't post.

Post as ONE review via the API with inline comments, anchored to `commit_id` = the PR headRefOid:

```
gh api repos/<owner>/<repo>/pulls/<n>/reviews --input review.json
```
with `{"commit_id": "...", "event": "REQUEST_CHANGES|APPROVE", "body": "", "comments": [{"path": "...", "line": N, "side": "RIGHT", "body": "..."}]}`. General (non-line) findings go in `body`. If a line isn't in the diff the API rejects it; re-anchor to the nearest diff line. If the user is the PR author, GitHub blocks approve/request-changes: fall back to event `COMMENT` and say so.

After posting, give the review URL and remove the PR worktree: `git -C <main clone> worktree remove --force <worktree path>`, then `git worktree prune`. If the clone was made into /tmp/bb-skillz just for this review, delete that too. Also delete any local branch `gh pr checkout` created for the PR. Folder mode has no worktree, so skip this. Stop there.

## Comment voice (important)

Posted comments are in the user's voice: super brief, plain statement of the issue, as few words as it takes (often ~3). Examples: "missing css prefix", "needs useCallback here", "auth check should happen before api call", "improve this code section". No greetings, no praise, no explanations, no "consider", no emoji, no signature or attribution lines. The longer reasoning stays in the chat list only.
