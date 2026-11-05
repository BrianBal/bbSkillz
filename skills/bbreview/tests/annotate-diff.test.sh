#!/usr/bin/env bash
# Runs the diff-annotator awk command exactly as written in ../SKILL.md
# against a fixture and compares with the expected output.
# Fixture covers: removed lines starting with "--", added lines starting with
# "++", "\ No newline at end of file", a new file, multiple hunks, and
# count-less "@@ -N +N @@" headers from -U0 diffs.
set -euo pipefail
dir="$(cd "$(dirname "$0")" && pwd)"
prog="$(sed -n "s/^ *awk '\(.*\)' <raw-diff> > .*/\1/p" "$dir/../SKILL.md")"
if [ -z "$prog" ]; then
  echo "FAIL: could not find the annotator awk command in SKILL.md" >&2
  exit 1
fi
if diff -u "$dir/annotate-diff.expected" <(awk "$prog" "$dir/annotate-diff.fixture.diff"); then
  echo "PASS: annotate-diff"
else
  echo "FAIL: annotate-diff output differs from expected (see diff above)" >&2
  exit 1
fi
