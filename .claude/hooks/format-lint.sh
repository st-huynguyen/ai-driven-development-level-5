#!/usr/bin/env bash
# PostToolUse hook for Edit/MultiEdit/Write (layer 1b, see docs/level-5-enforcement.md).
# Formats and lints only the file the agent just changed.
# Exit 0 = clean, exit 2 = problems remain (stderr is shown to the agent so it fixes them).
set -uo pipefail

input="$(cat)"
file="$(jq -r '.tool_input.file_path // empty' <<<"$input")"
project_dir="${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$input")}"

[ -z "$file" ] && exit 0
[ -f "$file" ] || exit 0
case "$file" in
  "$project_dir"/*) ;;
  *) exit 0 ;; # outside the project: not ours to format
esac

bin="$project_dir/node_modules/.bin"
cd "$project_dir" || exit 0
rel="${file#"$project_dir"/}"

# 1. Prettier: respects .prettierignore and .gitignore, skips file types it doesn't know.
if [ -x "$bin/prettier" ]; then
  if ! out="$("$bin/prettier" --write --ignore-unknown --log-level warn -- "$rel" 2>&1)"; then
    {
      echo "Prettier could not format $rel (often a syntax error). Fix it:"
      echo "$out"
    } >&2
    exit 2
  fi
fi

# 2. ESLint: only JS/TS files. Same strictness as CI (--max-warnings 0).
case "$rel" in
  *.js | *.jsx | *.mjs | *.cjs | *.ts | *.tsx | *.mts | *.cts) ;;
  *) exit 0 ;;
esac
[ -x "$bin/eslint" ] || exit 0

if ! out="$("$bin/eslint" --fix --max-warnings 0 --no-warn-ignored -- "$rel" 2>&1)"; then
  {
    echo "ESLint problems remain in $rel after auto-fix. Fix them (do not add eslint-disable):"
    echo "$out"
  } >&2
  exit 2
fi

exit 0
