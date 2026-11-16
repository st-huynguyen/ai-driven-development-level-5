#!/usr/bin/env bash
# PreToolUse guard for the Bash tool (layer 1a, see docs/level-5-enforcement.md).
# Reads the hook JSON on stdin. Exit 0 = allow, exit 2 = block (stderr is shown to the agent).
set -uo pipefail

input="$(cat)"
cmd="$(jq -r '.tool_input.command // empty' <<<"$input")"
project_dir="${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$input")}"
[ -z "$cmd" ] && exit 0

block() {
  echo "Blocked by .claude/hooks/guard-bash.sh: $1" >&2
  exit 2
}

# Start of a command: line start or after ; & | ( and optional whitespace.
S='(^|[;&|(][[:space:]]*)'

# 1. Destructive commands
if grep -qE "${S}(sudo[[:space:]]+)?rm[[:space:]]" <<<"$cmd"; then
  if grep -qE "${S}(sudo[[:space:]]+)?rm[[:space:]]+([^;&|]*[[:space:]])?-[a-zA-Z]*([rR][a-zA-Z]*f|f[a-zA-Z]*[rR])" <<<"$cmd" ||
     { grep -qE "${S}(sudo[[:space:]]+)?rm[[:space:]]+([^;&|]*[[:space:]])?(-[a-zA-Z]*[rR]|--recursive)([[:space:]]|$)" <<<"$cmd" &&
       grep -qE "${S}(sudo[[:space:]]+)?rm[[:space:]]+([^;&|]*[[:space:]])?(-[a-zA-Z]*f|--force)([[:space:]]|$)" <<<"$cmd"; }; then
    block "'rm -rf' is not allowed. Delete specific files without -rf, or ask the user to do it."
  fi
fi

if grep -qE "${S}git[[:space:]]+push[[:space:]]+([^;&|]*[[:space:]])?(--force[a-z-]*|-[a-zA-Z]*f([[:space:]]|$)|\+[^[:space:]]+)" <<<"$cmd"; then
  block "force push is not allowed. Push normally and open a pull request."
fi

if grep -qE "${S}git[[:space:]]+reset[[:space:]][^;&|]*--hard" <<<"$cmd"; then
  block "'git reset --hard' discards work and is not allowed. Use 'git stash' or ask the user."
fi

# 2. Skipping the git hooks of layer 2
if grep -qE "${S}([^[:space:];&|]+=[^[:space:];&|]*[[:space:]]+)*git[[:space:]][^;&|]*--no-verify" <<<"$cmd" ||
   grep -qE "${S}git[[:space:]]+commit[[:space:]]([^;&|]*[[:space:]])?-[a-zA-Z]*n[a-zA-Z]*([[:space:]]|$)" <<<"$cmd"; then
  block "skipping git hooks (--no-verify) is not allowed. Fix what the hook reports instead."
fi
if grep -qE "(^|[[:space:];&|(])LEFTHOOK=(0|false)([[:space:]]|$)" <<<"$cmd" ||
   grep -qE "core\.hooksPath|${S}(pnpm[[:space:]]+(exec[[:space:]]+)?|npx[[:space:]]+)?lefthook[[:space:]]+uninstall" <<<"$cmd"; then
  block "disabling or redirecting git hooks is not allowed. Fix what the hook reports instead."
fi

# 3. DB migrate / push only against a local database
if grep -qE "(prisma[[:space:]]+(migrate|db[[:space:]]+(push|execute))|drizzle-kit[[:space:]]+(push|migrate))" <<<"$cmd"; then
  db_url="$(grep -oE 'DATABASE_URL=[^[:space:];&|]+' <<<"$cmd" | head -1 | cut -d= -f2- | tr -d "'\"")"
  [ -z "$db_url" ] && db_url="${DATABASE_URL:-}"
  if [ -z "$db_url" ]; then
    for f in .env.local .env; do
      if [ -f "$project_dir/$f" ]; then
        db_url="$(grep -E '^[[:space:]]*DATABASE_URL=' "$project_dir/$f" | tail -1 | cut -d= -f2- | tr -d "'\"")"
        [ -n "$db_url" ] && break
      fi
    done
  fi
  host="$(sed -E 's#^[a-zA-Z0-9+]+://([^@/]*@)?(\[[^]]*\]|[^:/?]*).*#\2#' <<<"$db_url")"
  case "$host" in
    localhost | 127.0.0.1 | "[::1]" | host.docker.internal) ;;
    *) block "DB migrate/push is only allowed against a local database (DATABASE_URL host: '${host:-unknown}')." ;;
  esac
fi

# 4. Commands that touch .env files (templates are allowed)
env_refs="$(grep -oE "(^|[[:space:]/'\"=<>:])\.env(\.[A-Za-z0-9_-]+)*" <<<"$cmd" | sed -E "s#^[[:space:]/'\"=<>:]##")"
while IFS= read -r ref; do
  case "$ref" in
    "" | .env.example | .env.sample | .env.template) ;;
    *) block "commands that touch '$ref' are not allowed: it holds secrets. Use .env.example to see which variables exist." ;;
  esac
done <<<"$env_refs"

exit 0
