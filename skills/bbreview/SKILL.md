---
name: bbreview
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
- **Pre-PR mode**: folder mode run on our own branch before it becomes a PR (bbimprove always uses it, or the user says "pre-PR"). The goal is that the PR's reviewers find nothing. It differs from folder mode in three ways:
  - **Every finding is reported.** Use the pre-PR bar below. Nothing is dropped silently.
  - **Reviewers read past the diff.** They read every touched file in full and the callers of what changed, and the `blast-radius` persona runs.
  - **Rules are loaded.** Reviewers get the learned checklist and, for a repo TraceBot reviews, the TraceBot-reviewer persona (Phase 1 step 4).

## Phase 1: Gather (fast, read-only)

Do NOT run build/tests/lint here — those run in parallel during Phase 2.

1. `gh pr view <n> --repo <owner>/<repo> --json title,body,author,baseRefName,headRefName,headRefOid,files` and save the diff under `/tmp/bb-skillz`.
2. Get the code locally without disturbing the user's working tree: use an existing local clone of the repo if one exists (look under cwd and siblings), else `gh repo clone` into `/tmp/bb-skillz`. Create a git worktree for the PR head (`gh pr checkout` inside the worktree, or `git fetch origin pull/<n>/head`). Never switch branches in the user's main checkout.
3. Pre-annotate the diff with right-side file line numbers into `/tmp/bb-skillz/bb-diff-annotated.patch` so sub-agents never have to read whole files just to compute line numbers:
   ```bash
   awk '/^@@ /{split($2,o,","); split($3,n,","); ol=(2 in o)?o[2]:1; nl=(2 in n)?n[2]:1; ln=substr(n[1],2)-1; print; next} /^\\/{next} ol>0||nl>0{if(/^-/){ol--; print "     " $0; next} if(/^\+/)nl--; else {ol--; nl--} ln++; printf "%4d %s\n", ln, $0; next} /^(diff |index |--- |\+\+\+ )/{print}' <raw-diff> > /tmp/bb-skillz/bb-diff-annotated.patch
   ```
   The hunk body is bounded by the line counts in its `@@ -a,b +c,d @@` header, not by spotting the next `--- `/`+++ ` line, so a removed `-- comment` (`--- comment`) or added `++x` (`+++x`) never ends the hunk early. If you change this command, run `tests/annotate-diff.test.sh` in this skill's directory.
4. Read root `AGENTS.md` / `CLAUDE.md` (and any in touched directories) once so their contents can be passed inline to the sub-agents. Also read the repo's `REVIEW_GUIDELINES.md` if it has one. In pre-PR mode, also pass inline:
   - `references/learned-checklist.md`: the general section, plus the section for this repo;
   - `references/tracebot-reviewer.md`, when the repo is `tracevision/TraceBot` or TraceBot reviews its PRs.

## Phase 2: Parallel checks & review passes

Launch **all applicable sub-agents in parallel in a single message** (multiple Task tool calls, `subagent_type: "general"`).

**No subagent tool?** Not every host exposes a subagent/Task tool. If yours does not, do the same work yourself, one persona at a time, in this order: `checks`, `code-security-perf`, `rules-and-tests`, `blast-radius` (when it applies), `docs`. Never claim parallel agents ran when they did not.

Give each review agent:
- PR title/body
- Path to `/tmp/bb-skillz/bb-diff-annotated.patch` (and note that right-side line numbers are already in the left column)
- Worktree/folder path
- Inline `CLAUDE.md` / `AGENTS.md` content
- Instruction: *"Read the annotated diff first. Only read full files or grep the repo when you need surrounding context or caller verification — do not re-read untouched files unnecessarily. Verify every claim in the code; do not post anything; apply the Bar for a finding verbatim."*
- **Pre-PR mode** uses this instruction instead: *"Read the annotated diff, then read every touched file in full and grep for the callers and consumers of everything the diff changes. Bugs our reviewers found were mostly in the unchanged code around a hunk, or in a caller. Work through the learned checklist and the repo persona item by item. Verify every claim in the code, and do not post anything. Apply the pre-PR bar verbatim and return every finding with its tier. A finding is a class: when you find one (an unfenced read-then-write, a `LIMIT` that can starve, an unhandled status), find every other instance in the change and report each one. Starvation and unbounded work are Should, never Nit. The worktree is read-only: never check out, switch, stash or reset; read other revisions with `git show <rev>:<path>`. Return findings as your reply; don't write report files."*
- Reviewers judge the code cold. Never give them the coding session, the plan's reasoning, or earlier rounds' ledgers.

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

