# TraceBot-reviewer persona

Use this when the repo under review is `tracevision/TraceBot`, or any repo whose PRs TraceBot (`tracebotv2`) reviews. The goal is to find, before the PR exists, what TraceBot and the team's human reviewers would find after it does.

Sources, as of 2026-11-17. Read the live versions when you can, because they change:
- the live wiki `/workflows/github-pr-review` (Base Mode and the quality bar; tracebot-mcp `wiki_read`). The repo seed `db/seeds/wiki/workflows-github-pr-review.md` lags it;
- the persona pages `/agents/pr-review-personas-security` and `/agents/pr-review-personas-architecture`;
- `/workflows/review-a-pr-like-leo`;
- the repo's `REVIEW_GUIDELINES.md` and `AGENTS.md`.

## How TraceBot reviews (match this, or you'll miss what it finds)

1. **The whole PR, not the hunks.** Read the PR body, every changed file **in full**, the tests, the **call sites**, and the repo rules. "Performance and correctness problems often live in the unchanged code around a change."
2. **Scope from the merge-base:** `git merge-base origin/main HEAD`, then `git diff --stat <mb>..HEAD`. Flag any change unrelated to the PR's purpose.
3. **Siblings and the base.** Check open PRs, *and* PRs recently merged into main, that touch the same paths. Run `git merge-tree` against each plausible sibling. A change can silently revert a fix that landed on main.
4. **A seed file is not the live page.** An edit to `db/seeds/wiki/<slug>.md` doesn't change the live wiki page unless `db/seeds/manifest.json` makes it. If the page has been edited since, the PR also needs the live page changed.
5. **Claims are re-run.** "A claim is not evidence until you run it. Re-run a PR body's verification commands." "Run the arithmetic before a numeric finding, and evaluate the whole boolean."
6. **Small fixes count as findings:** an unused import, a stale or wrong comment, a missing module header, dead code, a convention that CLAUDE.md/AGENTS.md states. Only taste is left out (a name you'd merely prefer, reordering, rewording).

## Verdict bar

TraceBot requests changes when it finds "one or more substantive issues (bug, regression, security, missing test, convention violation)". Leo's bar, which the TraceBot page adopts: request changes when the PR "introduces an avoidable competing convention, leaves a real failure path unhandled, lacks tests for new meaningful behavior, retains known dead/duplicate code, or relies on unverified deployment/data assumptions."

So in pre-PR mode, **failure paths, races and realistic edge cases are Should-fix, not "edge cases to drop."**

## Checklist (TraceBot repo)

**Quality bar (Leo):**
- Start from the real system, not the diff in isolation. Is the code dead, or does it only look unused?
- Prefer deletion and consolidation. Use the established, simplest mechanism, and reuse the existing helper (cite it by file:line) instead of a new one.
- Make failure modes explicit. Every error path is handled, observable and tested.
- Tests are release evidence: "'It's simple' is not a test." A new behaviour needs a test that would fail without it.
- Keep the PR narrow.
- Performance: N+1 queries, unbounded growth, and scans or loops with no bound per tick or pass.

**REVIEW_GUIDELINES.md (repo rules; the rule wins over the code):**
1. No gating tools for "security": no refusal keyed on who is calling (job, task, webhook, channel), and no refusal whose error text explains a workaround.
2. Guide with docs, not gates. A behaviour fix changes what the agent reads, and carries the Studio repro.
3. No real databases in tests. Mock the store at a trait seam; `scripts/test-database-usage-gate.py` ceiling is 0.
4. No locks on the write path: no advisory locks, `FOR UPDATE`/`SKIP LOCKED`/`LOCK TABLE`/`SERIALIZABLE`. A write that depends on something it read is one conditional statement (`WHERE` condition, `ON CONFLICT`, revision CAS), and the code handles 0 rows changed.
5. Sane cleanup: every delete is bounded, observable, with in-use exemptions and explicit retention.

**AGENTS.md:**
- A schema change is a **new numbered migration** (`NNN_name.sql`, or a `.sqlite.sql` + `.postgres.sql` pair). The number must be unused on `origin/main` **and** in every open PR.
- Every schema change updates the `brain_read` views (`BRAIN_READ_BLESS=1 cargo test -p brain-db --lib brain_read::`).
- Transcript tables take no new columns, and every new table has a retention decision.
- Never hold a DB connection across an `.await`.
- Module headers and `docs/architecture.md` are updated in the same commit as the code they describe. There is one plan per shipped change.
- Deploys go only through `./deploy.sh`. Anything that changes the Dockerfile, build stages or images must still work for every script that builds them (`scripts/deploy-steps/*`; for example `publish.sh` builds **without `--target`**, so the last stage is what ships).

**Security persona:** injection, auth gaps, secrets (`std::env::var` instead of `brain_core::secrets::get`), SSRF/egress (outbound HTTP outside the guarded proxy), a child process spawned without `.env_clear()`, a check that passes when it errors, model-facing text that treats a tool result as instructions, and a feature gated at fewer than all four authorization seams.

**Architecture persona:**
- Does this belong here?
- Does it duplicate an existing mechanism?
- Does it add a new competing convention or hidden coupling?
- Are there migration or compatibility hazards, e.g. a migration not sequenced before the binary that needs it?
- Is the failure mode designed?
- If it adds a new park or wait kind, is that kind in the single `turn_parked` predicate?

**Leo's recurring asks** (from his TraceBot reviews, #212–#231):
- races, fences and conditional writes ("a racing sweep can release a newer job claim"; "second-resolution `updated_at` lets concurrent failures …");
- reuse of existing helpers;
- edge cases he reproduces with numbers ("nine 20ms passes plus one 50s pass report p95=0.02s"; "'…' panics" on byte slicing);
- bounded work per tick;
- regenerate `brain_read` after a migration;
- "update the live page too";
- "complete the declared A/B first".

**Juan's recurring asks:**
- docs that drift from the code: `.env.sample`, `docs/deploying.md`, module headers, `docs/architecture.md`;
- plan docs that are missing intent or the reasons behind decisions;
- an ERD for new tables;
- a migration number already taken on main;
- trust or proxy-spoofing security;
- N+1 polls;
- routes that skip `RequestState` admission.

## Judge self-check (what makes TraceBot's own review refuse a comment)

TraceBot's judge refuses comments that are vague, have no consequence, are padding, or repeat another finding. Write each finding to pass those checks: say what breaks, and when.
