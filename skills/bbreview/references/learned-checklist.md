# Learned checklist

Reviewer instructions taken from findings our pre-PR review missed and a PR reviewer then caught. Every pre-PR reviewer works through the General section and the section for its repo. `bbfix` adds a line when a PR finding shows a new kind of miss. Rules for this file: one line per item, cite the PR numbers, and no duplicates.

Seeded 2026-11-17 from 278 findings on 50 TraceBot PRs (HQ `projects/pr-first-pass-green/findings.md`).

Miss classes (`bbfix` tags each issue with one): outside-diff · repo rule · migration/sibling · docs claim · test gap · failure path/race · fix regression · security · correctness · preference.

## General (any repo)

1. **Consumers.** For every changed helper, status value, error type, default, build stage or target, grep all callers and consumers: scripts, deploy steps, CI, other routes, mobile/web clients, sweeps. Confirm each one still works. (TraceBot #236, #214, #150, #109, #152, #217, #221)
2. **Hidden writes.** Treat "read" functions as suspect: check whether one also writes (stamps, counters, caches). (#109, #152)
3. **Removed guards.** When a lock, guard or check is removed, audit every path it used to protect. (#196/#202)
4. **Fix residue.** After every fix, grep docs, comments, module headers, test counts and PR-body claims for the old behaviour. (#91, #109, #125, #154, #173, #216, #235)
5. **Tests that can fail.** A test must exercise the production query or seam, not a rebuilt copy or an unchanged helper. Ask: would this test fail if the change were reverted? (#91, #124, #215, #216)
6. **Reuse.** Reuse existing production helpers instead of re-implementing them. Search for one before accepting new code that orders, parses, extracts or ends something. (#203, #209, #212, #213, #215)
7. **Bounded work.** A `LIMIT N` over candidates that can be skipped needs a persistent cursor, or it starves. Any scan of history needs a bound per pass. (#209/#217, #215, #216, #219, #231)
8. **Fences.** A liveness or state check made before a write is not a fence: re-check it inside the conditional write. A CAS miss must not return success. A retry that reloads a snapshot keeps its status guard. (#170, #215, #216, #226)
9. **Clocks.** Never fence or compare-and-swap on a timestamp with one-second resolution; use a revision that changes on every write. (#196, #215, #219, #226)
10. **Redaction.** Blanking a field must not open a legacy path (an empty password matching a plaintext check). Cover base64 bodies, nested and stringified JSON, and columns the read layer hides. (#212, #220, #236)
11. **Re-run claims.** Re-run every number and command the PR body or docs claim. A claim that hasn't been run is a finding. (#220, #236)
12. **Siblings.** Check the open PRs and the recently merged PRs that touch the same paths. Run `git merge-tree` against each one. (#89, #197, #200, #225)

## tracevision/TraceBot

1. **Migrations.** Compare migration numbers against `origin/main` **and** every open PR. After merging main, regenerate the `brain_read` views (`BRAIN_READ_BLESS=1 cargo test -p brain-db --lib brain_read::`). Never rename a migration that has already been applied on dev. (#151, #152, #197, #200, #212, #216, #226, #235)
2. **Wiki seeds.** For any `db/seeds/wiki` change, check `db/seeds/manifest.json` and whether the live page has been edited. If it has, the PR needs a live-paste step: `forceRefresh` alone won't land it. (#106, #124, #125, #131, #176, #177, #210, #217, #218)
3. **Behaviour changes.** A prompt or behaviour change needs the AGENTS.md declared-sample A/B, with its result in the PR, or ships behind a flag that stays off until the A/B is done. New production SQL needs one run on dev before the PR. (#124, #125, #160, #172, #176, #193, #222)
4. **Plan docs.** A plan doc has the why, goals and acceptance criteria, a keep/revert threshold, an ERD for new tables, and decisions with their reasons. An execution log is not a plan. (#91, #112, #141, #152)
5. **No locks.** The write path takes no locks (REVIEW_GUIDELINES rule 4). Check that **review fixes** don't add one either. (#217)
6. **Build stages.** A Dockerfile stage change must keep `production` as the last stage, because `scripts/deploy-steps/publish.sh` builds without `--target`. (#236)
7. **Docs in the same commit.** `.env.sample`, `docs/deploying.md`, `docs/architecture.md` and the module headers are updated in the same commit as the code they describe. (#152, #235)
