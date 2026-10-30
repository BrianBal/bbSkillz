#!/usr/bin/env bash
# Install bb-skillz into Claude Code, Codex CLI and opencode via symlinks.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/bb-skillz"
BACKUP="$BACKUP_ROOT/backup-$(date +%Y%m%d-%H%M%S)"

# Loaded as user skills by Codex CLI and opencode, and by opencode's
# Claude-compatible loader only once (see README for the duplicate note).
SKILL_TARGETS=(
  "$HOME/.agents/skills"
  "$HOME/.claude/skills"
)

# Leftovers from earlier manual copies: backed up and removed so they cannot drift.
STALE_SKILL_DIRS=(
  "$HOME/.codex/skills"
  "$HOME/.config/opencode/skills"
)

# <dir>:<subdir of ./commands>
COMMAND_TARGETS=(
  "$HOME/.claude/commands:claude"
  "$HOME/.config/opencode/command:opencode"
)

backup_path() {
  local dest="$1" rel
  rel="${dest#"$HOME"/}"
  mkdir -p "$BACKUP/$(dirname "$rel")"
  cp -a "$dest" "$BACKUP/$rel"
  printf '  moved %s -> %s\n' "$dest" "$BACKUP/$rel"
}

link_path() {
  local src="$1" dest="$2"
  if [ -L "$dest" ]; then
    rm -f "$dest"
  elif [ -e "$dest" ]; then
    backup_path "$dest"
    rm -rf "$dest"
  fi
  mkdir -p "$(dirname "$dest")"
  ln -s "$src" "$dest"
  printf '  linked %s -> %s\n' "$dest" "$src"
}

uninstall() {
  local removed=0 dest
  for dest in "$HOME"/.agents/skills/* "$HOME"/.claude/skills/* \
              "$HOME"/.codex/skills/* "$HOME"/.config/opencode/skills/* \
              "$HOME"/.claude/commands/* "$HOME"/.config/opencode/command/*; do
    [ -L "$dest" ] || continue
    case "$(readlink "$dest")" in
      "$REPO"/*) rm -f "$dest"; printf '  removed %s\n' "$dest"; removed=$((removed + 1)) ;;
    esac
  done
  printf 'Removed %d symlink(s); real files were never touched.\n' "$removed"
}

if [ "${1:-}" = "--uninstall" ]; then
  uninstall
  exit 0
fi

printf 'Installing from %s\n' "$REPO"

for dir in "${STALE_SKILL_DIRS[@]}"; do
  for path in "$REPO"/skills/*/; do
    name="$(basename "$path")"
    if [ -d "$dir/$name" ] && [ ! -L "$dir/$name" ]; then
      backup_path "$dir/$name"
      rm -rf "$dir/$name"
    fi
  done
done

# Drop links into this repo that no longer match a current skill (e.g. renamed).
prune_repo_links() {
  local dir="$1" dest raw
  [ -d "$dir" ] || return 0
  for dest in "$dir"/*; do
    [ -L "$dest" ] || continue
    raw="$(readlink "$dest")"
    case "$raw" in
      "$REPO"/*) rm -f "$dest"; printf '  pruned stale link %s\n' "$dest" ;;
    esac
  done
}

for dir in "${SKILL_TARGETS[@]}"; do
  prune_repo_links "$dir"
  mkdir -p "$dir"
  for path in "$REPO"/skills/*/; do
    name="$(basename "$path")"
    link_path "$REPO/skills/$name" "$dir/$name"
  done
done

for pair in "${COMMAND_TARGETS[@]}"; do
  target="${pair%%:*}"
  src="$REPO/commands/${pair##*:}"
  prune_repo_links "$target"
  mkdir -p "$target"
  for file in "$src"/*.md; do
    link_path "$file" "$target/$(basename "$file")"
  done
done

printf '\nDone. Restart Claude Code / Codex / opencode if the skills do not appear.\n'
if [ -d "$BACKUP" ]; then
  printf 'Backups of replaced files: %s\n' "$BACKUP"
fi
