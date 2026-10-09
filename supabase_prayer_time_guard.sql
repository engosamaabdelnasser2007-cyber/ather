-- أثر — حارس وقت الصلاة على مستوى قاعدة البيانات (Supabase / Postgres)
-- ملاحظة: لم يُجرَّب على قاعدة بياناتك. راجعه على نسخة تجريبية أولًا.
-- يفترض وجود: profiles(id, city, country, timezone) و prayer_logs(user_id, date, prayer, status, ...)

-- 1) أعمدة التسجيل اليدوي
alter table prayer_logs
  add column if not exists source text not null default 'live' check (source in ('live','manual')),
  add column if not exists prayed_at time,
  add column if not exists added_at timestamptz not null default now();

-- 2) مواقيت الصلاة المعتمدة على الخادم (لا يكتبها إلا service_role عبر Edge Function)
create table if not exists prayer_times_cache (
  city text not null, country text not null, date date not null,
  fajr time not null, dhuhr time not null, asr time not null,
  maghrib time not null, isha time not null,
  tz text not null,                      -- مثل Africa/Cairo (من meta.timezone في Aladhan)
  primary key (city, country, date)
);
alter table prayer_times_cache enable row level security;
create policy "read times" on prayer_times_cache for select to authenticated using (true);
-- لا توجد سياسة insert/update: الكتابة للـ service_role فقط.

-- 3) الحارس
create or replace function enforce_prayer_time() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  p profiles%rowtype; t prayer_times_cache%rowtype;
  local_now timestamp; local_date date; due time;
begin
  if new.status = 'pending' then return new; end if;

  select * into p from profiles where id = new.user_id;
  select * into t from prayer_times_cache
   where city = p.city and country = p.country and date = new.date;

  if not found then
    if new.source = 'manual' then
      -- لا يمكن التحقق؛ يُقبل كسجل يدوي فقط ولا يُقبل لتاريخ مستقبلي
      if new.date > (now() at time zone coalesce(p.timezone,'UTC'))::date then
        raise exception 'prayer_not_yet_due' using errcode = 'P0001';
      end if;
    else
      raise exception 'prayer_times_unavailable' using errcode = 'P0001';
    end if;
  else
    local_now  := now() at time zone t.tz;
    local_date := local_now::date;
    due := case new.prayer when 'fajr' then t.fajr when 'dhuhr' then t.dhuhr
             when 'asr' then t.asr when 'maghrib' then t.maghrib else t.isha end;
    if new.date > local_date or (new.date = local_date and local_now::time < due) then
      raise exception 'prayer_not_yet_due' using errcode = 'P0001';
    end if;
  end if;

  -- لا نثق بوقت العميل
  new.added_at := now();
  if new.status = 'completed' and (tg_op = 'INSERT' or old.status is distinct from 'completed') then
    new.completed_at := now();
  end if;
  return new;
end $$;

drop trigger if exists prayer_time_guard on prayer_logs;
create trigger prayer_time_guard before insert or update on prayer_logs
  for each row execute function enforce_prayer_time();
