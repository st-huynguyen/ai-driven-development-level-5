#!/usr/bin/env bash
# PreToolUse guard for file tools (layer 1a, see docs/level-5-enforcement.md).
# Blocks Read/Edit/MultiEdit/Write/Grep on .env files (any case, or a glob for one), except templates.
# Blocks Edit/MultiEdit/Write of files that switch the layer 2 git hooks off.
# Exit 0 = allow, exit 2 = block (stderr is shown to the agent).
set -uo pipefail

. "$(dirname "$0")/env-names.sh"

input="$(cat)"
tool="$(jq -r '.tool_name // empty' <<<"$input")"
paths="$(jq -r '.tool_input | (.file_path, .path, .glob) // empty' <<<"$input")"

while IFS= read -r p; do
  [ -z "$p" ] && continue
  if is_secret_env_name "$(basename -- "$p")"; then
    echo "Blocked by .claude/hooks/guard-files.sh: '$p' holds secrets and cannot be read or modified by the agent. Use .env.example to see which variables exist." >&2
    exit 2
  fi
  case "$tool" in
    Edit | MultiEdit | Write)
      case "$p" in
        */.git/hooks/* | .git/hooks/* | lefthook-local.* | .lefthook-local.* | */lefthook-local.* | */.lefthook-local.*)
          echo "Blocked by .claude/hooks/guard-files.sh: '$p' can switch the git hooks off. Fix what the hook reports instead." >&2
          exit 2
          ;;
      esac
      ;;
  esac
done <<<"$paths"

exit 0
