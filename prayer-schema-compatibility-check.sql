-- أثر: فحص توافق جدول تسجيل الصلاة مع واجهة التطبيق — قراءة فقط.
-- لا ينشئ/يعدّل/يحذف جداول أو بيانات أو سياسات.
-- شغّل هذا الملف في Supabase SQL Editor قبل تشغيل أي migration.

-- 1) هل الجداول المطلوبة موجودة؟
select t.table_name,
       case when t.table_name is null then 'MISSING' else 'FOUND' end as state
from (values ('profiles'), ('prayer_logs'), ('prayer_times_cache')) as expected(table_name)
left join information_schema.tables t
  on t.table_schema = 'public'
 and t.table_name = expected.table_name
order by expected.table_name;

-- 2) أعمدة يحتاجها مسار الصلاة الحالي في الواجهة.
with expected(table_name, column_name) as (
  values
    ('profiles','id'), ('profiles','city'), ('profiles','country'), ('profiles','timezone'),
    ('prayer_logs','user_id'), ('prayer_logs','date'), ('prayer_logs','prayer'),
    ('prayer_logs','status'), ('prayer_logs','timing'), ('prayer_logs','progress'),
    ('prayer_logs','source'), ('prayer_logs','prayed_at'), ('prayer_logs','completed_at'),
    ('prayer_logs','updated_at'),
    ('prayer_times_cache','city'), ('prayer_times_cache','country'), ('prayer_times_cache','date'),
    ('prayer_times_cache','fajr'), ('prayer_times_cache','dhuhr'), ('prayer_times_cache','asr'),
    ('prayer_times_cache','maghrib'), ('prayer_times_cache','isha'), ('prayer_times_cache','tz')
)
select e.table_name, e.column_name,
       case when c.column_name is null then 'MISSING' else 'FOUND' end as state,
       c.data_type, c.is_nullable
from expected e
left join information_schema.columns c
  on c.table_schema = 'public'
 and c.table_name = e.table_name
 and c.column_name = e.column_name
order by e.table_name, e.column_name;

-- 3) هل يوجد مفتاح فريد يدعم upsert onConflict(user_id,date,prayer)؟
select i.relname as index_name, pg_get_indexdef(ix.indexrelid) as definition
from pg_index ix
join pg_class t on t.oid = ix.indrelid
join pg_namespace n on n.oid = t.relnamespace
join pg_class i on i.oid = ix.indexrelid
where n.nspname = 'public'
  and t.relname = 'prayer_logs'
  and ix.indisunique
order by i.relname;

-- 4) اكتشاف سجلات مكررة قبل إنشاء أي unique index.
-- النتيجة الفارغة تعني عدم العثور على تكرارات؛ لا تحذف التكرارات تلقائيًا.
select user_id, date, prayer, count(*) as duplicate_count
from public.prayer_logs
group by user_id, date, prayer
having count(*) > 1
order by duplicate_count desc, date desc
limit 100;

-- 5) قيم status/source الموجودة فعليًا، لتفادي إضافة CHECK يخالف البيانات القديمة.
select 'status' as field_name, status as field_value, count(*) as row_count
from public.prayer_logs
group by status
union all
select 'source' as field_name, source as field_value, count(*) as row_count
from public.prayer_logs
group by source
order by field_name, row_count desc;

-- 6) سياسات RLS الحالية على الجداول الثلاثة.
select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('profiles','prayer_logs','prayer_times_cache')
order by tablename, policyname;

-- 7) المشغلات والدوال المرتبطة بسجل الصلاة؛ لا تعرض بيانات المستخدمين.
select tr.trigger_name, tr.action_timing, tr.event_manipulation, tr.action_statement
from information_schema.triggers tr
where tr.event_object_schema = 'public'
  and tr.event_object_table = 'prayer_logs'
order by tr.trigger_name, tr.event_manipulation;

select p.proname as function_name,
       pg_get_function_identity_arguments(p.oid) as arguments,
       pg_get_functiondef(p.oid) as definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('athar_guard_prayer_log','enforce_prayer_time')
order by p.proname;
