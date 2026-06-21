-- ════════════════════════════════════════════════════════════════════
-- Chapter One Shine Bang Pho — EXT scope grid seed
-- Run in: Supabase Dashboard → SQL Editor (after db/schema.sql)
-- Effect:  seeds the rope-access facade grid into public.scope_ext —
--          4 facade zones × 4 elevation bands = 16 cells, all 'pending'.
-- Safe to re-run: ON CONFLICT (project_id, zone, elevation) DO NOTHING.
--
-- EXT scope = crack repair + repaint facade, by Rope Access (โรยตัว).
-- Zones: facade orientation. Elevation: floor band over Ground..32.
-- Adjust the VALUES grid to match the building's real facade layout.
-- ════════════════════════════════════════════════════════════════════
insert into public.scope_ext (project_id, zone, elevation, status, method)
select p.id, v.zone, v.elevation, 'pending', 'rope-access'
from public.projects p
cross join (values
  ('North','G-8'),  ('North','9-16'),  ('North','17-24'),  ('North','25-32'),
  ('East', 'G-8'),  ('East', '9-16'),  ('East', '17-24'),  ('East', '25-32'),
  ('South','G-8'),  ('South','9-16'),  ('South','17-24'),  ('South','25-32'),
  ('West', 'G-8'),  ('West', '9-16'),  ('West', '17-24'),  ('West', '25-32')
) as v(zone, elevation)
where p.code = 'CH1-SBP-2026'
on conflict (project_id, zone, elevation) do nothing;

-- ─── verify ─────────────────────────────────────────────────────────
-- select zone, elevation, status, pct from public.scope_ext
-- order by zone, elevation;
