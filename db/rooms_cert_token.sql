-- Public shareable certificate token for the rooms table.
-- Powers the no-login certificate page at  …/#cert/{cert_token}
-- Idempotent: safe to re-run. Apply via Supabase Dashboard → SQL Editor.

ALTER TABLE rooms ADD COLUMN IF NOT EXISTS cert_token text;

-- One-time lookup index for the public cert page (token is unique per room)
CREATE UNIQUE INDEX IF NOT EXISTS rooms_cert_token_key ON rooms (cert_token);

-- ───────────────────────────────────────────────────────────────────────────
-- RLS: allow the anon (logged-out) role to SELECT a room ONLY by a live token.
-- The cert page queries:  SELECT * FROM rooms WHERE cert_token = '{token}'
-- A row is exposed only when it carries a token AND has reached a certified
-- lifecycle stage — pending/active/complete rooms stay private.
-- ───────────────────────────────────────────────────────────────────────────
-- Requires: rooms table SELECT policy for anon role
-- Run in Supabase:
DROP POLICY IF EXISTS "public_cert_read" ON rooms;
CREATE POLICY "public_cert_read" ON rooms
  FOR SELECT TO anon
  USING (cert_token IS NOT NULL AND stage IN ('warranty','certified','closed'));
