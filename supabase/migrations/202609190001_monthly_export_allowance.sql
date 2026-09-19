-- Three account-bound full-story exports per calendar month.
-- Claims are server-side and idempotent per story so reinstalling the app or
-- tapping twice cannot create extra credits or spend two credits.

create table public.monthly_export_claims (
  user_id uuid not null references auth.users(id) on delete cascade,
  month_start date not null,
  story_id text not null check (char_length(story_id) between 1 and 512),
  claimed_at timestamptz not null default now(),
  primary key (user_id, month_start, story_id)
);

create index monthly_export_claims_user_month_idx
on public.monthly_export_claims (user_id, month_start, claimed_at);

alter table public.monthly_export_claims enable row level security;

grant select on table public.monthly_export_claims to authenticated;
grant select, insert, update, delete on table public.monthly_export_claims to service_role;
revoke all on table public.monthly_export_claims from anon;

create policy "monthly_export_claims_select_own"
on public.monthly_export_claims for select to authenticated
using ((select auth.uid()) = user_id);

create or replace function public.monthly_export_allowance()
returns table ("limit" integer, used integer, remaining integer)
language sql
stable
security definer
set search_path = ''
as $$
  select
    3 as "limit",
    count(*)::integer as used,
    greatest(0, 3 - count(*)::integer) as remaining
  from public.monthly_export_claims
  where user_id = (select auth.uid())
    and month_start = date_trunc('month', current_date)::date;
$$;

create or replace function public.claim_monthly_export(p_story_id text)
returns table (allowed boolean, remaining integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  current_month date := date_trunc('month', current_date)::date;
  existing_claim boolean;
  used_count integer;
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  if p_story_id is null or char_length(p_story_id) not between 1 and 512 then
    raise exception 'Invalid story identifier';
  end if;

  -- Serialize claims for this user and month to enforce the three-credit cap.
  perform pg_advisory_xact_lock(
    hashtextextended(current_user_id::text || ':' || current_month::text, 0)
  );

  select exists (
    select 1
    from public.monthly_export_claims
    where user_id = current_user_id
      and month_start = current_month
      and story_id = p_story_id
  ) into existing_claim;

  select count(*)::integer
  into used_count
  from public.monthly_export_claims
  where user_id = current_user_id
    and month_start = current_month;

  if existing_claim then
    return query select true, greatest(0, 3 - used_count);
    return;
  end if;

  if used_count >= 3 then
    return query select false, 0;
    return;
  end if;

  insert into public.monthly_export_claims (user_id, month_start, story_id)
  values (current_user_id, current_month, p_story_id);

  return query select true, greatest(0, 2 - used_count);
end;
$$;

revoke all on function public.monthly_export_allowance() from public, anon;
revoke all on function public.claim_monthly_export(text) from public, anon;
grant execute on function public.monthly_export_allowance() to authenticated;
grant execute on function public.claim_monthly_export(text) to authenticated;
grant execute on function public.monthly_export_allowance() to service_role;
grant execute on function public.claim_monthly_export(text) to service_role;

