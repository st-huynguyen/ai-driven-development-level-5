#!/usr/bin/env bash
# Layer 3b of docs/level-5-enforcement.md: fail when a change adds a comment that
# switches a check off (eslint-disable, @ts-ignore, nosemgrep, ...).
# Only lines added since the merge base count, so existing suppressions don't fail it.
#
# Usage: scripts/check-suppressions.sh [base-ref]   (default: origin/main)
set -euo pipefail

base="${1:-origin/main}"
patterns='eslint-disable|@ts-ignore|@ts-expect-error|@ts-nocheck|nosemgrep|gitleaks:allow'

# Files that mention these words on purpose: docs, the guard hooks and this checker.
excludes=(
  ':(exclude)*.md'
  ':(exclude).claude/hooks/*'
  ':(exclude)scripts/check-suppressions*'
)

findings="$(
  git diff --unified=0 --no-color --no-ext-diff "$base...HEAD" -- . "${excludes[@]}" |
    awk -v pat="$patterns" '
      # File headers sit between "diff --git" and the first "@@". Inside a hunk, an added
      # line whose text starts with "++ " also begins with "+++ ", so only trust it here.
      /^diff --git / { header = 1; next }
      header && /^\+\+\+ / { file = substr($0, 7); next }    # "+++ b/<path>"
      /^@@/      { header = 0; split($3, a, ","); line = substr(a[1], 2) + 0; next }  # "@@ -a,b +c,d @@"
      !header && /^\+/ { if ($0 ~ pat) printf "%s\t%d\t%s\n", file, line, substr($0, 2); line++ }
    '
)"

if [ -z "$findings" ]; then
  echo "No new suppression comments since $base."
  exit 0
fi

echo "New suppression comments since $base:"
while IFS=$'\t' read -r file line text; do
  echo "  $file:$line: ${text#"${text%%[![:space:]]*}"}"
  # GitHub Actions turns this into an annotation on the PR diff.
  [ -n "${GITHUB_ACTIONS:-}" ] && echo "::error file=$file,line=$line::New suppression comment. Fix the underlying problem instead of switching the check off."
done <<<"$findings"
echo
echo "Fix the underlying problem instead of switching the check off."
echo "If a suppression is truly needed, a reviewer has to approve it explicitly."
exit 1
