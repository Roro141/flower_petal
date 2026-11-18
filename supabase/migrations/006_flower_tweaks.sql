-- Windowsill: the centre picked when tweaking a flower is saved with its petal.
-- Run in the Supabase dashboard: SQL Editor → New query → paste → Run. Safe to run again.
-- (Fullness needs nothing here: it's saved in the petal's points.)

-- Empty for petals planted before this; those keep their owner's usual centre.
alter table public.petals add column if not exists centre text
  check (centre in ('button', 'seeds', 'star', 'cross', 'kraft'));

-- latest_petals is `select *`, which Postgres fixes to the columns there were when
-- the view was made, so make it again to pick up the new column.
create or replace view public.latest_petals with (security_invoker = true) as
  select distinct on (group_id, profile_id) *
  from public.petals
  order by group_id, profile_id, created_at desc;
