#!/usr/bin/env bash
# Tests for the layer 1b PostToolUse hook. Run: bash .claude/hooks/test-format-lint.sh
set -uo pipefail

dir="$(cd "$(dirname "$0")" && pwd)"
export CLAUDE_PROJECT_DIR="$(cd "$dir/../.." && pwd)"
tmp="$CLAUDE_PROJECT_DIR/.claude/hooks/.test-tmp"
mkdir -p "$tmp"
trap 'rm -r "$tmp"' EXIT
pass=0
fail=0

run_hook() { # run_hook <file_path> -> sets code
  jq -n --arg f "$1" '{hook_event_name: "PostToolUse", tool_name: "Write", tool_input: {file_path: $f}}' |
    "$dir/format-lint.sh" >/dev/null 2>"$tmp/stderr"
  code=$?
}

check() { # check <name> <file> <content> <expected exit> [expected content after hook]
  local name="$1" file="$tmp/$2" content="$3" expected="$4" after="${5-}"
  printf '%s' "$content" >"$file"
  run_hook "$file"
  local ok=1
  [ "$code" = "$expected" ] || ok=0
  if [ -n "$after" ] && [ "$(cat "$file")" != "$(printf '%s' "$after")" ]; then ok=0; fi
  if [ "$ok" = 1 ]; then
    pass=$((pass + 1)); printf '  ok    exit %s  %s\n' "$code" "$name"
  else
    fail=$((fail + 1)); printf '  FAIL  %s: expected exit %s, got %s\n' "$name" "$expected" "$code"
    sed 's/^/        /' "$tmp/stderr"
    [ -n "$after" ] && { echo "        file now:"; sed 's/^/        | /' "$file"; }
  fi
}

echo "format-lint.sh"
check "unformatted TS gets formatted" fmt.ts \
  $'const  x = {a:1}\nexport default x' 0 \
  $'const x = { a: 1 };\nexport default x;'
check "auto-fixable lint is fixed (let -> const)" fix.ts \
  $'let a = 1;\nexport default a;\n' 0 \
  $'const a = 1;\nexport default a;'
check "unused variable is reported back" unused.ts \
  $'const unused = 1;\nexport const y = 2;\n' 2
check "syntax error is reported back" broken.tsx \
  $'export const A = () => <div>;\n' 2
check "markdown is formatted, not linted" note.md \
  $'# Title\n*  item' 0 \
  $'# Title\n\n- item'
check "unknown file type is left alone" script.sh \
  $'echo   hi\n' 0 \
  $'echo   hi'
check "prettier-ignored path is left alone" AGENTS.md \
  $'*  keep   as is\n' 0 \
  $'*  keep   as is'

run_hook "$tmp/does-not-exist.ts"
if [ "$code" = 0 ]; then pass=$((pass + 1)); echo "  ok    exit 0  missing file is skipped"; else fail=$((fail + 1)); echo "  FAIL  missing file: exit $code"; fi
run_hook "/tmp/outside-project.ts"
if [ "$code" = 0 ]; then pass=$((pass + 1)); echo "  ok    exit 0  file outside the project is skipped"; else fail=$((fail + 1)); echo "  FAIL  outside project: exit $code"; fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