**Pre-PR bar** (replaces the bar above in pre-PR mode; pass it verbatim). The question is no longer "would I block someone else's PR for this?" It is "**would this PR's reviewer (TraceBot or a teammate) comment on it?**" Report every finding, each with a tier:
- **Must**: bugs, security, failing checks, repo-rule violations, docs or PR-body claims that contradict the code, and broken consumers outside the diff.
- **Should**: realistic failure paths, races, and edge cases on paths people run. Also: missing tests for new behaviour, an existing helper or convention not reused, a stale comment or missing module header, dead code, unbounded work, a migration or sibling-PR conflict, and a wiki seed changed without the live page. Our PR reviewers flag all of these.
- **Nit**: pure taste (a name you'd merely prefer, reordering, rewording that says the same thing). List these too, but they never block.

Drop nothing silently. Hedged findings stay in, marked `unsure` with what would settle them; the fixer settles them by reading or running the code. The coordinator, not the reviewer, decides what to fix.

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

**4. Blast radius (`blast-radius`)** (pre-PR mode always; in other modes when the diff touches build, deploy, CI, schema, config or a public API. Tag findings with persona `Blast radius`). The other personas review what changed; this one reviews **who depends on what changed**:
- **Consumers:** for each changed function, type, route, tool, config key, env var, file path, CLI flag, Dockerfile stage or build target, grep the whole repo for its users. That includes `scripts/`, deploy steps, CI workflows, Makefiles, Dockerfiles, tests, docs and seeds. Check that each user still works. Example: adding a final Dockerfile stage changes what a `docker build` without `--target` ships (TraceBot #236, `scripts/deploy-steps/publish.sh`).
- **Readers of what the diff writes:** for each new status value, sentinel or blanked value (`""`, `0`, `NULL`, a placeholder) and each new row kind, grep every reader of that column or type, changed or not: outcome mappers, filters, sweeps, repair queries, auth and login checks. Check what each one does with the new value. A reader that sends it down an old branch (a blank or zero value taking a fallback or legacy path, a new status falling into an `else` that means something else) is a Must.
- **Other writers of the same rows:** for each row or state the diff writes, list every other path that writes it: kickoff, finish, retry, reconcile, edit, stop, sweep, boot recovery. For each pair, ask what happens when they interleave (one commits between the other's read and write, or one fails half-way). Each write must be fenced on the state the other changes. Name the interleaving in the finding.
- **Schema:** migration numbers must be unused on `origin/main` (`git fetch` first) and in every open PR (`gh pr list --state open --json number,files`). Regenerated artifacts (views, snapshots, bundles) must be updated.
- **Siblings:** open PRs, and PRs merged into main since the merge-base, that touch the same paths. Run `git merge-tree` against each one. Flag conflicts and semantic overlaps.
- **Live state the diff can't show:** a wiki seed or config whose live copy needs the same change, or env vars that must be set in every deploy target.
Before the findings, put two short tables in your reply so the coverage can be checked: **readers** (new value or status → each reader → what it does with it) and **writer pairs** (writer A, writer B, the interleaving, fenced or not). A pair you didn't check is a gap, not a pass.
Return each finding at the nearest diff line, or as General when no diff line fits.

**5. Docs (`docs`)** (tag findings with persona `Docs`; skip launching this agent ONLY if the diff is purely internal test/style/refactor with no touched docs and no renamed/changed symbols, APIs, config, flags, or user-visible behavior):
Check every doc related to the change — the ones the PR touches (`*.md`, `docs/**`, README, CHANGELOG, ADRs) and the ones that describe the changed code (grep the repo's docs for changed names/behavior). Verify that:
- **New docs are correct**: anything added matches what the code actually does, and is placed where the repo expects docs.
- **Stale docs are updated**: no doc still describes behavior the code no longer has, and no doc is missing an update the change requires (renamed things, moved files, changed APIs, changed config/flags, changed setup steps).
- **Docs describe how things work**: the docs are accurate and complete enough to explain the behavior they cover, not just a restatement of the code.

- **Safety claims are enforced** (pre-PR mode): list every claim the change adds, in docs, code comments, module headers or the PR body, that something cannot, never or only happens ("a revoked key is refused", "runs at most once", "only admins see it"). For each, find the code that enforces it and trace it end to end, including the unchanged code that reads the value (auth checks, dispatch, filters, outcome mappers). An unenforced claim is a Must: either the code is wrong or the claim is.

A doc that mismatches or conflicts with the code is never minor: flag it and name the file and the line, and say what the code does now. Same for a change that clearly needs a doc update the PR skipped. Drop doc wording/verbosity/formatting nits (see the bar).

Mechanical results (build/test/lint/chunk-size failures) are merged into the list as findings too.

## Phase 3: Present

Dedupe across agents, then re-apply the bar from Phase 2 and silently drop every minor finding (don't list them, don't mention how many were dropped). Keep bad patterns and doc mismatches.

**Pre-PR mode is different: never drop anything.** List Must, then Should, then a **Nits** group, and show the counts per tier. Each item gets its tier in the persona slot (`[Should · Tests]`). Dedupe only true duplicates.

Then show a single numbered list, in this shape:

```
1. [Code Quality] https://github.com/<owner>/<repo>/pull/<n>/changes#diff-<anchor>R<line>
   "<preview: the short posted comment text>"

   <long description: what is wrong, when it bites, the evidence, and the
   smallest fix. 2-5 sentences. Written to the user, never posted.>

---
2. [Security] ...
```

Rules for the list:

- `[persona]` is the finding's persona: `Code Quality`, `Security`, `Performance`, `Repo rules`, `Web Trace`, `Tests`, `Blast radius`, `Docs`, `Build`.
- The link points at the exact changed line. `<anchor>` is the SHA-256 of the repo-relative path exactly as it appears in the PR's file list (no leading `./`):
  ```bash
  printf '%s' "path/to/file.ts" | sha256sum | cut -d' ' -f1   # macOS: shasum -a 256
  ```
  giving `.../pull/<n>/changes#diff-<anchor>R<line>` (right-side line number). Only link paths that are actually in the diff.
- Put a `---` between items, with a blank line either side.
- Findings with no diff line (build/lint failure, missing file, suite-wide problem) go in a separate **General** group below the list, with no link.
- **Folder mode** has no PR: use `path:line` in place of the link.
- Close with one line stating build / tests / lint status.

Then **stop and wait**. Do not post anything yet.

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

The response carries the review `id`. Fetch the comments it created and upgrade each accepted finding to its permanent link:

```bash
gh api repos/<owner>/<repo>/pulls/<n>/reviews/<review_id>/comments \
  --jq '.[] | {path, line, id, body}'
```

Match on `path` + `line`, then print the accepted findings again in the Phase 3 shape, with `https://github.com/<owner>/<repo>/pull/<n>/changes#r<id>` in place of the diff anchor - the same link GitHub's "Copy link" gives. Rejected findings are not in the review and get no link.

After posting, give the review URL and remove the PR worktree: `git -C <main clone> worktree remove --force <worktree path>`, then `git worktree prune`. If the clone was made into /tmp/bb-skillz just for this review, delete that too. Also delete any local branch `gh pr checkout` created for the PR. Folder mode has no worktree, so skip this. Stop there.

## Comment voice (important)

Posted comments are in the user's voice: super brief, plain statement of the issue, as few words as it takes (often ~3). Examples: "missing css prefix", "needs useCallback here", "auth check should happen before api call", "improve this code section". No greetings, no praise, no explanations, no "consider", no emoji, no signature or attribution lines. The longer reasoning stays in the chat list only.
