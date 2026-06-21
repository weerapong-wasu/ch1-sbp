# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Chapter One Shine Bang Pho (CH1-SBP) — Daily Progress Report system for Forma Corporations. Single structure, 33 in-scope floors (Ground + Floor 1–32). Two work scopes: **EXT** (exterior façade — crack repair + repaint, by rope access, tracked Zone × Elevation) and **INT** (interior — crack/ceiling/flooring/paint, tracked room-by-room per floor). Tracks progress, manpower/safety, site photos, rooms. Contract CH1-SBP/FORMA/001/2569 (total value 6,500,000 THB). Adapted from the Chapter One Modern Dutch base.

⚠️ The Supabase **anon key is a PLACEHOLDER** (`index.html` SUPABASE_ANON = 'PLACEHOLDER_ANON_KEY'). The app cannot connect until the real anon/public key from the `wvihzrdokwpjeneycppv` project is filled into both `index.html` and `.env.local`.

## Architecture

**Everything lives in `index.html`** (~2550 lines, vanilla JS + inline CSS). No build system, no package manager, no tests. To develop, open `index.html` directly in a browser or deploy to Vercel (`vercel.json` rewrites all paths to `index.html` — SPA-style). SQL for the backend lives in `db/`.

External dependencies load from CDN:
- `@supabase/supabase-js@2.39.3` (UMD build — the UMD CDN is load-bearing; earlier commits regressed when the ESM build was used)
- `Chart.js 4.4.1` (UMD) for the S-curve and velocity chart

### Backend (Supabase)

Project URL and anon key are hardcoded at the top of the `<script>` block. Data model:

- `profiles` — user role (`admin` | `internal` | `client`)
- `projects` — looked up by `code='CH1-SBP-2026'` to get `PROJECT_ID`
- `daily_reports` — one row per `(project_id, report_date)`; upserted on save
- `floor_progress` — child rows keyed on `(report_id, building, floor_no)`; one batch upsert per save
- `photos` — metadata rows; files live in Storage bucket `ch1-sbp-photos`
- `payment_milestones` — 4 contract installments; seeded by `db/payment_milestones.sql` (amounts are a placeholder split summing to 6.5M — confirm vs signed schedule)
- `rooms` — INT scope (room-by-room tracking, room lifecycle + cert/warranty)
- `scope_ext` — EXT scope (façade grid: zone × elevation); seeded by `db/scope_ext_seed.sql`
- `audit_logs` — written on every report save

The new Supabase project is **empty** — run `db/schema.sql` FIRST (creates all core tables + `scope_ext`, seeds the `projects` row `code='CH1-SBP-2026'`, applies RLS), then the seed/RLS files below. SQL files in `db/` are idempotent (table uses `IF NOT EXISTS`, seeds `ON CONFLICT DO NOTHING`, every policy `DROP`ped first) — run them in Supabase Dashboard → SQL Editor:
- `db/schema.sql` — full core schema + `scope_ext` + projects seed + RLS (run first)
- `db/rls_photos.sql` — RLS for `photos` table + `storage.objects` (bucket `ch1-sbp-photos`, also created here)
- `db/payment_milestones.sql` — table, 4-installment seed, RLS
- `db/scope_ext_seed.sql` — façade zone × elevation grid seed (16 cells)

RLS pattern across all tables: client = read-only (SELECT for `authenticated`); admin/internal = full read/write (INSERT/UPDATE/DELETE gated by a `profiles.role IN ('admin','internal')` exists-clause).

### Role-based UI

`afterLogin()` loads the profile, then `showApp()` builds different tab sets:
- **admin / internal** → Dashboard / Update / Report / Photos / Rooms / Log tabs; admin also sees the PDF print button
- **client** → read-only Live Progress dashboard only (`loadClientDashboard()`)

### Dashboard tab (admin/internal, `loadDashboard()` at line ~2353)

Six cards rendered from one batched fetch of `daily_reports`, `floor_progress`, `payment_milestones`:
- `dc-progress-body` — overall % SVG ring + "Day N of 180"
- `dc-pay-body` — payment milestones (paid / current / pending) with progress fill toward each threshold
- `dc-vel-foot` + `dash-vel` canvas — 14-day velocity chart (`renderVelocityChart`)
- `dc-mh-body` — MH burn stats grid
- `dc-stall-body` — stalled floors (no progress in N days)
- `dc-safe-body` — safety hero (LTI / near-miss / etc.)

`skelDash()` writes skeletons into all six containers up front; on error each card swaps to a `renderState` error with a retry button bound to `loadDashboard`.

### Building/floor constants (load-bearing)

```js
BLDG = { M:{floors:33, startFloor:0, endFloor:32, color:'a', label:'Chapter One Shine Bang Pho'} }
TF = 33  // total in-scope floors
flLabel(n)  // 0 → "G" (Ground), else the number
```

