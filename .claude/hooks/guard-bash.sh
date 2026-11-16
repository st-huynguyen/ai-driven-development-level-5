#!/usr/bin/env bash
# PreToolUse guard for the Bash tool (layer 1a, see docs/level-5-enforcement.md).
# Reads the hook JSON on stdin. Exit 0 = allow, exit 2 = block (stderr is shown to the agent).
set -uo pipefail

input="$(cat)"
cmd="$(jq -r '.tool_input.command // empty' <<<"$input")"
project_dir="${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$input")}"
[ -z "$cmd" ] && exit 0

. "$(dirname "$0")/env-names.sh"

block() {
  echo "Blocked by .claude/hooks/guard-bash.sh: $1" >&2
  exit 2
}

# Start of a command: line start, after ; & | ( ` {, or after a keyword or wrapper that runs the
# next word as a command (do rm, then rm, xargs rm, find -exec rm, sudo rm, env rm, ...).
# Then any options or VAR=value words (xargs -0 rm, FOO=1 git commit).
W='(-[^[:space:];&|]*[[:space:]]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*[[:space:]]+)*'
WRAP='do|then|else|elif|xargs|-exec|-execdir|-ok|exec|command|builtin|env|nohup|time|nice|sudo|doas'
S="(^|[;&|(\`{]|(^|[[:space:];&|(\`{])(${WRAP})[[:space:]])[[:space:]]*${W}"
# rm, also as /bin/rm or \rm.
RM="${S}"'([^[:space:];&|]*/)?\\?rm'
# git plus global options before the subcommand (git -C dir, git -c key=value, git --no-pager).
GIT="${S}"'([^[:space:];&|]*/)?git([[:space:]]+-[^[:space:];&|]+([[:space:]]+[^-[:space:];&|][^[:space:];&|]*)?)*[[:space:]]+'

# 1. Destructive commands
if grep -qE "${RM}[[:space:]]" <<<"$cmd"; then
  if grep -qE "${RM}[[:space:]]+([^;&|]*[[:space:]])?-[a-zA-Z]*([rR][a-zA-Z]*f|f[a-zA-Z]*[rR])" <<<"$cmd" ||
     { grep -qE "${RM}[[:space:]]+([^;&|]*[[:space:]])?(-[a-zA-Z]*[rR]|--recursive)([[:space:]]|$)" <<<"$cmd" &&
       grep -qE "${RM}[[:space:]]+([^;&|]*[[:space:]])?(-[a-zA-Z]*f|--force)([[:space:]]|$)" <<<"$cmd"; }; then
    block "'rm -rf' is not allowed. Delete specific files without -rf, or ask the user to do it."
  fi
fi

if grep -qE "${GIT}push[[:space:]]+([^;&|]*[[:space:]])?(--force[a-z-]*|-[a-zA-Z]*f([[:space:]]|$)|\+[^[:space:]]+)" <<<"$cmd"; then
  block "force push is not allowed. Push normally and open a pull request."
fi

if grep -qE "${GIT}reset[[:space:]][^;&|]*--hard" <<<"$cmd"; then
  block "'git reset --hard' discards work and is not allowed. Use 'git stash' or ask the user."
fi

# 2. Skipping the git hooks of layer 2
if grep -qE "${S}([^[:space:];&|]*/)?git[[:space:]][^;&|]*--no-verify" <<<"$cmd" ||
   grep -qE "${GIT}commit[[:space:]]([^;&|]*[[:space:]])?-[a-zA-Z]*n[a-zA-Z]*([[:space:]]|$)" <<<"$cmd"; then
  block "skipping git hooks (--no-verify) is not allowed. Fix what the hook reports instead."
fi
# LEFTHOOK=0 turns every hook off; LEFTHOOK_EXCLUDE skips jobs (gitleaks...), LEFTHOOK_CONFIG and
# LEFTHOOK_BIN swap the config or binary; lefthook-local.yml can override jobs; .git/hooks holds the hooks.
if grep -qE "(^|[[:space:];&|(])(LEFTHOOK=(0|false)([[:space:]]|$)|LEFTHOOK_(EXCLUDE|CONFIG|BIN)=)" <<<"$cmd" ||
   grep -qE "core\.hooksPath|\.git/hooks|lefthook-local\.|${S}(pnpm[[:space:]]+(exec[[:space:]]+)?|npx[[:space:]]+)?lefthook[[:space:]]+uninstall" <<<"$cmd"; then
  block "disabling or redirecting git hooks is not allowed. Fix what the hook reports instead."
fi

# 3. DB migrate / push only against a local database
db_host() { sed -E 's#^[a-zA-Z0-9+]+://([^@/]*@)?(\[[^]]*\]|[^:/?]*).*#\2#' <<<"$1"; }
if grep -qE "(prisma[[:space:]]+(migrate|db[[:space:]]+(push|execute))|drizzle-kit[[:space:]]+(push|migrate))" <<<"$cmd"; then
  urls=()
  inline="$(grep -oE 'DATABASE_URL=[^[:space:];&|]+' <<<"$cmd" | head -1 | cut -d= -f2- | tr -d "'\"")"
  if [ -n "$inline" ]; then
    urls=("$inline")
  elif [ -n "${DATABASE_URL:-}" ]; then
    urls=("$DATABASE_URL")
  else
    # Tools load different env files (Prisma CLI: .env only; Next.js and most drizzle configs:
    # .env.local too), so every env file that sets DATABASE_URL must point at a local database.
    for f in "$project_dir"/.env "$project_dir"/.env.*; do
      [ -f "$f" ] || continue
      case "${f##*/}" in .env.example | .env.sample | .env.template) continue ;; esac
      u="$(grep -E '^[[:space:]]*(export[[:space:]]+)?DATABASE_URL=' "$f" | tail -1 | cut -d= -f2- | tr -d "'\"")"
      [ -n "$u" ] && urls+=("$u")
    done
  fi
  [ "${#urls[@]}" -eq 0 ] &&
    block "DB migrate/push is only allowed against a local database (DATABASE_URL host: 'unknown')."
  for u in "${urls[@]}"; do
    host="$(db_host "$u")"
    case "$host" in
      localhost | 127.0.0.1 | "[::1]" | host.docker.internal) ;;
      *) block "DB migrate/push is only allowed against a local database (DATABASE_URL host: '${host:-unknown}')." ;;
    esac
  done
fi

# 4. Commands that touch env files (templates are allowed).
# Split into words on shell punctuation, so ./.env, {.env.local,} and --env-file=.env each yield a word.
split_words() { tr -s "[:space:];&|()<>=:{},\`" '\n'; }
env_block() {
  block "commands that touch '$1' are not allowed: it holds secrets. Use .env.example to see which variables exist."
}
# Names: drop quotes and backslashes first (.e"n"v and .\env are .env to the shell).
while IFS= read -r word; do
  case "$word" in "" | *[*?[]*) continue ;; esac
  is_secret_env_name "${word##*/}" && env_block "$word"
done < <(tr -d "\\\\\"'" <<<"$cmd" | split_words)
# Globs (.en?.local, .e*): only outside quotes, where the shell expands them ('s|.*|x|' is a regex).
while IFS= read -r word; do
  case "$word" in *[*?[]*) is_secret_env_name "${word##*/}" && env_block "$word" ;; esac
done < <(sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g" <<<"$cmd" | split_words)

exit 0
