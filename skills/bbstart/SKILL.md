---
name: bbstart
description: Turn a task or ticket into a researched, visual, interactive plan before any code is written. Investigates the codebase, discusses approaches with the user, then builds a self-contained HTML planning artifact containing the research, the plan, the options and the open questions, plus an optional small proof of concept. Never implements the task. Use when the user gives a task and wants to think it through first, invokes `/bbstart`, or says "let's plan this" / "how should we do X".
---

# BB Start

Input: a task, ticket, or free-form description of work to be done.

## 1. Understand

Record the request in the user's own words. Ask only what actually blocks investigation (scope, target repo, deadline) - do not interrogate. Read the repo's `AGENTS.md` / `CLAUDE.md` and look at what already exists before proposing anything.

## 2. Investigate

Map the areas the task touches, find patterns and utilities to reuse, note constraints (tests, build, deploy, data model), and list what you could not determine. Cite `path:line` for every claim about the code. Read-only: change nothing.

## 3. Discuss

Present 2-3 viable approaches with honest tradeoffs (effort, risk, blast radius, reversibility), recommend one and say why, and ask the questions only the user can answer. Converge before building anything.

## 4. Build the artifact

One self-contained HTML page in a visual, interactive planning space: the research, the plan, the options considered, and the open questions. Layout, sections and interactions are yours to choose - make it useful to read and steer, not a wall of text. No build step, no CDN, nothing that breaks offline: it must open straight from `file://`.

An optional small proof-of-concept demo is welcome when it clarifies a decision (a mockup, a throwaway spike, a flow diagram). Skip it when it would not help, and say so.

Write `plan.md` beside it with the same content in plain markdown, so agents and git can read the plan without parsing HTML.

Save under:

- inside a git repo: `.bb/artifacts/<YYYY-MM-DD>-<slug>/`
- otherwise: `${XDG_CONFIG_HOME:-$HOME/.config}/bb/artifacts/<YYYY-MM-DD>-<slug>/`

The folder holds `index.html`, `plan.md`, and any demo files. Open the page (or, if the demo needs real files, serve that folder with `python3 -m http.server` and give the URL) and print the path. If the host has its own artifact surface (Claude desktop, claude.ai), publish there too.

## 5. Hand off

Offer the next step: keep iterating on the plan, start implementing, or hand the folder to `bbreview` / `bbimprove`.

## Rules

- Research and the plan are always present. The demo is optional.
- Never invent repo behaviour; every claim traces to code you read.
- Keep the page current: update it when the discussion changes the plan.
- Do not implement the task, commit, push, or open a PR unless the user asks.
