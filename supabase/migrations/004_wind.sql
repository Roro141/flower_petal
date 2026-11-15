-- Windowsill: wind. A few times a day, at random, a gust blows through each windowsill.
-- Run in the Supabase dashboard: SQL Editor → New query → paste → Run. Safe to run again.
-- Needs the Cron integration (pg_cron); this turns it on if it isn't already.

-- One row per gust. seed decides everything about it (who loses a petal, which one,
-- where it lands), so every phone shows the same gust.
create table if not exists public.gusts (
  id         bigint generated always as identity primary key,
  group_id   uuid not null references public.groups (id) on delete cascade,
  seed       int not null,
  created_at timestamptz not null default now()
);
create index if not exists gusts_latest on public.gusts (group_id, created_at desc);

alter table public.gusts enable row level security;
drop policy if exists "see gusts on your windowsills" on public.gusts;
create policy "see gusts on your windowsills" on public.gusts
  for select to authenticated using (public.is_member(group_id));

-- Every 30 minutes each windowsill has a 7.5% chance of a gust: about 3–4 a day, at random.
create or replace function public.maybe_gust() returns void
language sql security definer set search_path = public as $$
  insert into gusts (group_id, seed)
  select id, floor(random() * 2147483647)::int from groups where random() < 0.075;
$$;
revoke execute on function public.maybe_gust() from public, anon, authenticated;

create extension if not exists pg_cron;
select cron.schedule('windowsill-gusts', '*/30 * * * *', 'select public.maybe_gust()');

-- TEMPORARY, for testing: blows a gust through your own windowsill right now.
-- The app calls it on a long press of the window in builds from Xcode. Remove before real use.
create or replace function public.test_gust() returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  insert into gusts (group_id, seed)
  select group_id, floor(random() * 2147483647)::int
  from members where profile_id = auth.uid() order by joined_at desc limit 1;
end $$;
revoke execute on function public.test_gust() from public, anon;
grant execute on function public.test_gust() to authenticated;
