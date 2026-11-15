-- Windowsill: lock the spike table once the new app (accounts and groups) works.
-- Run in the Supabase dashboard: SQL Editor → New query → paste → Run.
-- Removes every policy on petals_v2 (the open test ones) and anonymous access to it.
-- Row-level security stays on, so with no policies nobody can read or write it.

do $$
declare p record;
begin
  for p in select policyname from pg_policies where schemaname = 'public' and tablename = 'petals_v2' loop
    execute format('drop policy %I on public.petals_v2', p.policyname);
  end loop;
end $$;

alter table public.petals_v2 enable row level security;
revoke all on public.petals_v2 from anon, authenticated;
revoke all on public.latest_petals_v2 from anon, authenticated;
