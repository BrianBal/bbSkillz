---
name: tracebot-sweep
description: HQ's improvement loop for TraceBot (Brain). Triages recent prod Slack conversations, picks the worst failure patterns, sends one agent per pattern to reproduce and fix it in Studio (retrying with new hypotheses when a fix fails), verifies what comes back, and lands verified fixes as a local branch, a draft PR when Brian has asked, or a proposed wiki change. Use when Brian says "sweep tracebot", "run the bot army", "find and fix bad TraceBot conversations", or when a scheduled loop fires this skill. Runs from HQ (~/hq) and only orchestrates. The method lives in the TraceBot repo's conversation-triage and context-investigation skills.
---

# TraceBot sweep

You are HQ, the coordinator. This skill is the loop. The method lives in the repo:

- `~/trace/TraceBot/.claude/skills/conversation-triage/`: find bad conversations and group them into patterns.
- `~/trace/TraceBot/.claude/skills/context-investigation/`: reproduce one pattern in Studio, test hypotheses one fork at a time, and land the fix.

Until branch `feat/conversation-improvement-loop` is merged, both skills live in the worktree `~/trace/wt/TraceBot-feat-conversation-loop/.claude/skills/`. Read them there, and have investigator worktrees branch from that branch instead of `origin/main`. Read both SKILL.md files before the first run in a session. If they disagree with this file, they win on method and this file wins on orchestration and limits.

State lives in `~/hq/projects/tracebot.md`: section **Bot-army improvement loop**, plus a dated **Sweep** entry under Log for each run.

## Hard limits

- **STOP (updated 2026-11-05): no Studio replays against prod from a laptop yet.** PR #112 (merged 2026-11-05) fixed fork creation and tool decisions: they now hold the lock for round trips, not rows. But the Studio worker's own per-step turn writes still hold prod's install-wide write lock for up to ~3 s over a laptop link. Remove this line when the global-lock removal (fix/lockfree) ships, or when the worker runs inside AWS next to the database.

- **Prod is read-only for every agent.** Use tb2db for reads. In Studio, any call that writes or sends gets `respond`ed, never called: Slack, wiki writes, jobs, HubSpot, `worker_*`, `qa_*`, GitHub.
- **No prod wiki writes.** Wiki fixes land as a seed-file branch or as a proposed body for Brian.
- **Code stops at a local commit on a feature branch.** Open a draft PR only when Brian has said so for this run (for example "sweep and open PRs"). Never push to main, merge or deploy.
- **One investigation in Studio at a time.** Studio forks share the prod advisory lock (at most 2 forks at once), and each Studio worker runs one checkout. Triage can be parallel; investigations run one after another.
- **Budget per run:** at most 3 patterns investigated, at most 2 attempts per pattern. One attempt is a single context-investigation run, which already caps itself at 6 forks without progress and twice that in total. Stop early and report if Studio or AWS auth breaks.

## Prerequisites (check, don't fix)

1. tb2db works: `mcp__tb2db__tb2_run_query` with env `prod` and `SELECT 1`. On an SSO error, ask Brian to run `aws sso login --sso-session default`, then reconnect tb2db with `/mcp`.
2. Studio can run: `AWS_PROFILE=code DATABASE_SECRET=prod/db/tracebot-db/tracebot scripts/start-studio.sh prod` from the worktree the investigator will use. If the build fails to link libpq, record that in the report and stop.
3. Is a previous sweep still open? Read the loop section in the project file and don't re-investigate a pattern that is already open. Group patterns by title and class, not by conversation id.

## The loop

### 1. Triage

Give conversation-triage to one `general-purpose` agent (tb2db needs MCP access, which `researcher` lacks). Brief:

- window (default: since the last sweep, else 2 days);
- output paths: `~/hq/projects/tracebot-sweeps/<date>/triage.json` and `triage.md`;
- split into chunks of about 60 conversations across parallel sub-agents and merge;
- quote real text only.

When it returns, spot-check 3 or 4 evidence quotes yourself with tb2db before trusting the list.

