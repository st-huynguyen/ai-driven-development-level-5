#!/usr/bin/env bash
# Tests for scripts/check-suppressions.sh. Run: bash scripts/check-suppressions.test.sh
set -uo pipefail

checker="$(cd "$(dirname "$0")" && pwd)/check-suppressions.sh"
repo="$(mktemp -d)"
trap 'rm -r "$repo"' EXIT
pass=0
fail=0

g() { git -C "$repo" "$@" >/dev/null 2>&1; }
g init -b main
g config user.email test@example.com
g config user.name test
g config commit.gpgsign false
mkdir -p "$repo/lib" "$repo/docs"
printf '// eslint-disable-next-line no-console\nconsole.log("old");\n' >"$repo/lib/old.ts"
printf 'export const a = 1;\n' >"$repo/lib/a.ts"
g add -A
g commit -m base
g switch -c feature # each case commits here and is compared against main

check() { # check <name> <expected exit> [expected text in output]
  local name="$1" expected="$2" text="${3-}" out code
  g add -A
  g commit -m "$name"
  out="$(cd "$repo" && "$checker" main 2>&1)"
  code=$?
  if [ "$code" = "$expected" ] && { [ -z "$text" ] || grep -qF -- "$text" <<<"$out"; }; then
    pass=$((pass + 1)); printf '  ok    exit %s  %s\n' "$code" "$name"
  else
    fail=$((fail + 1)); printf '  FAIL  %s: expected exit %s, got %s\n' "$name" "$expected" "$code"
    sed 's/^/        /' <<<"$out"
  fi
  g reset --hard main # next case starts from the base again
}

echo "check-suppressions.sh"
printf 'export const a = 2;\n' >"$repo/lib/a.ts"
check "clean change passes (old suppressions are ignored)" 0
printf 'export const a = 1;\n// eslint-disable-next-line @typescript-eslint/no-explicit-any\nexport const b: any = 2;\n' >"$repo/lib/a.ts"
check "eslint-disable is reported with file and line" 1 "lib/a.ts:2:"
printf '// @ts-ignore\nexport const c: number = "x";\n' >"$repo/lib/c.ts"
check "@ts-ignore in a new file" 1 "lib/c.ts:1:"
printf '// @ts-expect-error legacy\nexport const d: number = "x";\n' >"$repo/lib/d.ts"
check "@ts-expect-error" 1 "lib/d.ts:1:"
printf '/* eslint-disable */\nexport const e = 1;\n' >"$repo/lib/e.tsx"
check "file-wide eslint-disable" 1 "lib/e.tsx:1:"
printf 'const q = db.raw(input); // nosemgrep\n' >"$repo/lib/q.ts"
check "nosemgrep" 1 "lib/q.ts:1:"
printf '++ eslint-disable\n// @ts-ignore\n' >"$repo/lib/plus.txt"
check "added line starting with '++ ' is checked, not taken as a file header" 1 "lib/plus.txt:2:"
printf '++ eslint-disable\n' >"$repo/lib/plus.txt"
check "added line starting with '++ ' is reported itself" 1 "lib/plus.txt:1:"
printf 'Never add eslint-disable or @ts-ignore.\n' >"$repo/docs/rules.md"
check "markdown is ignored" 0
printf 'console.log("old");\n' >"$repo/lib/old.ts"
check "removing a suppression passes" 0

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
