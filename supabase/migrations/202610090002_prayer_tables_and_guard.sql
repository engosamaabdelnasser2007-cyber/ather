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

create index if not exists prayer_logs_user_date_idx
  on public.prayer_logs (user_id, date desc);
create index if not exists prayer_times_cache_city_date_idx
  on public.prayer_times_cache (city, country, date desc);

alter table public.profiles enable row level security;
alter table public.prayer_logs enable row level security;
alter table public.prayer_times_cache enable row level security;

-- سياسات الجداول الشخصية. السياسات permissive الموجودة مسبقًا لا تزال قد تتسع بمنطق OR؛
-- راجعها في SQL Editor قبل الإنتاج.
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
    if new.date > (now() at time zone coalesce(p.timezone, 'Africa/Cairo'))::date then
      raise exception 'prayer_not_yet_due' using errcode = 'P0001';
    end if;
  else
    local_now := now() at time zone t.tz;
    due_time := case new.prayer
      when 'fajr' then t.fajr
      when 'dhuhr' then t.dhuhr
      when 'asr' then t.asr
      when 'maghrib' then t.maghrib
      when 'isha' then t.isha
    end;
    if new.date > local_now::date
       or (new.date = local_now::date and local_now::time < due_time) then
      raise exception 'prayer_not_yet_due' using errcode = 'P0001';
    end if;
  end if;

  new.added_at := now();
  if new.status = 'completed' and
     (tg_op = 'INSERT' or old.status is distinct from 'completed') then
    new.completed_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists athar_prayer_log_guard on public.prayer_logs;
create trigger athar_prayer_log_guard
before insert or update on public.prayer_logs
for each row execute function public.athar_guard_prayer_log();
