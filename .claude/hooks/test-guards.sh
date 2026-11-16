#!/usr/bin/env bash
# Tests for the layer 1a PreToolUse guards. Run: bash .claude/hooks/test-guards.sh
set -uo pipefail

dir="$(cd "$(dirname "$0")" && pwd)"
pass=0
fail=0
unset DATABASE_URL
export CLAUDE_PROJECT_DIR="$(mktemp -d)" # empty dir: no env files to fall back on

check() { # check <script> <expected allow|block> <tool> <json tool_input>
  local script="$1" expected="$2" tool="$3" tool_input="$4" code actual
  jq -n --arg tool "$tool" --argjson ti "$tool_input" \
    '{hook_event_name: "PreToolUse", tool_name: $tool, tool_input: $ti}' |
    "$dir/$script" >/dev/null 2>&1
  code=$?
  case "$code" in 0) actual=allow ;; 2) actual=block ;; *) actual="error($code)" ;; esac
  if [ "$actual" = "$expected" ]; then
    pass=$((pass + 1)); printf '  ok    %-5s %s\n' "$expected" "$tool_input"
  else
    fail=$((fail + 1)); printf '  FAIL  expected %s, got %s: %s\n' "$expected" "$actual" "$tool_input"
  fi
}

bash_case() { check guard-bash.sh "$1" Bash "$(jq -cn --arg c "$2" '{command: $c}')"; }

echo "guard-bash.sh: destructive commands"
bash_case block 'rm -rf node_modules'
bash_case block 'rm -fr dist'
bash_case block 'rm -r -f build'
bash_case block 'rm --recursive --force out'
bash_case block 'sudo rm -rf /'
bash_case block 'ls && rm -rf .next'
bash_case block 'git push --force origin main'
bash_case block 'git push origin main --force'
bash_case block 'git push -f'
bash_case block 'git push -uf origin main'
bash_case allow 'git push origin feature-f'
bash_case block 'git push --force-with-lease'
bash_case block 'git push origin +main'
bash_case block 'git reset --hard HEAD~1'
bash_case allow 'rm app/old-page.tsx'
bash_case allow 'rm app/l2-demo-format.ts app/re-fetch.ts'
bash_case allow 'rm -r app/old-dir'
bash_case allow 'echo "never run rm -rf"'
bash_case allow 'git push -u origin feature/coupon'
bash_case allow 'git reset --soft HEAD~1'
bash_case allow 'git commit -m "fix: coupon"'
bash_case allow 'pnpm build'

echo "guard-bash.sh: skipping git hooks"
bash_case block 'git commit --no-verify -m "wip"'
bash_case block 'git commit -n -m "wip"'
bash_case block 'git commit -anm "wip"'
bash_case block 'git push --no-verify'
bash_case block 'GIT_AUTHOR_NAME=x git commit --no-verify -m wip'
bash_case block 'LEFTHOOK=0 git commit -m "wip"'
bash_case block 'git -c core.hooksPath=/dev/null commit -m wip'
bash_case block 'git config core.hooksPath .nohooks'
bash_case block 'pnpm exec lefthook uninstall'
bash_case allow 'git commit -m "re-run tests"'
bash_case allow 'git commit -am "fix nav"'
bash_case allow 'git push -n origin feature/coupon'
bash_case allow 'pnpm exec lefthook run pre-commit'

echo "guard-bash.sh: database migrate / push"
bash_case block 'DATABASE_URL=postgresql://u:p@prod-db.example.com:5432/app pnpm exec prisma migrate deploy'
bash_case block 'DATABASE_URL="postgresql://u:p@10.0.0.5/app" pnpm exec drizzle-kit push'
bash_case block 'pnpm exec prisma migrate dev'
bash_case allow 'DATABASE_URL=postgresql://u:p@localhost:5432/app pnpm exec prisma migrate dev'
bash_case allow 'DATABASE_URL=postgresql://u:p@127.0.0.1/app pnpm exec prisma db push'
bash_case allow 'pnpm exec prisma generate'

echo "guard-bash.sh: env files"
bash_case block 'cat .env'
bash_case block 'cat .env.local'
bash_case block 'source .env.local && pnpm dev'
bash_case block 'grep STRIPE .env.local'
bash_case block 'echo FOO=1 >> .env'
bash_case block 'cp ./.env.local /tmp/x'
bash_case block 'git add .env.production'
bash_case allow 'cat .env.example'
bash_case allow 'grep -rn "process.env" app'
bash_case allow 'ls -la'

file_case() { check guard-files.sh "$1" "$2" "$3"; }

echo "guard-files.sh"
file_case block Read '{"file_path": "/repo/.env"}'
file_case block Read '{"file_path": "/repo/.env.local"}'
file_case block Edit '{"file_path": "/repo/.env.production", "old_string": "a", "new_string": "b"}'
file_case block Write '{"file_path": "/repo/.env", "content": "X=1"}'
file_case block Grep '{"pattern": "KEY", "path": "/repo/.env.local"}'
file_case block Grep '{"pattern": "KEY", "glob": ".env*"}'
file_case allow Read '{"file_path": "/repo/.env.example"}'
file_case allow Read '{"file_path": "/repo/app/page.tsx"}'
file_case allow Write '{"file_path": "/repo/docs/notes.md", "content": "uses process.env"}'
file_case allow Grep '{"pattern": "env", "path": "/repo/app", "glob": "*.tsx"}'

rmdir "$CLAUDE_PROJECT_DIR"
echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
