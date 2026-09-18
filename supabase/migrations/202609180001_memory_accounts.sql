-- Memories accounts and temporary share links.
-- Run through Supabase migrations or paste once into the SQL Editor.

create extension if not exists pgcrypto;

-- Keep privileged trigger functions outside the Data API's exposed schemas.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

grant select, insert, update, delete on table public.profiles to authenticated;
grant select, insert, update, delete on table public.profiles to service_role;
revoke all on table public.profiles from anon;

create policy "profiles_select_own"
on public.profiles for select to authenticated
using ((select auth.uid()) = id);

create policy "profiles_update_own"
on public.profiles for update to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

create or replace function private.handle_new_memories_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke all on function private.handle_new_memories_user() from public, anon, authenticated;

create trigger on_memories_auth_user_created
after insert on auth.users
for each row execute procedure private.handle_new_memories_user();

create table public.memories (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 160),
  duration_seconds double precision not null default 0 check (duration_seconds >= 0),
  export_tier text not null check (export_tier in ('free', 'story_pass')),
  storage_path text not null unique,
  share_token uuid not null unique default gen_random_uuid(),
  share_enabled boolean not null default true,
  saved_to_phone_at timestamptz,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days'),
  constraint memory_expiry_after_creation check (expires_at > created_at)
);

create index memories_owner_created_idx
on public.memories (owner_id, created_at desc);

create index memories_expiry_idx
on public.memories (expires_at)
where share_enabled;

alter table public.memories enable row level security;

grant select, insert, update, delete on table public.memories to authenticated;
grant select, insert, update, delete on table public.memories to service_role;
revoke all on table public.memories from anon;

create policy "memories_select_own"
on public.memories for select to authenticated
using ((select auth.uid()) = owner_id);

create policy "memories_insert_own"
on public.memories for insert to authenticated
with check ((select auth.uid()) = owner_id);

create policy "memories_update_own"
on public.memories for update to authenticated
using ((select auth.uid()) = owner_id)
with check ((select auth.uid()) = owner_id);

create policy "memories_delete_own"
on public.memories for delete to authenticated
using ((select auth.uid()) = owner_id);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'memory-exports',
  'memory-exports',
  false,
  262144000,
  array['video/mp4']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "memory_exports_insert_own_folder"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'memory-exports'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "memory_exports_select_own"
on storage.objects for select to authenticated
using (
  bucket_id = 'memory-exports'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "memory_exports_update_own"
on storage.objects for update to authenticated
using (
  bucket_id = 'memory-exports'
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'memory-exports'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "memory_exports_delete_own"
on storage.objects for delete to authenticated
using (
  bucket_id = 'memory-exports'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);
