---
name: bbdoc
description: Self-healing documentation audit loop. Finds all documentation and specs touched or affected by the current branch/PR (or a given folder/topic), spawns parallel subagents via the Task tool (subagent_type "general") to audit each doc line-by-line against the actual codebase for untrue, misleading, or out-of-date information, updates the docs (and regenerates any derived OpenAPI/schema bundles), and repeats up to 5 passes until zero findings remain. Use when the user invokes `/bbdoc`, says "bbdoc", or asks to audit and fix affected docs until clean.
---

# BB Doc

Audits and updates every documentation file and API spec touched or affected by the current branch (or a user-specified folder/module), running up to 5 passes with parallel subagents until no untrue, misleading, or out-of-date statements remain.

Input: optional path, module, or topic. Defaults to the current branch's changes against the base branch (`origin/HEAD`, else `origin/master` or `origin/main`) in the current working directory.

Keep a ledger at `/tmp/bb-skillz/bbdoc-ledger.md`: per pass, each finding (`path:line - issue`), the action taken (`updated` / `deferred`), and the file(s) changed.

## Phase 1: Find Affected Docs

1. **Changed docs & specs in the branch diff**:
   - `MB=$(git merge-base HEAD <default-branch>)`
   - Collect all modified/added `*.md`, `docs/**`, `README*`, `CLAUDE.md`, `AGENTS.md`, OpenAPI specs (`*.yaml`, `*.yml`), and GraphQL schemas (`*.gql`, `*.graphql`) in `git diff $MB --name-only` (including uncommitted and untracked files).
2. **Untouched docs affected by the code changes**:
   - Identify the modules, services, routes, exports, env vars, scripts, and config keys added, renamed, moved, or modified in `git diff $MB --name-only`.
   - Use `grep` / `glob` across the repository's `*.md` and `docs/**` files for references to those changed modules, routes, functions, paths, or behaviors so stale untouched docs are included in the scope.
3. **Group into review batches**:
   - Partition the affected docs into logical batches (typically 2-5 parallel subagents, e.g.: service README & root docs, reference/contract docs, OpenAPI/schema specs, plan/design docs) so each subagent has a focused set of files to verify deeply.

## Phase 2: Audit & Update Loop (max 5 passes)

Repeat up to 5 passes:

1. **Parallel Subagent Audit (Cold)**:
   - Launch all batch subagents **in parallel in a single message** via the `Task` tool (`subagent_type: "general"`). If your host has no subagent tool, do the batches yourself sequentially instead and say so.
   - Do **not** pass the ledger or tell the subagents what was fixed in prior passes; they must read the current docs and verify against the codebase cold.
   - Instruct each subagent:
     - Read its assigned doc/spec files completely, line by line.
     - Cross-check every factual claim against the actual code in the repository: routes, HTTP methods, status codes, query/body/path parameters, regex patterns, response shapes, file paths, module/function names, CLI flags, npm scripts, env vars, secret names, cache keys/versions/TTLs, timeouts, rate limits, and architectural descriptions.
     - Flag **only** untrue, misleading, contradictory, or out-of-date information (including examples that violate current validators/patterns, or plan/design docs whose status, requirements, or callout banners contradict what was built).
     - **Drop** pure wording/style/formatting preferences when the existing text is accurate.
     - Do **not** edit files inside the subagent; return findings as `{file, line, quoted_text, actual_code_behavior, suggested_fix}`.

2. **Check if Clean**:
   - Dedupe findings across subagents and filter out anypurely stylistic nits or items already marked `deferred` in the ledger.
   - If **0 findings** remain, stop the loop and go to **Report**.

3. **Update Docs**:
   - For each valid finding:
     - **Update** (default): edit the doc or spec file with the smallest, clearest change that makes it accurate and consistent with the codebase and surrounding prose.
     - **Defer**: only if resolving the contradiction requires a product decision from the user or editing an external resource (or if a finding reappears a 3rd time after two update attempts). Record it in the ledger for the Report.
   - If any OpenAPI spec (`docs/api.yaml`, `docs/paths/*.yaml`) or GraphQL schema (`schema.gql`) was updated:
     - Run the package's spec/schema build & validation commands (e.g. `npm run spec:bundle`, `npm run schemas:build`, `npm run compile-schema`, `npm run schemas:validate`) and update `.api.baseline.json` if descriptions/schemas intentionally changed.
     - Run relevant contract/schema tests to confirm everything passes.

4. **Log Status & Continue**:
   - Record the pass's findings and updates in `/tmp/bb-skillz/bbdoc-ledger.md`.
   - Output a one-line status (e.g. `Pass 1: 12 doc findings - 12 updated, 0 deferred. Running Pass 2...`).
   - Proceed to the next pass.

## Rules

- Do **not** commit, push, or post to GitHub unless the user explicitly asked for it in their prompt.
- Never invent behavior: every doc update must be verified against the actual code on disk.
- Keep edits concise and match the document's existing tone and formatting.

## Report

When the loop finishes (clean pass or after Pass 5), present a concise summary:
- **Affected docs audited**: list of files checked.
- **Passes run**: count and whether the final pass came back clean (0 findings).
- **Updates made**: per file, one-line summary of what was corrected.
- **Deferred items** (if any): numbered list with reason and suggested fix.
- **Validation status**: result of any spec bundle/validation or test runs.
