-- أثر: فحص قراءة فقط لاكتشاف مخطط قاعدة البيانات الفعلي.
-- هذا الملف لا ينشئ ولا يعدّل ولا يحذف أي بيانات أو سياسات.
-- شغّل كل استعلام على حدة في Supabase SQL Editor؛ ثم أرسل النتائج مع إخفاء أي بيانات شخصية.

-- 1) كل الجداول والـ views الموجودة في public.
select table_schema, table_name, table_type
from information_schema.tables
where table_schema = 'public'
order by table_type, table_name;

-- 2) كل أعمدة الجداول في public.
select table_name, ordinal_position, column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
order by table_name, ordinal_position;

-- 3) سياسات RLS لكل جداول public.
select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
order by tablename, policyname;

-- 4) حالة RLS على الجداول الفعلية.
select n.nspname as schema_name, c.relname as table_name,
       c.relrowsecurity as rls_enabled, c.relforcerowsecurity as force_rls
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind in ('r','p')
order by c.relname;

-- 5) كل الفهارس الموجودة في public.
select schemaname, tablename, indexname, indexdef
from pg_indexes
where schemaname = 'public'
order by tablename, indexname;

-- 6) كل القيود في جداول public، دون افتراض اسم جدول محدد.
select n.nspname as schema_name, c.relname as table_name,
       con.conname, con.contype, con.convalidated,
       pg_get_constraintdef(con.oid) as definition
from pg_constraint con
join pg_class c on c.oid = con.conrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
order by c.relname, con.conname;

-- 7) كل المشغلات الموجودة في جداول public.
select event_object_table as table_name, trigger_name,
       event_manipulation, action_timing, action_statement
from information_schema.triggers
where event_object_schema = 'public'
order by event_object_table, trigger_name, event_manipulation;

-- 8) دوال public: الأسماء والتواقيع فقط.
select n.nspname as schema_name, p.proname as function_name,
       pg_get_function_identity_arguments(p.oid) as arguments,
       pg_get_function_result(p.oid) as result_type,
       p.prosecdef as security_definer
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
order by p.proname;
