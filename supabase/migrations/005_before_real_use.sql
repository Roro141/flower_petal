-- Windowsill: clean up the testing leftovers before real use.
-- Run in the Supabase dashboard: SQL Editor → New query → paste → Run. Safe to run again.

-- The test gust the app used to blow on a long press.
drop function if exists public.test_gust();

-- Every anonymous ("try without apple") test account. Deleting the auth user also
-- deletes its profile, memberships, petals and widget tokens (they cascade).
-- Accounts made with Sign in with Apple are not anonymous, so they stay.
delete from auth.users where is_anonymous;

-- Windowsills nobody is on any more (their gusts go with them).
delete from public.groups g
where not exists (select 1 from public.members m where m.group_id = g.id);
