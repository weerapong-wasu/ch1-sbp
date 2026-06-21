-- ════════════════════════════════════════════════════════════════════
-- Chapter One Shine Bang Pho — Photos RLS policies + storage bucket
-- Run in: Supabase Dashboard → SQL Editor (after db/schema.sql)
-- Effect:  client = read-only.   admin / internal = full read/write.
-- Safe to re-run: every policy is dropped first.
-- ════════════════════════════════════════════════════════════════════

-- ─── storage bucket: ch1-sbp-photos (public read for getPublicUrl) ──
insert into storage.buckets (id, name, public)
values ('ch1-sbp-photos', 'ch1-sbp-photos', true)
on conflict (id) do nothing;

-- ─── photos table ───────────────────────────────────────────────────
alter table public.photos enable row level security;

drop policy if exists "photos_read_authed"     on public.photos;
drop policy if exists "photos_write_internal"  on public.photos;
drop policy if exists "photos_update_internal" on public.photos;
drop policy if exists "photos_delete_internal" on public.photos;

create policy "photos_read_authed"
  on public.photos for select
  to authenticated
  using (true);

create policy "photos_write_internal"
  on public.photos for insert
  to authenticated
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role in ('admin','internal')
    )
  );

create policy "photos_update_internal"
  on public.photos for update
  to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role in ('admin','internal')
    )
  );

create policy "photos_delete_internal"
  on public.photos for delete
  to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role in ('admin','internal')
    )
  );

-- ─── storage.objects (bucket: ch1-sbp-photos) ───────────────────
-- Note: storage policies must be created with sufficient privilege.
-- If running as non-superuser fails, use the Storage UI:
--   Storage → ch1-sbp-photos → Policies → New policy.

drop policy if exists "ph_obj_read"   on storage.objects;
drop policy if exists "ph_obj_write"  on storage.objects;
drop policy if exists "ph_obj_update" on storage.objects;
drop policy if exists "ph_obj_delete" on storage.objects;

create policy "ph_obj_read"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'ch1-sbp-photos');

create policy "ph_obj_write"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'ch1-sbp-photos'
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role in ('admin','internal')
    )
  );

create policy "ph_obj_update"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'ch1-sbp-photos'
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role in ('admin','internal')
    )
  );

create policy "ph_obj_delete"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'ch1-sbp-photos'
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role in ('admin','internal')
    )
  );

-- ─── verify ─────────────────────────────────────────────────────────
-- select schemaname, tablename, policyname, cmd, roles
-- from pg_policies
-- where tablename in ('photos','objects')
-- order by tablename, policyname;
