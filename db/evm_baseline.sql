-- ════════════════════════════════════════════════════════════════════
-- Chapter One Progress — EVM Baseline (table + seed R3 + RLS)
-- Run in: Supabase Dashboard → SQL Editor
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
-- Source: Master Schedule R3 + Contract PS-CH-RBN:P/FORMA/001/2569
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
where p.code = 'CHAPTER-ONE-2026'
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