### 2. Pick patterns

`triage.json` follows `conversation-triage/v1`. `patterns[]` is already ranked by `score`, which is computed from `total_conversations` (the full count, not the up to 8 listed). Each pattern has `id`, `title`, `class`, `layer`, `severity`, `conversations[]` (representative first), `representative_id` and `suggested_test_goal`. Within that ranking, prefer:

1. `layer: context`: wiki, routing, procedure. Studio can prove these.
2. `layer: code` with a clear seam, such as tool description or response text.
3. `layer: infra` (markup leaking into replies, MCP 500s). Don't investigate these in Studio. Write them up as tasks for Brian or a dedicated implementer, with the conversation ids as evidence.

Skip patterns with `total_conversations` < 3 unless their severity is `high`. Patterns from the scope filters' `counts.filtered` are out of scope by design: don't pick them. Silences right after a Brain message (`slack_response_decisions` silent, `harness_bug` / `code`) are code issues, never Studio work.

Take at most 3. Record each under the loop section as `- [ ] <pattern id> <title> (<class>, <n> convs) — investigating`.

### 3. Investigate (one pattern at a time)

Dispatch an `implementer` agent with `isolation: "worktree"` (or brief it to create `~/trace/wt/TraceBot-fix-<pattern-slug>` off `origin/main`). Give it:

- the pattern object from `triage.json` (representative, set, suggested test goal);
- the instruction to run context-investigation "from an orchestrator", with its fork budget, and to return the machine-readable result block;
- the hard limits above, verbatim;
- definition of done: a result block, plus either a local commit on `fix/<pattern-slug>`, a proposed wiki body file, or a clear negative result;
- "append your result to ~/hq/projects/tracebot.md under Log".

### 4. Judge the result

The report ends with one fenced `json` block, `context-investigation/result/v1`. Its fields: `status`, `test_goal`, `samples_passed`/`samples_total`, `baseline_passed`/`baseline_total`, `set_results[]`, `forks_used`, `change`, `branch`, `commit` and `proposed_wiki[]` (with `seeded` and `prod_state`). Parse it, then **verify before believing it**:

- **`fixed`:** needs at least 3 passing samples, a baseline rerun that still fails, and the other conversations in the set passing. Read the diff or the proposed page. Reject fixes that name the conversation's specifics (overfit). If the code changed, rerun the repo's test gates for the touched crates yourself.
- **`narrow`, or a fail with a new reason:** retry once. Brief a fresh agent with the first attempt's notes, the forks already tried, and what they ruled out.
- **`negative` after 2 attempts:** mark the pattern `needs-brian` with the evidence.
- **`code_cause` or `harness_bug`:** if `branch` is set, review it like a code fix. Otherwise write it up as an implementer task. Infra also comes back as `code_cause`, with `notes` saying so. Don't keep forking.
- **`blocked`:** report the blocker to Brian. Don't retry until it's cleared.

### 5. Land

- **Code:** the branch stays local. If Brian asked for PRs this run, open a **draft** PR with `gh pr create --draft`. The body carries the test goal, fork evidence (samples passed out of total, the baseline, the set) and the conversation ids, and ends with the attribution line.
- **Wiki change:** follow `proposed_wiki[].prod_state`:
  - `untouched` or `agent_edited`: the seed-file change on the branch lands it (the agent adds `forceRefresh` for `agent_edited`).
  - `person_edited`, `not_seeded` or `absent`: copy `body_path` into the sweep folder and list it for Brian to apply.

### 6. Report

Update the loop section (one line per pattern: status, branch or PR, next action). Add a **Sweep <date>** log entry. Update `projects.md` Next. Then give Brian a short chat summary covering:

- conversations swept;
- good and bad counts;
- the patterns found;
- what got fixed, with evidence;
- what is blocked on him.

## Scheduling

Run it on demand, or have Brian set up a loop (`/loop 24h /tracebot-sweep`) or a scheduled routine. Each firing is one full run under the budget above. A run that finds nothing new above the noise floor reports that in one line and stops.
