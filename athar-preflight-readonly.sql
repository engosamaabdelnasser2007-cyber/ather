-- أثر: فحص قراءة فقط قبل أي تعديل على Supabase.
-- لا يعدّل ولا يحذف أي بيانات. شغّله في SQL Editor أولًا.

-- 1) تحقق من وجود الأعمدة التي تعتمد عليها مسودة الحارس.
select table_name, column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name in ('profiles', 'prayer_logs', 'prayer_times_cache')
order by table_name, ordinal_position;

-- 2) اعرض سياسات RLS الحالية. سياسات permissive تتجمع بمنطق OR.
select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('profiles', 'prayer_logs', 'prayer_times_cache')
order by tablename, policyname;

-- 3) تحقق من تفعيل RLS و FORCE RLS.
select n.nspname as schema_name, c.relname as table_name,
       c.relrowsecurity as rls_enabled, c.relforcerowsecurity as force_rls
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('profiles', 'prayer_logs', 'prayer_times_cache')
order by c.relname;

-- 4) اعرض الفهارس والقيود الحالية قبل إضافة أي قيد.
select indexname, indexdef
from pg_indexes
where schemaname = 'public' and tablename = 'prayer_logs'
order by indexname;

select conname, contype, convalidated, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid = to_regclass('public.prayer_logs')
order by conname;

-- 5) اعرض المشغلات الموجودة لتجنب استبدال مشغل غير متعلق.
select trigger_name, event_manipulation, action_timing, action_statement
from information_schema.triggers
where event_object_schema = 'public'
  and event_object_table = 'prayer_logs'
order by trigger_name, event_manipulation;
