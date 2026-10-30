---
name: bb-inspect
description: Multi-persona code inspection of a specific module, page, section, or group of code (either in the current/local repo or given a GitHub repo + target like `tracevision/web-trace team page`). Resolves the target files, runs scoped mechanical checks (tests/lint/build) in parallel with focused review subagents via the Task tool (subagent_type "general") covering code/security/perf, repo rules/web-trace/tests, and docs, presents a numbered findings list, and offers to fix accepted findings. Use when the user asks to "bb-inspect" or review/audit a module, page, feature, or folder of code rather than a branch diff or PR.
---

# BB Inspect

Inspects an existing module, page, section, or group of code using the same substantive bar and personas as `bb-review`, scoped to that area of the codebase rather than a git diff.

Input examples:
- `/bb-inspect database module` (from inside the project dir)
- `/bb-inspect flex page` (from inside the project dir)
- `/bb-inspect tracevision/web-trace team page` (from outside the project dir, given `<owner>/<repo>` or repo name + module/section/page)
- `/bb-inspect src/modules/billing` (explicit path or glob)

## Phase 1: Gather & Scope (fast, read-only)

Do NOT run build/tests/lint here — those run in parallel during Phase 2.

1. **Resolve the repository**:
   - If the input specifies a GitHub repo (`<owner>/<repo>`, a GitHub URL, or a repo name when cwd is a parent workspace like `/home/bal/trace`): look for an existing local checkout under cwd and its immediate subdirectories/siblings first. If found, use that local repo path (read-only until the user accepts fixes). If not found locally, `gh repo clone <owner>/<repo>` into `/tmp/bb-skillz/<repo>`.
   - Otherwise, use the current working directory (or git root of cwd).
2. **Resolve the target scope (files in the module/page/group)**:
   - Use fast `glob` and `grep` to map the user's target description (e.g. `"database module"`, `"flex page"`, `"team page"`) to the concrete files that belong to that module/page/feature:
     - Source files (components, pages/routes, hooks, controllers, state/data layer, styles, helpers)
     - Associated test files (`*.test.*`, `*.spec.*`, `__tests__/**`)
     - Related docs (`*.md`, `docs/**`, tracked-action docs, ADRs)
   - If the target matches nothing or is genuinely ambiguous between unrelated modules, ask a brief clarifying question and stop before spawning sub-agents.
3. **Read repo rules once**:
   - Read root `AGENTS.md` / `CLAUDE.md` (and any nested ones in the target directories) so their contents can be passed inline to the sub-agents.

## Phase 2: Parallel checks & review passes

Launch **all applicable sub-agents in parallel in a single message** (multiple Task tool calls, `subagent_type: "general"`).

**No subagent tool?** Not every host exposes a subagent/Task tool. If yours does not, do the same work yourself, one persona at a time, in this order: `checks`, `code-security-perf`, `rules-and-tests`, `docs`. Never claim parallel agents ran when they did not.

Give each review agent:
- Target description (what module/page/group is being inspected)
- Repo path and the exact list of scoped target files (source, tests, and docs)
- Inline `CLAUDE.md` / `AGENTS.md` content
- Instruction: *"Inspect the scoped target files thoroughly. Only read files outside the target scope when checking callers, shared utilities, data models, or interlocking systems — do not wander into unrelated modules. Verify every claim by reading the code; do not edit anything; apply the Bar for a finding verbatim."*

Each review agent returns findings as `{file (relative to repo root), line, comment (draft, see voice), reason (1-2 lines for the user), persona}`.

**Bar for a finding** (pass verbatim to every review agent, and re-apply in Phase 3):
- **Flag**: bugs and wrong behavior; security issues; failing build/tests/lint; **bad patterns** (anti-patterns that cause real problems or will get copied: e.g. mocking internals instead of data, stale closures/missing deps, bypassing the data layer, cross-module coupling, duplicated logic that should be shared); repo-rule violations in the code; **docs that mismatch or conflict with the code** (stale docs, docs describing behavior the code no longer has, tracked-action docs that disagree with the code, or missing required docs like tracked-action plans): these are never minor, they must be updated.
- **Drop (minor)**: anything that is merely a preference or polish: naming, small readability tweaks, "could be simpler" when the current code is fine, optional refactors, minor perf, extra test cases for trivial paths, doc wording/verbosity, formatting/prettier-only changes, missing or misplaced JSDoc/comments, large-scale redesigns. Also drop:
  - **Hedged or speculative findings**: rare failure paths (a cleanup step throwing after a successful commit, double faults), "unclear whether this is intended", "may just be a nudge". Only flag something you can state as a concrete, realistic failure. If the description of the *problem* needs "might" or "unclear", drop it (being unsure about the best *fix* is fine).
  - **Missing tests for edge paths** unless that path is likely to happen and would cause real damage.
  - **Edge-case bugs**: real bugs that only show up with a misconfiguration, an unusual env/flag combination, an uncommon input format or version, or a value that would have to drift out of sync later. Being true is not enough. Flag a bug only if it hits the normal path or a case people regularly run into, or if its damage is severe (data loss, security, broken prod). Fixing an edge case adds code and risk, and often creates more issues than it solves.
  - **Duplicated constants/literals** (e.g. a default repeated in two files), even when a repo rule asks for named constants, unless the copies already disagree.

  Findings must be **substantive**: something a senior engineer on this team would genuinely want fixed in this module. If no, drop it. An empty list is a normal, good result.

