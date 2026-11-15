-- Windowsill: accounts, groups and invites.
-- Run in the Supabase dashboard: SQL Editor → New query → paste → Run.
-- Safe to run again. Leaves the spike table (petals_v2) alone; 002_close_spike.sql locks that later.

create extension if not exists pgcrypto;

-- An older test table called "petals" (from before petals_v2) may already exist.
-- Keep it, renamed to petals_v1, so the new petals table can take the name.
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'petals')
     and not exists (select 1 from information_schema.columns
                     where table_schema = 'public' and table_name = 'petals'
                       and column_name = 'group_id' and data_type = 'uuid') then
    alter table public.petals rename to petals_v1;
  end if;
end $$;

-- ── Tables ────────────────────────────────────────────────────────────────

-- One row per person, keyed by their auth user id.
create table if not exists public.profiles (
  id   uuid primary key references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 24)
);

-- A windowsill. The invite code goes in the link: windowsill://join/<invite_code>.
create table if not exists public.groups (
  id          uuid primary key default gen_random_uuid(),
  invite_code text not null unique default encode(gen_random_bytes(6), 'hex'),
  created_at  timestamptz not null default now()
);

-- Who is on which windowsill (2–6 people), and in what order they joined.
create table if not exists public.members (
  group_id   uuid not null references public.groups (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  joined_at  timestamptz not null default now(),
  primary key (group_id, profile_id)
);

-- Cut petals. points = the right half of one petal, [[x, y], ...], normalized 0–1.
create table if not exists public.petals (
  id         bigint generated always as identity primary key,
  profile_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  group_id   uuid not null references public.groups (id) on delete cascade,
  points     jsonb not null,
  pattern    text not null,
  n_petals   int not null check (n_petals between 5 and 8),
  created_at timestamptz not null default now()
);
create index if not exists petals_latest on public.petals (group_id, profile_id, created_at desc);

-- Each member's newest petal. security_invoker: the caller's row-level security applies.
create or replace view public.latest_petals with (security_invoker = true) as
  select distinct on (group_id, profile_id) *
  from public.petals
  order by group_id, profile_id, created_at desc;

-- ── Helpers (security definer, so policies don't recurse into members) ──────

create or replace function public.is_member(g uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from members where group_id = g and profile_id = auth.uid());
$$;

create or replace function public.shares_group(p uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from members mine join members theirs on mine.group_id = theirs.group_id
    where mine.profile_id = auth.uid() and theirs.profile_id = p
  );
$$;

-- ── Row-level security ───────────────────────────────────────────────────

alter table public.profiles enable row level security;
alter table public.groups   enable row level security;
alter table public.members  enable row level security;
alter table public.petals   enable row level security;

drop policy if exists "see yourself and people on your windowsills" on public.profiles;
create policy "see yourself and people on your windowsills" on public.profiles
  for select to authenticated using (id = auth.uid() or public.shares_group(id));
drop policy if exists "create your own profile" on public.profiles;
create policy "create your own profile" on public.profiles
  for insert to authenticated with check (id = auth.uid());
drop policy if exists "rename yourself" on public.profiles;
create policy "rename yourself" on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "see your windowsills" on public.groups;
create policy "see your windowsills" on public.groups
  for select to authenticated using (public.is_member(id));

drop policy if exists "see who is on your windowsills" on public.members;
create policy "see who is on your windowsills" on public.members
  for select to authenticated using (public.is_member(group_id));

drop policy if exists "see petals on your windowsills" on public.petals;
create policy "see petals on your windowsills" on public.petals
  for select to authenticated using (public.is_member(group_id));
drop policy if exists "plant on your windowsills" on public.petals;
create policy "plant on your windowsills" on public.petals
  for insert to authenticated with check (profile_id = auth.uid() and public.is_member(group_id));

-- Groups and members are only ever written through these two functions.

-- Starts a new windowsill with you on it.
create or replace function public.create_group() returns public.groups
language plpgsql security definer set search_path = public as $$
declare g groups;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  insert into groups default values returning * into g;
  insert into members (group_id, profile_id) values (g.id, auth.uid());
  return g;
end $$;

-- Joins the windowsill with this invite code (at most 6 people).
create or replace function public.join_group(code text) returns public.groups
language plpgsql security definer set search_path = public as $$
declare g groups;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into g from groups where invite_code = code;
  if not found then raise exception 'no windowsill with that code'; end if;
  if not exists (select 1 from members where group_id = g.id and profile_id = auth.uid()) then
    if (select count(*) from members where group_id = g.id) >= 6 then
      raise exception 'that windowsill is full';
    end if;
    insert into members (group_id, profile_id) values (g.id, auth.uid());
  end if;
  return g;
end $$;

revoke execute on function public.create_group(), public.join_group(text),
                           public.is_member(uuid), public.shares_group(uuid) from public, anon;
grant execute on function public.create_group(), public.join_group(text),
                          public.is_member(uuid), public.shares_group(uuid) to authenticated;
