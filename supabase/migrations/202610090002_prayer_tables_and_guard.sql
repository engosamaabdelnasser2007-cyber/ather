-- أثر: إنشاء الجداول الأساسية وحارس تسجيل الصلاة.
-- راجع المخطط قبل التشغيل. مناسب لمشروع أثر لا يحتوي هذه الجداول بعد.
-- لا يحذف أي جدول أو بيانات. اختبره في مشروع staging أولًا.

create extension if not exists pgcrypto;

-- ملف المستخدم: إذا كان موجودًا بأعمدة مختلفة، لا تُعدّل هيكله تلقائيًا؛
-- افحصه قبل تشغيل هذا الملف.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  city text,
  country text,
  timezone text not null default 'Africa/Cairo',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- مواقيت الصلاة التي يعتمد عليها الحارس.
create table if not exists public.prayer_times_cache (
  city text not null,
  country text not null,
  date date not null,
  fajr time not null,
  dhuhr time not null,
  asr time not null,
  maghrib time not null,
  isha time not null,
  tz text not null,
  updated_at timestamptz not null default now(),
  primary key (city, country, date)
);

-- سجل الصلاة. لا يمكن للمستخدم إنشاء سجل باسم مستخدم آخر بسبب RLS.
create table if not exists public.prayer_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  date date not null,
  prayer text not null check (prayer in ('fajr','dhuhr','asr','maghrib','isha')),
  status text not null default 'completed' check (status in ('pending','completed','missed')),
  source text not null default 'live' check (source in ('live','manual')),
  prayed_at time,
  added_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  unique (user_id, date, prayer)
);

-- Extend pre-existing tables too. CREATE TABLE IF NOT EXISTS alone does not
-- add columns when a table already exists.
alter table public.profiles
  add column if not exists city text,
  add column if not exists country text,
  add column if not exists timezone text not null default 'Africa/Cairo',
  add column if not exists updated_at timestamptz not null default now();

alter table public.prayer_times_cache
  add column if not exists city text,
  add column if not exists country text,
  add column if not exists date date,
  add column if not exists fajr time,
  add column if not exists dhuhr time,
  add column if not exists asr time,
  add column if not exists maghrib time,
  add column if not exists isha time,
  add column if not exists tz text,
  add column if not exists updated_at timestamptz not null default now();

alter table public.prayer_logs
  add column if not exists source text not null default 'live',
  add column if not exists prayed_at time,
  add column if not exists added_at timestamptz not null default now(),
  add column if not exists completed_at timestamptz;

-- Compatibility with the current app data layer, which reads/writes timing,
-- progress, and updated_at. Safe for existing tables: only adds missing columns.
alter table public.prayer_logs
  add column if not exists timing text,
  add column if not exists progress integer,
  add column if not exists updated_at timestamptz not null default now();

-- The app upserts on (user_id, date, prayer). Never delete duplicates automatically.
-- Abort with a clear message if existing data cannot safely support this unique key.
DO $block$
BEGIN
  if exists (
    select 1 from public.prayer_logs
    where user_id is null or date is null or prayer is null
  ) then
    raise exception 'migration_blocked: prayer_logs has null identity fields; inspect rows first';
  end if;
  if exists (
    select 1 from public.prayer_logs
    group by user_id, date, prayer
    having count(*) > 1
  ) then
    raise exception 'migration_blocked: duplicate (user_id,date,prayer) rows exist; resolve manually before migration';
  end if;
END;
$block$;

create unique index if not exists prayer_logs_user_date_prayer_uidx
  on public.prayer_logs (user_id, date, prayer);

-- Cache upsert also depends on a unique key. Existing nulls/duplicates must be reviewed.
DO $block$
BEGIN
  if exists (
    select 1 from public.prayer_times_cache
    where city is null or country is null or date is null
  ) then
    raise exception 'migration_blocked: prayer_times_cache has null key fields; inspect rows first';
  end if;
  if exists (
    select 1 from public.prayer_times_cache
    group by city, country, date
    having count(*) > 1
  ) then
    raise exception 'migration_blocked: duplicate (city,country,date) cache rows exist; resolve manually before migration';
  end if;
END;
$block$;

create unique index if not exists prayer_times_cache_city_country_date_uidx
  on public.prayer_times_cache (city, country, date);

create index if not exists prayer_logs_user_date_idx
  on public.prayer_logs (user_id, date desc);
create index if not exists prayer_times_cache_city_date_idx
  on public.prayer_times_cache (city, country, date desc);

alter table public.profiles enable row level security;
alter table public.prayer_logs enable row level security;
alter table public.prayer_times_cache enable row level security;

-- سياسات الجداول الشخصية. السياسات permissive الموجودة مسبقًا لا تزال قد تتسع بمنطق OR؛
-- راجعها في SQL Editor قبل الإنتاج. لا تحذف هذه السياسات تلقائيًا؛ قد تكون مخصصة لميزات أخرى.
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
  for select to authenticated using (id = (select auth.uid()));
drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles
  for insert to authenticated with check (id = (select auth.uid()));
drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update to authenticated using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

drop policy if exists "prayer_logs_select_own" on public.prayer_logs;
create policy "prayer_logs_select_own" on public.prayer_logs
  for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "prayer_logs_insert_own" on public.prayer_logs;
create policy "prayer_logs_insert_own" on public.prayer_logs
  for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists "prayer_logs_update_own" on public.prayer_logs;
create policy "prayer_logs_update_own" on public.prayer_logs
  for update to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
drop policy if exists "prayer_logs_delete_own" on public.prayer_logs;
create policy "prayer_logs_delete_own" on public.prayer_logs
  for delete to authenticated using (user_id = (select auth.uid()));

drop policy if exists "prayer_times_cache_read_authenticated" on public.prayer_times_cache;
create policy "prayer_times_cache_read_authenticated" on public.prayer_times_cache
  for select to authenticated using (true);

create or replace function public.athar_guard_prayer_log()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  p public.profiles%rowtype;
  t public.prayer_times_cache%rowtype;
  local_now timestamp;
  due_time time;
begin
  -- Validate values even if an older table was created without CHECK constraints.
  if new.prayer not in ('fajr', 'dhuhr', 'asr', 'maghrib', 'isha') then
    raise exception 'invalid_prayer' using errcode = '22023';
  end if;
  if new.status not in ('pending', 'completed', 'missed') then
    raise exception 'invalid_prayer_status' using errcode = '22023';
  end if;
  if new.source not in ('live', 'manual') then
    raise exception 'invalid_prayer_source' using errcode = '22023';
  end if;

  -- لا تسمح بتغيير مالك السجل أو هويته عبر UPDATE.
  if tg_op = 'UPDATE' then
    if new.user_id is distinct from old.user_id
       or new.date is distinct from old.date
       or new.prayer is distinct from old.prayer then
      raise exception 'prayer_log_identity_immutable' using errcode = '42501';
    end if;
  end if;

  -- لا تعتمد على RLS وحدها داخل trigger؛ تحقق من هوية المستخدم.
  if auth.uid() is not null and new.user_id <> auth.uid() then
    raise exception 'prayer_log_not_owned' using errcode = '42501';
  end if;

  select * into p from public.profiles where id = new.user_id;
  if not found then
    raise exception 'profile_required_for_prayer_log' using errcode = 'P0001';
  end if;

  -- سجلات pending ليست وسيلة لتجاوز الحارس؛ نتحقق من وقت الصلاة عند كل إدخال/تحديث.
  select * into t
  from public.prayer_times_cache
  where city = p.city and country = p.country and date = new.date;

  if not found then
    if new.source <> 'manual' then
      raise exception 'prayer_times_unavailable' using errcode = 'P0001';
    end if;
    if p.timezone is null or not exists (
      select 1 from pg_catalog.pg_timezone_names z where z.name = p.timezone
    ) then
      raise exception 'invalid_profile_timezone' using errcode = '22023';
    end if;
    if new.date > (now() at time zone p.timezone)::date then
      raise exception 'prayer_not_yet_due' using errcode = 'P0001';
    end if;
  else
    -- Fail closed: invalid time zones or missing times must never bypass due-time checks.
    if t.tz is null or not exists (
      select 1 from pg_catalog.pg_timezone_names z where z.name = t.tz
    ) then
      raise exception 'invalid_prayer_timezone' using errcode = '22023';
    end if;

    local_now := now() at time zone t.tz;
    due_time := case new.prayer
      when 'fajr' then t.fajr
      when 'dhuhr' then t.dhuhr
      when 'asr' then t.asr
      when 'maghrib' then t.maghrib
      when 'isha' then t.isha
    end;

    if local_now is null or due_time is null then
      raise exception 'prayer_time_data_incomplete' using errcode = 'P0001';
    end if;

    if new.date > local_now::date
       or (new.date = local_now::date and local_now::time < due_time) then
      raise exception 'prayer_not_yet_due' using errcode = 'P0001';
    end if;
  end if;

  if tg_op = 'INSERT' then
    new.added_at := now();
    if new.status = 'completed' then
      new.completed_at := now();
    else
      new.completed_at := null;
    end if;
  else
    -- Keep server-owned timestamps stable; clients cannot rewrite them.
    new.added_at := old.added_at;
    if new.status = 'completed' and old.status is distinct from 'completed' then
      new.completed_at := now();
    elsif new.status = 'completed' then
      new.completed_at := old.completed_at;
    else
      new.completed_at := null;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists athar_prayer_log_guard on public.prayer_logs;
create trigger athar_prayer_log_guard
before insert or update on public.prayer_logs
for each row execute function public.athar_guard_prayer_log();