### Sub-agents to launch in parallel

**1. Scoped Mechanical Checks (`checks`)**:
Run the repo's checks scoped to the target module/files where possible for speed (e.g. unit tests for the module's test files, linter on the target files/directory, typecheck/build). Install deps first only if missing. Return pass/fail for each with relevant error output. For `web-trace`, also check build/chunk warnings if a build is run.

**2. Code, Security & Performance (`code-security-perf`)** (tag each finding with persona `Code Quality`, `Security`, or `Performance`):
- **Code Quality**: does the module do what it intends; best practices; easy to follow, not spaghetti; sane data model behind components. Check how callers/consumers interact with this module and check interlocking systems (shared state, registries, events, caches, things keyed on the module's values).
- **Security**: security issues in the module (authz/authn ordering, injection, secrets, unsafe input handling, data exposure).
- **Performance**: real performance issues only (N+1 queries, unbounded renders/loops, expensive unmemoized work on hot paths, leaky listeners/timers). No micro-optimizations.

**3. Rules, Web-Trace & Tests (`rules-and-tests`)** (tag each finding with persona `Repo rules`, `Web Trace`, or `Tests`):
- **Repo rules**: check the target files against every guideline in `CLAUDE.md` / `AGENTS.md`.
- **Tests**: are the right things mocked (in UI, mocking every internal component tests nothing: mock the data instead); mocks used well (DB mocks return the correct shape, function mocks return realistic values); tests give real value; high-impact paths in the module are covered.
- **Web Trace** (ONLY when repo is `web-trace`; skip otherwise):
  - Component `FancyButton` has class `FancyButton` on its root element
  - CSS is prefixed with the component class (`.FancyButton ...`)
  - Pages use tracked actions, and there is a doc stating the tracked-action plan; verify the code's tracked actions actually match that doc
  - No cross-module linking between folders in the `modules` directory
  - No `import { x } from "trux"`; must be `from "trux/<subpackage>"` (e.g. `trux/atoms`) to avoid bloating chunks

**4. Docs (`docs`)** (tag findings with persona `Docs`):
Check every doc related to the target module/page — docs inside the module, `docs/**`, READMEs, ADRs, tracked-action plans (grep the repo's docs for the module's names/routes/components/behavior). Verify that:
- **Docs match the code**: no doc describes stale behavior, old props/APIs/flags/routes, or conflicts with what the module actually does.
- **Required docs exist and are complete**: if the repo expects docs for this module/page (e.g. tracked-action plans in `web-trace`, module READMEs), verify they exist and accurately explain how things work.

A doc that mismatches or conflicts with the code is never minor: flag it with file and line, and state what the code does now. Drop doc wording/verbosity/formatting nits.

Mechanical results (test/lint/typecheck/build failures in scope) are merged into the list as findings too.

## Phase 3: Present

Dedupe across agents, then re-apply the bar from Phase 2 and silently drop every minor finding (don't list them, don't mention how many were dropped). Keep bad patterns and doc mismatches.

Present:
1. **Scope line**: repo + target folders/file count inspected.
2. **Checks line**: scoped tests / lint / typecheck status in one line.
3. **Numbered findings list**: each item as `N. [persona] path:line - draft comment` plus a short 1-2 line reason. Put non-line findings (e.g. missing doc file or suite-wide failure) in a "general" group.

Then **stop and wait**. Ask which numbers they want fixed (or if they're good as-is).

## Phase 4: Fix (after the user replies)

The user replies with numbers to accept (e.g. `1 3 5`), `all`, or `none` / `approve`.
- If `none` / `approve`: stop.
- For accepted numbers: make the smallest change in the repo that resolves each finding (matching surrounding code style), re-run the relevant checks (tests/lint/typecheck) to verify, and report what changed.
- Do not commit or push unless explicitly asked. If the repo was cloned into `/tmp/bb-skillz/<repo>` because no local checkout existed, note the path where the fixes were applied (or offer to branch/PR if they want).

## Comment voice (important)

Draft comments use the same brief voice as `bb-review`: plain statement of the issue in as few words as it takes (often ~3-6 words, e.g. `"missing css prefix"`, `"needs useCallback here"`, `"auth check should happen before api call"`, `"tracked action missing from doc"`). No greetings, no praise, no "consider", no emoji. The 1-2 line explanation stays in the reason line below the item.