Single structure. `floor_no` 0 = Ground (displayed "G"), 1–32 = upper floors. `floor_progress.building` is always `'M'`. The legacy A/B/C 3-building model is gone; `daily_reports.bldg_a_pct` now holds the single-building %, `bldg_b/c_pct` are written 0.

EXT scope grid: facade zones North/East/South/West × elevation bands `G-8 / 9-16 / 17-24 / 25-32` (see `db/scope_ext_seed.sql`). The EXT tab cycles a cell pending→inprogress→complete→defect on tap, then `saveScopeExt()` upserts changed cells.

### Data flow quirks to know

- `loadFloorState()` deliberately prefers the latest report with `floors_complete > 0` over the strict latest — this prevents a 0% save from wiping the UI's floor state. Keep this behavior.
- `calcMH()` auto-calculates MH Today and MH Cumulative from worker counts × hours × working days, writing into hidden `f-mht` / `f-mha` inputs. The previous cumulative is cached in `sessionStorage['prev_mha']` so "today" can add to it. `isHistoricalLoad` guards against recalc when loading a past report into the form.
- Photo upload path: `compressPhoto()` (max 1200px, quality 0.75) → Storage upload with `upsert:true` → `getPublicUrl()` → insert row in `photos` table. Storage paths are namespaced `${PROJECT_ID}/${reportId}/${category}/${index}_${timestamp}.jpg` — the timestamp prevents 409 duplicates on re-upload.
- Photo categories are stored as `initiate` / `progress` / `cleanup` in the DB but keyed as `i` / `p` / `c` in the UI; conversion is inline in the upload/load code.
- Print uses `window.print()` after waiting for photo `<img>` elements to finish loading (see `doPrint()` and `loadAndPrint()`); print CSS hides the form/log/room panes and forces A4 portrait with `-webkit-print-color-adjust:exact` so SVG progress rings render. `doPrint()` uses a `printed` boolean guard so the fallback `setTimeout` never fires a second print dialog.

## Conventions (use these — don't reinvent)

### Forma Design System (CSS custom properties at `:root`)

Hardcoded colors and timings are the wrong move — pull from these tokens instead:

- **Brand:** `--navy` (#302e81), `--navy-dk`, `--navy-dk2`, `--navy-soft`, `--navy-soft2`, `--red` (#ed1b24), `--red-dk`, `--red-soft`
- **Status:** `--green` / `--ga`, `--amber` / `--aa`, `--purple`
- **Surfaces (theme-aware):** `--bg`, `--card`, `--sf`, `--t1`/`--t2`/`--t3` (text), `--bd`, `--inp`, `--inpb`
- **Focus:** `--focus-ring` (apply via `:focus-visible{box-shadow:var(--focus-ring)}`)
- **Transitions:** `--t-fast` (.15s), `--t-base` (.2s), `--t-slow` (.3s)
- **Font scale:** `--fs` / `--fss` / `--fxs`, switched by `[data-font="S|M|L"]` on `<html>`
- **Theme:** `[data-theme="light|dark"]` on `<html>` swaps the surface tokens; charts re-read colors via `gc()` on toggle

### Async UX pattern (used by every loader)

1. **Skeleton first** — render `.skel` / `.skel-line` placeholders into target containers immediately so the layout never blanks (`afterLogin()` calls per-pane skeleton helpers; Dashboard uses `skelDash()`).
2. **Try the fetch.**
3. **On empty** — replace with `renderState(container, {kind:'empty', icon, msg, sub})`.
4. **On error** — `renderState(container, {kind:'error', msg:'…', sub:thaiErr(err), retryFn:loaderFn})` AND `toastErr('❌ '+thaiErr(err))`.

`renderState(container, opts)` is the only inline empty/error renderer (line ~2294). It builds an `.estate` card; if `retryFn` is passed, it wires a "🔄 ลองใหม่" button.

### Error message translation

`thaiErr(err)` (line ~2275) maps Supabase/network errors → Thai user messages by inspecting `err.code` (Postgres codes like `23505`, `23503`, `42501`) and message substrings (`failed to fetch`, `timeout`, `jwt`, `row-level security`, `storage`, `payload too large`, etc.). Always wrap user-facing error strings in `thaiErr(err)` — don't surface raw Postgres messages.

### Toasts

`toast(msg, kind)` / `toastOK(msg)` / `toastErr(msg)` — single `#toast` element, `.t-success` / `.t-error` / `.t-info` variants. Use for transient feedback; use `renderState` for in-pane persistent states.

## Common Tasks

- **Run locally:** open `index.html` directly in a browser (no server needed). Supabase calls hit production.
- **Deploy:** push to the branch Vercel watches. `vercel.json` does the SPA rewrite.
- **Apply DB changes:** open the `.sql` file in Supabase Dashboard → SQL Editor and run. All scripts in `db/` are idempotent.
- **There are no tests, linters, or build steps.** Don't invent them.

## Housekeeping

- `index.html.bak.*` files are local manual backups. Ignored by `.gitignore`.
- `.claude/` (local Claude Code settings) is gitignored.
