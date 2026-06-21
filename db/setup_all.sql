-- ════════════════════════════════════════════════════════════════════
-- CH1-SBP — ONE-SHOT SETUP (all 5 db/*.sql files, in run order)
-- Project: wvihzrdokwpjeneycppv · paste whole file into Supabase SQL Editor → Run
-- Order: schema → rls_photos → payment_milestones → evm_baseline → scope_ext_seed
-- Idempotent: safe to re-run.
-- ════════════════════════════════════════════════════════════════════


-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  FILE 1/5 : schema.sql                                            ║
-- ╚══════════════════════════════════════════════════════════════════╝

-- ════════════════════════════════════════════════════════════════════
-- Chapter One Shine Bang Pho (CH1-SBP) — CORE SCHEMA
-- Supabase project: wvihzrdokwpjeneycppv
-- Run in: Supabase Dashboard → SQL Editor (run this FIRST, before the
--          other db/*.sql seed files).
--
-- Creates every table the app reads/writes, seeds the project row
-- (code = 'CH1-SBP-2026'), and applies RLS:
--   client          = read-only (SELECT for authenticated)
--   admin / internal = full read/write
--
-- Safe to re-run: tables use IF NOT EXISTS, columns ADD ... IF NOT EXISTS,
--                 seeds ON CONFLICT DO NOTHING, every policy DROPped first.
-- ════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════════
-- profiles — one row per auth user, carries the role
-- ════════════════════════════════════════════════════════════════════
create table if not exists public.profiles (
  id          uuid        primary key references auth.users(id) on delete cascade,
  email       text,
  full_name   text,
  role        text        not null default 'client'
                          check (role in ('admin','internal','client')),
  created_at  timestamptz not null default now()
);

-- auto-create a profile (role 'client' = read-only) on signup.
-- Promote real staff with:  update public.profiles set role='internal' where email='...';
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, role)
  values (new.id, new.email, 'client')
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ─── helper: is the current user admin/internal? ────────────────────
-- Defined after profiles exists (language sql validates its body at
-- creation). SECURITY DEFINER so the check itself is not gated by
-- profiles RLS — prevents recursive policy evaluation.
create or replace function public.is_internal()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role in ('admin','internal')
  );
$$;

alter table public.profiles enable row level security;
drop policy if exists "profiles_read_authed"  on public.profiles;
drop policy if exists "profiles_update_own"    on public.profiles;
drop policy if exists "profiles_update_admin"  on public.profiles;
-- read: any authenticated user (needed for role lookups + user display)
create policy "profiles_read_authed" on public.profiles
  for select to authenticated using (true);
-- update: a user may edit their own row (name); admins may edit anyone
create policy "profiles_update_own" on public.profiles
  for update to authenticated using (id = auth.uid());

-- ════════════════════════════════════════════════════════════════════
-- projects — looked up by code to resolve PROJECT_ID
-- ════════════════════════════════════════════════════════════════════
create table if not exists public.projects (
  id              uuid          primary key default gen_random_uuid(),
  code            text          not null unique,
  name            text          not null,
  contract_no     text,
  contract_value  numeric(14,2),
  total_days      int,
  start_date      date,
  created_at      timestamptz   not null default now()
);

insert into public.projects (code, name, contract_no, contract_value, total_days, start_date)
values (
  'CH1-SBP-2026',
  'Chapter One Shine Bang Pho',
  'CH1-SBP/FORMA/001/2569',
  6500000.00,
  180,
  '2026-04-01'
)
on conflict (code) do nothing;

alter table public.projects enable row level security;
drop policy if exists "projects_read_authed"   on public.projects;
drop policy if exists "projects_write_internal" on public.projects;
create policy "projects_read_authed" on public.projects
  for select to authenticated using (true);
create policy "projects_write_internal" on public.projects
  for all to authenticated using (public.is_internal()) with check (public.is_internal());

-- ════════════════════════════════════════════════════════════════════
-- daily_reports — one row per (project_id, report_date), upserted
-- ════════════════════════════════════════════════════════════════════
create table if not exists public.daily_reports (
  id                uuid          primary key default gen_random_uuid(),
  project_id        uuid          not null references public.projects(id) on delete cascade,
  report_date       date          not null,
  day_no            int,
  -- scope discriminator (EXT facade · INT interior · both). Not part of the
  -- unique key: one consolidated report per day still covers both scopes.
  scope             text          not null default 'both'
                                  check (scope in ('ext','int','both')),
  weather           text,
  temp_celsius      numeric(5,2),
  rain_hours        numeric(5,2),
  direct_workers    int           default 0,
  indirect_workers  int           default 0,
  mh_today          int           default 0,
  mh_cumulative     int           default 0,
  lti_count         int           default 0,
  near_miss_count   int           default 0,
  overall_pct       numeric(6,2)  default 0,
  bldg_a_pct        numeric(6,2)  default 0,
  bldg_b_pct        numeric(6,2)  default 0,
  bldg_c_pct        numeric(6,2)  default 0,
  floors_complete   int           default 0,
  floors_active     int           default 0,
  concern_1_title   text,
  concern_1_action  text,
  concern_2_title   text,
  concern_2_action  text,
  next_working_date date,
  priority_1        text,
  priority_2        text,
  created_by        uuid          references public.profiles(id),
  created_at        timestamptz   not null default now(),
  unique (project_id, report_date)
);
create index if not exists idx_daily_reports_project_date
  on public.daily_reports (project_id, report_date desc);

alter table public.daily_reports enable row level security;
drop policy if exists "dr_read_authed"    on public.daily_reports;
drop policy if exists "dr_write_internal" on public.daily_reports;
create policy "dr_read_authed" on public.daily_reports
  for select to authenticated using (true);
create policy "dr_write_internal" on public.daily_reports
  for all to authenticated using (public.is_internal()) with check (public.is_internal());

-- ════════════════════════════════════════════════════════════════════
-- floor_progress — child of daily_reports, one row per floor
-- building = 'M' (single structure), floor_no 0 = Ground .. 32
-- ════════════════════════════════════════════════════════════════════
create table if not exists public.floor_progress (
  id              uuid          primary key default gen_random_uuid(),
  report_id       uuid          not null references public.daily_reports(id) on delete cascade,
  project_id      uuid          not null references public.projects(id) on delete cascade,
  building        text          not null default 'M',
  floor_no        int           not null,
  pct             numeric(6,2)  not null default 0,
  completed_date  date,
  created_at      timestamptz   not null default now(),
  unique (report_id, building, floor_no)
);
create index if not exists idx_floor_progress_report
  on public.floor_progress (report_id);

alter table public.floor_progress enable row level security;
drop policy if exists "fp_read_authed"    on public.floor_progress;
drop policy if exists "fp_write_internal" on public.floor_progress;
create policy "fp_read_authed" on public.floor_progress
  for select to authenticated using (true);
create policy "fp_write_internal" on public.floor_progress
  for all to authenticated using (public.is_internal()) with check (public.is_internal());

-- ════════════════════════════════════════════════════════════════════
-- photos — metadata; files live in Storage bucket 'ch1-sbp-photos'
-- category: initiate | progress | cleanup
-- ════════════════════════════════════════════════════════════════════
create table if not exists public.photos (
  id             uuid         primary key default gen_random_uuid(),
  report_id      uuid         references public.daily_reports(id) on delete cascade,
  project_id     uuid         references public.projects(id) on delete cascade,
  category       text         not null
                              check (category in ('initiate','progress','cleanup')),
  storage_path   text,
  public_url     text,
  caption        text         default '',
  display_order  int          default 0,
  created_at     timestamptz  not null default now()
);
create index if not exists idx_photos_report on public.photos (report_id, display_order);
-- RLS for this table lives in db/rls_photos.sql (run that after this file).

-- ════════════════════════════════════════════════════════════════════
-- audit_logs — written on every report save / baseline lock
-- ════════════════════════════════════════════════════════════════════
create table if not exists public.audit_logs (
  id          uuid         primary key default gen_random_uuid(),
  user_id     uuid         references public.profiles(id),
  action      text,
  table_name  text,
  record_id   uuid,
  summary     text,
  created_at  timestamptz  not null default now()
);
create index if not exists idx_audit_logs_created on public.audit_logs (created_at desc);

alter table public.audit_logs enable row level security;
drop policy if exists "audit_read_internal"  on public.audit_logs;
drop policy if exists "audit_write_authed"   on public.audit_logs;
create policy "audit_read_internal" on public.audit_logs
  for select to authenticated using (public.is_internal());
create policy "audit_write_authed" on public.audit_logs
  for insert to authenticated with check (auth.uid() is not null);

-- ════════════════════════════════════════════════════════════════════
-- rooms — INT scope: room-by-room tracking, one row per room
-- scope: 'int' (interior renovation) | 'ext' (facade) — defaults 'int'
-- status: pending | inprogress | complete | defect
-- stage lifecycle: pending → active → complete → certified → warranty → closed
-- ════════════════════════════════════════════════════════════════════
create table if not exists public.rooms (
  id                     uuid         primary key default gen_random_uuid(),
  project_id             uuid         not null references public.projects(id) on delete cascade,
  room_no                text         not null,
  building               text,
  floor_ref              text,
  scope                  text         default 'int',
  status                 text         not null default 'pending'
                                      check (status in ('pending','inprogress','complete','defect')),
  stage                  text         default 'pending',
  note                   text,
  completed_date         date,
  -- certificate + warranty (see db/rooms_warranty.sql / rooms_cert_token.sql)
  certificate_ref        text,
  certificate_issued_at  timestamptz,
  warranty_start_date    date,
  warranty_expiry_date   date,
  cert_token             text,
  created_by             uuid         references public.profiles(id),
  updated_by             uuid         references public.profiles(id),
  created_at             timestamptz  not null default now()
);
create unique index if not exists rooms_cert_token_key on public.rooms (cert_token);

alter table public.rooms enable row level security;
drop policy if exists "rooms_read_authed"    on public.rooms;
drop policy if exists "rooms_write_internal" on public.rooms;
drop policy if exists "public_cert_read"     on public.rooms;
create policy "rooms_read_authed" on public.rooms
  for select to authenticated using (true);
create policy "rooms_write_internal" on public.rooms
  for all to authenticated using (public.is_internal()) with check (public.is_internal());
-- public (logged-out) cert page: expose a room only by a live token at a
-- certified/warranty/closed stage. Mirrors db/rooms_cert_token.sql.
create policy "public_cert_read" on public.rooms
  for select to anon
  using (cert_token is not null and stage in ('warranty','certified','closed'));

-- ════════════════════════════════════════════════════════════════════
-- scope_ext — EXT scope: rope-access facade tracking by Zone × Elevation
-- zone: facade (North/East/South/West); elevation: floor band (e.g. 'G-8')
-- status: pending | inprogress | complete | defect
-- ════════════════════════════════════════════════════════════════════
create table if not exists public.scope_ext (
  id           uuid         primary key default gen_random_uuid(),
  project_id   uuid         not null references public.projects(id) on delete cascade,
  zone         text         not null,
  elevation    text         not null,
  status       text         not null default 'pending'
                            check (status in ('pending','inprogress','complete','defect')),
  pct          numeric(6,2) not null default 0,
  method       text         default 'rope-access',
  note         text,
  photo_urls   jsonb        not null default '[]'::jsonb,
  updated_by   uuid         references public.profiles(id),
  created_at   timestamptz  not null default now(),
  updated_at   timestamptz  not null default now(),
  unique (project_id, zone, elevation)
);
create index if not exists idx_scope_ext_project on public.scope_ext (project_id);

alter table public.scope_ext enable row level security;
drop policy if exists "sx_read_authed"    on public.scope_ext;
drop policy if exists "sx_write_internal" on public.scope_ext;
create policy "sx_read_authed" on public.scope_ext
  for select to authenticated using (true);
create policy "sx_write_internal" on public.scope_ext
  for all to authenticated using (public.is_internal()) with check (public.is_internal());

-- ─── next steps ─────────────────────────────────────────────────────
-- 1. Run db/rls_photos.sql        (photos + storage bucket policies)
-- 2. Run db/payment_milestones.sql (4-installment seed)
-- 3. Run db/evm_baseline.sql       (EVM R3 baseline)
-- 4. Run db/scope_ext_seed.sql     (facade zone × elevation grid seed)
-- 5. Create your auth users, then promote staff:
--      update public.profiles set role='internal' where email='you@forma...';
--      update public.profiles set role='admin'    where email='admin@forma...';


-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  FILE 2/5 : rls_photos.sql                                        ║
-- ╚══════════════════════════════════════════════════════════════════╝

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


-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  FILE 3/5 : payment_milestones.sql                                ║
-- ╚══════════════════════════════════════════════════════════════════╝

-- ════════════════════════════════════════════════════════════════════
-- Chapter One Shine Bang Pho — Payment Milestones (table + seed + RLS)
-- Run in: Supabase Dashboard → SQL Editor (after db/schema.sql)
-- Effect:  creates public.payment_milestones, seeds 4 CH1-SBP
--          installments, applies RLS (client = read-only,
--          admin / internal = full read/write).
-- Safe to re-run: table uses IF NOT EXISTS, seed uses ON CONFLICT,
--                 every policy is dropped first.
-- ════════════════════════════════════════════════════════════════════

-- ─── table ──────────────────────────────────────────────────────────
create table if not exists public.payment_milestones (
  id              uuid          primary key default gen_random_uuid(),
  project_id      uuid          not null references public.projects(id) on delete cascade,
  milestone_no    int           not null,
  milestone_name  text          not null,
  threshold_pct   numeric(5,2)  not null,
  amount          numeric(14,2),
  status          text          not null default 'pending'
                                check (status in ('pending','invoiced','paid')),
  paid_date       date,
  created_at      timestamptz   not null default now(),
  unique (project_id, milestone_no)
);

create index if not exists idx_payment_milestones_project
  on public.payment_milestones (project_id, milestone_no);

-- ─── seed: CH1-SBP 4 installments ───────────────────────────────────
-- Source: contract CH1-SBP/FORMA/001/2569
-- Total contract value: 6,500,000.00 THB
-- ⚠️ Thresholds/amounts below are a sensible default that sums to the
--    contract value — CONFIRM against the signed payment schedule and
--    adjust the VALUES rows if the contract differs.
insert into public.payment_milestones
  (project_id, milestone_no, milestone_name, threshold_pct, amount, status)
select p.id, v.milestone_no, v.milestone_name, v.threshold_pct, v.amount, 'pending'
from public.projects p
cross join (values
  (1, 'ลงนามสัญญา / เงินล่วงหน้า',   0.00,  1300000.00),
  (2, 'ดำเนินงานเสร็จ 40%',          40.00,  1950000.00),
  (3, 'ดำเนินงานเสร็จ 75%',          75.00,  1950000.00),
  (4, 'เสร็จ 100% + ส่งมอบ',        100.00,  1300000.00)
) as v(milestone_no, milestone_name, threshold_pct, amount)
where p.code = 'CH1-SBP-2026'
on conflict (project_id, milestone_no) do nothing;

-- ─── RLS ────────────────────────────────────────────────────────────
alter table public.payment_milestones enable row level security;

drop policy if exists "pm_read_authed"      on public.payment_milestones;
drop policy if exists "pm_write_internal"   on public.payment_milestones;
drop policy if exists "pm_update_internal"  on public.payment_milestones;
drop policy if exists "pm_delete_internal"  on public.payment_milestones;

create policy "pm_read_authed"
  on public.payment_milestones for select
  to authenticated
  using (true);

create policy "pm_write_internal"
  on public.payment_milestones for insert
  to authenticated
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role in ('admin','internal')
    )
  );

create policy "pm_update_internal"
  on public.payment_milestones for update
  to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role in ('admin','internal')
    )
  );

create policy "pm_delete_internal"
  on public.payment_milestones for delete
  to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role in ('admin','internal')
    )
  );

-- ─── verify ─────────────────────────────────────────────────────────
-- select milestone_no, milestone_name, threshold_pct, amount, status
-- from public.payment_milestones
-- order by milestone_no;
--
-- select schemaname, tablename, policyname, cmd, roles
-- from pg_policies
-- where tablename = 'payment_milestones'
-- order by policyname;


-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  FILE 4/5 : evm_baseline.sql                                      ║
-- ╚══════════════════════════════════════════════════════════════════╝

-- ════════════════════════════════════════════════════════════════════
-- Chapter One Shine Bang Pho — EVM Baseline (table + seed R3 + RLS)
-- Run in: Supabase Dashboard → SQL Editor (after db/schema.sql)
-- Effect:  creates public.evm_baseline (immutable revisions of the
--          earned-value baseline), seeds the initial R3 row from the
--          existing Master Schedule, applies RLS (client = read,
--          admin / internal = insert only — no UPDATE / DELETE).
-- Safe to re-run: table uses IF NOT EXISTS, seed uses ON CONFLICT,
--                 every policy is dropped first.
-- ════════════════════════════════════════════════════════════════════

-- ─── table ──────────────────────────────────────────────────────────
create table if not exists public.evm_baseline (
  id              uuid          primary key default gen_random_uuid(),
  project_id      uuid          not null references public.projects(id) on delete cascade,
  revision        text          not null,
  plan_day_array  jsonb         not null,
  plan_pct_array  jsonb         not null,
  bac_thb         numeric(14,2) not null,
  note            text,
  locked_at       timestamptz   not null default now(),
  locked_by       uuid          references public.profiles(id),
  created_at      timestamptz   not null default now(),
  unique (project_id, revision)
);

create index if not exists idx_evm_baseline_project_locked
  on public.evm_baseline (project_id, locked_at desc);

-- ─── seed: Chapter One R3 baseline ──────────────────────────────────
-- Source: Master Schedule R3 + Contract CH1-SBP/FORMA/001/2569
-- Total contract value: 6,500,000.00 THB · 180 working days
insert into public.evm_baseline
  (project_id, revision, plan_day_array, plan_pct_array, bac_thb, note, locked_at)
select p.id,
       'R3',
       '[1,20,40,60,90,120,150,180]'::jsonb,
       '[0,10,32,44,58,72,87,100]'::jsonb,
       6500000.00,
       'Initial baseline imported from Master Schedule R3.',
       now()
from public.projects p
where p.code = 'CH1-SBP-2026'
on conflict (project_id, revision) do nothing;

-- ─── audit trigger: write each new baseline to audit_logs ───────────
create or replace function public.audit_evm_baseline()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.audit_logs (user_id, action, table_name, record_id, summary)
  values (
    coalesce(new.locked_by, auth.uid()),
    'create',
    'evm_baseline',
    new.id,
    'EVM Baseline ' || new.revision || ' locked · BAC=' || new.bac_thb || ' THB'
  );
  return new;
exception when others then
  -- never block baseline insert if audit_logs is unavailable
  return new;
end;
$$;

drop trigger if exists trg_audit_evm_baseline on public.evm_baseline;
create trigger trg_audit_evm_baseline
  after insert on public.evm_baseline
  for each row execute function public.audit_evm_baseline();

-- ─── RLS ────────────────────────────────────────────────────────────
alter table public.evm_baseline enable row level security;

drop policy if exists "evm_read_authed"     on public.evm_baseline;
drop policy if exists "evm_insert_internal" on public.evm_baseline;
drop policy if exists "evm_update_block"    on public.evm_baseline;
drop policy if exists "evm_delete_block"    on public.evm_baseline;

-- read: every authenticated role can read the baseline (client included)
create policy "evm_read_authed"
  on public.evm_baseline for select
  to authenticated
  using (true);

-- insert: admin / internal only
create policy "evm_insert_internal"
  on public.evm_baseline for insert
  to authenticated
  with check (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role in ('admin','internal')
    )
  );

-- update / delete: NOBODY — baseline is immutable. New revision = new row.
create policy "evm_update_block"
  on public.evm_baseline for update
  to authenticated
  using (false);

create policy "evm_delete_block"
  on public.evm_baseline for delete
  to authenticated
  using (false);

-- ─── verify ─────────────────────────────────────────────────────────
-- select revision, plan_day_array, plan_pct_array, bac_thb, locked_at
-- from public.evm_baseline
-- order by locked_at desc;
--
-- select schemaname, tablename, policyname, cmd, roles
-- from pg_policies
-- where tablename = 'evm_baseline'
-- order by policyname;


-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  FILE 5/5 : scope_ext_seed.sql                                    ║
-- ╚══════════════════════════════════════════════════════════════════╝

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

