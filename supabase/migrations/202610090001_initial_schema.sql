-- أثر: المخطط الأولي لقاعدة البيانات.
-- شغّله فقط في مشروع Supabase جديد/مخصص لأثر بعد مراجعته.
-- لا يحتوي على DROP أو TRUNCATE أو حذف بيانات.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  city text,
  country text,
  timezone text not null default 'Africa/Cairo',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.prayer_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  prayer_date date not null,
  prayer text not null check (prayer in ('fajr','dhuhr','asr','maghrib','isha')),
  status text not null default 'completed' check (status in ('completed','missed')),
  source text not null default 'manual' check (source in ('manual','app')),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  unique (user_id, prayer_date, prayer)
);

create table if not exists public.quran_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  log_date date not null default current_date,
  surah_name text,
  pages_read integer not null default 0 check (pages_read >= 0),
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists public.adhkar_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  log_date date not null default current_date,
  dhikr_key text not null,
  count integer not null default 0 check (count >= 0),
  created_at timestamptz not null default now(),
  unique (user_id, log_date, dhikr_key)
);

create index if not exists prayer_logs_user_date_idx on public.prayer_logs(user_id, prayer_date desc);
create index if not exists quran_logs_user_date_idx on public.quran_logs(user_id, log_date desc);
create index if not exists adhkar_logs_user_date_idx on public.adhkar_logs(user_id, log_date desc);

alter table public.profiles enable row level security;
alter table public.prayer_logs enable row level security;
alter table public.quran_logs enable row level security;
alter table public.adhkar_logs enable row level security;

drop policy if exists "profile_select_own" on public.profiles;
create policy "profile_select_own" on public.profiles for select to authenticated using (id = (select auth.uid()));
drop policy if exists "profile_insert_own" on public.profiles;
create policy "profile_insert_own" on public.profiles for insert to authenticated with check (id = (select auth.uid()));
drop policy if exists "profile_update_own" on public.profiles;
create policy "profile_update_own" on public.profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

drop policy if exists "prayer_logs_select_own" on public.prayer_logs;
create policy "prayer_logs_select_own" on public.prayer_logs for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "prayer_logs_insert_own" on public.prayer_logs;
create policy "prayer_logs_insert_own" on public.prayer_logs for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists "prayer_logs_update_own" on public.prayer_logs;
create policy "prayer_logs_update_own" on public.prayer_logs for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
drop policy if exists "prayer_logs_delete_own" on public.prayer_logs;
create policy "prayer_logs_delete_own" on public.prayer_logs for delete to authenticated using (user_id = (select auth.uid()));

drop policy if exists "quran_logs_select_own" on public.quran_logs;
create policy "quran_logs_select_own" on public.quran_logs for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "quran_logs_insert_own" on public.quran_logs;
create policy "quran_logs_insert_own" on public.quran_logs for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists "quran_logs_update_own" on public.quran_logs;
create policy "quran_logs_update_own" on public.quran_logs for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
drop policy if exists "quran_logs_delete_own" on public.quran_logs;
create policy "quran_logs_delete_own" on public.quran_logs for delete to authenticated using (user_id = (select auth.uid()));

drop policy if exists "adhkar_logs_select_own" on public.adhkar_logs;
create policy "adhkar_logs_select_own" on public.adhkar_logs for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "adhkar_logs_insert_own" on public.adhkar_logs;
create policy "adhkar_logs_insert_own" on public.adhkar_logs for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists "adhkar_logs_update_own" on public.adhkar_logs;
create policy "adhkar_logs_update_own" on public.adhkar_logs for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
drop policy if exists "adhkar_logs_delete_own" on public.adhkar_logs;
create policy "adhkar_logs_delete_own" on public.adhkar_logs for delete to authenticated using (user_id = (select auth.uid()));

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'name', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();