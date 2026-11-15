#!/usr/bin/env bash
# PreToolUse guard for file tools (layer 1a, see docs/level-5-enforcement.md).
# Blocks Read/Edit/MultiEdit/Write/Grep on .env files, except templates.
# Exit 0 = allow, exit 2 = block (stderr is shown to the agent).
set -uo pipefail

input="$(cat)"
paths="$(jq -r '.tool_input | (.file_path, .path, .glob) // empty' <<<"$input")"

while IFS= read -r p; do
  [ -z "$p" ] && continue
  name="$(basename -- "$p")"
  case "$name" in
    .env.example | .env.sample | .env.template) ;;
    .env | .env.* | .env\*)
      echo "Blocked by .claude/hooks/guard-files.sh: '$p' holds secrets and cannot be read or modified by the agent. Use .env.example to see which variables exist." >&2
      exit 2
      ;;
  esac
done <<<"$paths"

exit 0
