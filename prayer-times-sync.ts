// Supabase Edge Function: prayer-times-sync  (Deno) — لم تُجرَّب
// يملأ prayer_times_cache من Aladhan بصلاحية service_role. استدعِها من التطبيق قبل التسجيل
// أو من cron يوميًا: supabase.functions.invoke('prayer-times-sync', { body: { city, country, date } })
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
Deno.serve(async (req) => {
  const { city, country, date } = await req.json(); // date: YYYY-MM-DD
  if (!city || !country || !/^\d{4}-\d{2}-\d{2}$/.test(date)) return new Response("bad request", { status: 400 });
  const [y, m, d] = date.split("-");
  const r = await fetch(`https://api.aladhan.com/v1/timingsByCity/${d}-${m}-${y}?city=${encodeURIComponent(city)}&country=${encodeURIComponent(country)}&method=5`);
  if (!r.ok) return new Response("upstream", { status: 502 });
  const { data } = await r.json(); const t = data.timings; const hm = (s: string) => s.slice(0, 5);
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { error } = await sb.from("prayer_times_cache").upsert({
    city, country, date, fajr: hm(t.Fajr), dhuhr: hm(t.Dhuhr), asr: hm(t.Asr),
    maghrib: hm(t.Maghrib), isha: hm(t.Isha), tz: data.meta.timezone,
  });
  return new Response(error ? error.message : "ok", { status: error ? 500 : 200 });
});
