# bb-skillz

Agent skills for multi-persona code review, code inspection, doc auditing and
PR sweep. One source of truth, symlinked into Claude Code, Codex CLI and
opencode so the copies can never drift apart again.

| Skill | What it does | Input |
| --- | --- | --- |
| `bb-review` | Multi-persona review of a PR (posts the review) or a local folder (suggests fixes only) | PR URL or folder |
| `bb-improve` | Runs `bb-review` in folder mode, fixes every finding, repeats until clean. Never commits/pushes | folder |
| `bb-inspect` | Same review bar, scoped to one module/page/feature instead of a diff | module, path, or `owner/repo target` |
| `bb-doc` | Audits affected docs line-by-line against the code and fixes them, up to 5 passes | optional path/topic |
| `ghprs` | Finds a PR with your review requested and runs `bb-review` on it | optional repo/author/number filter |

## Install

```bash
git clone https://github.com/BrianBal/bbSkillz.git ~/labs/bbSkillz
~/labs/bbSkillz/install.sh
```

The installer:

- symlinks each `skills/<name>` into `~/.agents/skills/` (read by Codex CLI and opencode)
  and `~/.claude/skills/` (read by Claude Code, and by opencode's Claude-compatible loader);
- symlinks the `commands/` wrappers into `~/.claude/commands/` and
  `~/.config/opencode/command/`;
- backs up (never deletes) any real directory it replaces, under
  `~/.local/state/bb-skillz/backup-<timestamp>/`;
- removes stale real copies from `~/.codex/skills/` and
  `~/.config/opencode/skills/` so an old copy cannot shadow the repo.

Update with `git -C ~/labs/bbSkillz pull`. Nothing else to re-run.

Uninstall with `~/labs/bbSkillz/install.sh --uninstall` (only removes symlinks
that point into this repo).

## Invoking

- **Claude Code**: `/bb-review`, `/bb-improve`, `/bb-inspect`, `/bb-doc`, `/ghprs`
- **opencode**: `/bb-review`, etc. (commands), or just ask in prose — the skill
  descriptions auto-trigger
- **Codex CLI**: `/skills` to pick, or `$bb-review ...` to invoke explicitly

## Layout

```
skills/<name>/SKILL.md      # the Agent Skills standard: name + description frontmatter
commands/claude/*.md        # thin $-argument wrappers
commands/opencode/*.md
install.sh
```

`SKILL.md` is the only format all three agents parse, so the skills themselves
are shared verbatim. The `commands/` layer exists only to give Claude and
opencode a slash-command entrypoint; Codex uses `$name` instead.

## Portability notes

- **Subagents.** `bb-review`, `bb-inspect`, `bb-doc` and `bb-improve` want to fan
  out to parallel reviewers. Every host with a subagent tool (Claude Code's Task
  tool, opencode's `task`, Codex subagents) uses it. On a host without one, the
  skill says to run the personas sequentially in the same order rather than skip
  them or fake parallelism.
- **Scratch space.** Temporary diffs, worktrees and ledgers go to
  `/tmp/bb-skillz/`, not into any tool's own directory.
- **Repo rules.** All skills read the repository's `AGENTS.md` / `CLAUDE.md`,
  so project conventions stay in the repo, not in the skill.
- **Duplicates.** opencode reads both `~/.agents/skills` and `~/.claude/skills`,
  so each skill is visible from two global paths there. If opencode ever lists a
  skill twice, drop the `~/.claude/skills` symlinks (opencode still finds them
  through `~/.agents/skills`).
