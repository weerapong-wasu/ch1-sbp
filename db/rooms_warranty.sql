-- Certificate + Warranty tracking columns for the rooms table.
-- Idempotent: safe to re-run. Apply via Supabase Dashboard → SQL Editor.

ALTER TABLE rooms ADD COLUMN IF NOT EXISTS certificate_ref       text;
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS certificate_issued_at timestamptz;
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS warranty_start_date   date;
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS warranty_expiry_date  date;

-- stage lifecycle: pending → active → complete → certified → warranty → closed
-- (certificate issuance auto-advances complete → warranty in one write; rlAutoClose() moves
--  warranty → closed once warranty_expiry_date < today)
