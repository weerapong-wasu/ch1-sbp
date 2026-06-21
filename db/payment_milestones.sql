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
