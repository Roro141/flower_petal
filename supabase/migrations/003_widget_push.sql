-- Windowsill: widget push tokens, so a friend's new petal can nudge your widget.
-- Run in the Supabase dashboard: SQL Editor → New query → paste → Run. Safe to run again.

-- An older widget_tokens table from the spike (token, profile_id, updated_at) may
-- already exist. Keep it, renamed to widget_tokens_v1, so the new one can take the name.
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'widget_tokens')
     and not exists (select 1 from information_schema.columns
                     where table_schema = 'public' and table_name = 'widget_tokens' and column_name = 'environment') then
    alter table public.widget_tokens rename to widget_tokens_v1;
  end if;
  -- The old table may still have the spike's open policies; nobody needs it now.
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'widget_tokens_v1') then
    execute 'revoke all on public.widget_tokens_v1 from anon, authenticated';
  end if;
end $$;

-- One row per phone (a widget push token), owned by whoever is signed in on it.
-- environment: 'development' for builds from Xcode, 'production' for App Store builds;
-- they go to different Apple push servers.
create table if not exists public.widget_tokens (
  token       text primary key,
  profile_id  uuid not null references public.profiles (id) on delete cascade,
  environment text not null default 'development' check (environment in ('development', 'production')),
  updated_at  timestamptz not null default now()
);

-- Nobody reads or writes this table directly; the app saves tokens through the
-- function below and the push function reads them with the service role.
alter table public.widget_tokens enable row level security;

-- Saves this phone's token for whoever is signed in. If someone else used to be
-- signed in on the phone, the token moves to the new person.
create or replace function public.save_widget_token(token text, environment text)
returns void language plpgsql security definer set search_path = public as $$
-- Bare "token"/"environment" mean the table's columns; the arguments are written
-- save_widget_token.token / save_widget_token.environment.
#variable_conflict use_column
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  insert into widget_tokens (token, profile_id, environment, updated_at)
  values (save_widget_token.token, auth.uid(), save_widget_token.environment, now())
  on conflict (token) do update
    set profile_id = auth.uid(), environment = excluded.environment, updated_at = now();
end $$;

revoke execute on function public.save_widget_token(text, text) from public, anon;
grant execute on function public.save_widget_token(text, text) to authenticated;
