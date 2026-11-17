# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

## Commands

Package manager is **pnpm** (pinned via `packageManager` in `package.json`) — don't use npm/yarn.

```bash
pnpm dev          # dev server on http://localhost:3000 (Turbopack)
pnpm build        # production build — also type-checks
pnpm start        # serve the production build
pnpm lint         # ESLint (flat config, eslint-config-next core-web-vitals + typescript + eslint-config-prettier)
pnpm format       # Prettier, write fixes (defaults, .prettierrc.json is empty)
pnpm format:check # Prettier, check only (for CI)
pnpm typecheck    # next typegen && tsc --noEmit (route types first, then type-check)
pnpm test         # Vitest, run once (config: vitest.config.mts, tests: *.test.ts next to the code)
pnpm exec vitest run lib/format-price.test.ts   # a single test file
pnpm exec next typegen    # regenerate route types (PageProps/LayoutProps) without dev/build
```

## Git hooks (Lefthook)

`lefthook.yml` is installed by `pnpm install` (the `prepare` script). `pre-commit` runs Prettier, ESLint and gitleaks on staged files; `pre-push` runs `pnpm typecheck` and `pnpm test`. gitleaks must be installed on the machine (`brew install gitleaks`). Never skip the hooks (`--no-verify`): fix what they report. Write commit messages with `git commit -F <file>` when the message mentions env file names, because `.claude/hooks/guard-bash.sh` blocks commands containing them.

## CI (GitHub Actions)

`.github/workflows/ci.yml` runs on every pull request and on pushes to `main`, one job per status check: `lint`, `typecheck`, `test`, `build`, `suppressions`, `gitleaks`, `semgrep`, `dependency-review`. Shared setup lives in `.github/actions/setup`. `.github/workflows/claude-review.yml` runs the read-only reviewer agent (job `claude-review`, needs the `ANTHROPIC_API_KEY` secret): it posts one comment per reviewed commit listing serious issues only and never fails on what it finds. `suppressions` fails when a change adds `eslint-disable`, `@ts-ignore`, `@ts-expect-error`, `@ts-nocheck`, `nosemgrep` or `gitleaks:allow`; check locally with `scripts/check-suppressions.sh main`. ESLint has `noInlineConfig: true`, so comments in source files can't switch rules off or reconfigure them (`lint` fails on them). Pin every action to the full commit SHA of a release at least 21 days old, with the tag in a comment (`uses: owner/action@<sha> # vX.Y.Z`); semgrep fails on tag-only pins. Pin container images by digest (`image:tag@sha256:...`) and downloaded binaries by sha256 written in the workflow; update the pin together with the version.

## Merge policy (GitHub)

`main` is protected by the `main-protection` ruleset, defined in `.github/rulesets/main-protection.json` and applied to GitHub by the owner (the file has no effect by itself; how to apply it is in `docs/level-5-enforcement.md`). Changes reach `main` only through a pull request with all 9 checks green (the 8 above plus `claude-review`), the branch up to date and one approval from someone other than the last pusher; force push and deletion are blocked. If you rename or add a CI job, update `required_status_checks` in that JSON file in the same PR and say in the PR that the owner must re-apply the ruleset. `.github/CODEOWNERS` lists the files that set the rules (lint/type/format config, `package.json`, hooks, CI, scripts, agent instructions); a PR that changes them needs a code owner's approval (`@st-huynguyen` or `@bd-huynguyen`, never the PR author), so call them out in the PR description and request that review. Never approve a PR or change the ruleset on someone's behalf.

Tests for the hook and CI scripts: `bash .claude/hooks/test-guards.sh`, `bash .claude/hooks/test-format-lint.sh`, `bash scripts/check-suppressions.test.sh`.

The user's global pnpm config has `minimum-release-age` (21 days), so `pnpm add <pkg>@latest` resolves to the newest version at least 21 days old, not the true latest. Respect this; don't override it.

## Stack

- Next.js 16 (App Router only, `app/`), React 19, TypeScript strict
- Tailwind CSS v4: CSS-first config in `app/globals.css` (`@import "tailwindcss"` + `@theme inline`). There is **no** `tailwind.config.*` and **no** PostCSS config — CSS is processed by the `@tailwindcss/turbopack` loader registered under `turbopack.rules` in `next.config.ts`.
- Path alias `@/*` → repo root.

## Next.js config that changes how code must be written

`next.config.ts` enables:

- **`cacheComponents: true`** — Cache Components model. Caching is opt-in via `"use cache"`; dynamic/uncached data must sit behind `<Suspense>` boundaries. See `node_modules/next/dist/docs/01-app/01-getting-started/08-caching.md`.
- **`partialPrefetching: true`** (requires Cache Components) — `<Link>` prefetches a per-route App Shell instead of the full page; uncached data streams in after navigation. See `node_modules/next/dist/docs/01-app/02-guides/prefetching.md`.

`PageProps<'/route'>` and `LayoutProps<'/route'>` are global, generated type helpers (no import) — used in `app/layout.tsx`. They are produced into `.next/types` by `next dev`/`next build`/`next typegen`.

## Repo notes

- `AGENTS.md` is auto-managed by `next dev` (it re-adds its block); keep it committed as-is.
- `AI-Driven Development_ Level-Up Playbook.pptx.pdf` at the root is reference material for the project, not app code.
