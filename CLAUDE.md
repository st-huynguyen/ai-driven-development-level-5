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
pnpm exec tsc --noEmit    # type-check only
pnpm exec next typegen    # regenerate route types (PageProps/LayoutProps) without dev/build
```

No test runner is set up yet.

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
