-- أثر: اكتشاف الجداول والأعمدة الفعلية — قراءة فقط، لا يعدّل البيانات.

-- 1) الجداول الموجودة في المخططات المعتادة
select table_schema, table_name, table_type
from information_schema.tables
where table_schema in ('public', 'auth')
  and table_type = 'BASE TABLE'
order by table_schema, table_name;

-- 2) أسماء الأعمدة ذات الصلة بالصلاة أو المستخدمين أو المواقيت
select table_schema, table_name, column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and (
    table_name ilike '%prayer%'
    or table_name ilike '%salah%'
    or table_name ilike '%user%'
    or table_name ilike '%profile%'
    or table_name ilike '%time%'
    or column_name ilike '%prayer%'
    or column_name ilike '%status%'
    or column_name ilike '%user_id%'
    or column_name ilike '%fajr%'
  )
order by table_name, ordinal_position;

-- 3) سياسات RLS الحالية على كل جداول public
select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
order by tablename, policyname;

-- 4) حالة RLS لكل جدول في public
select n.nspname as schema_name, c.relname as table_name,
       c.relrowsecurity as rls_enabled, c.relforcerowsecurity as force_rls
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind = 'r'
order by c.relname;

-- 5) المشغلات على جداول public — قراءة فقط
select event_object_schema, event_object_table, trigger_name,
       event_manipulation, action_timing, action_statement
from information_schema.triggers
where event_object_schema = 'public'
order by event_object_table, trigger_name, event_manipulation;
