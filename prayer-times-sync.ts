// Supabase Edge Function: prayer-times-sync
// Hardened draft for review. Assumes public.profiles(id, city, country)
// and public.prayer_times_cache(city, country, date, fajr, dhuhr, asr, maghrib, isha, tz).
// Test on a staging Supabase project before deployment.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

function validDate(value: unknown): value is string {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [year, month, day] = value.split("-").map(Number);
  const d = new Date(Date.UTC(year, month - 1, day));
  return d.getUTCFullYear() === year && d.getUTCMonth() === month - 1 && d.getUTCDate() === day;
}

function cleanTime(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const match = value.match(/^(\d{1,2}):(\d{2})(?::\d{2})?(?:\s*\([^)]*\))?$/);
  if (!match) return null;
  const hours = Number(match[1]);
  const minutes = Number(match[2]);
  if (hours > 23 || minutes > 59) return null;
  return `${String(hours).padStart(2, "0")}:${String(minutes).padStart(2, "0")}`;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200, headers: corsHeaders });
  }
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const authorization = req.headers.get("Authorization");
  const tokenMatch = authorization?.match(/^Bearer\s+(.+)$/i);
  if (!tokenMatch) return json(401, { error: "authentication_required" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    console.error("Missing required Supabase Edge Function environment variables");
    return json(500, { error: "server_configuration_error" });
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${tokenMatch[1]}` } },
  });
  const { data: userResult, error: authError } = await userClient.auth.getUser(tokenMatch[1]);
  if (authError || !userResult.user) return json(401, { error: "invalid_session" });

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }
  if (!body || typeof body !== "object" || !validDate((body as Record<string, unknown>).date)) {
    return json(400, { error: "invalid_date" });
  }
  const date = (body as { date: string }).date;

  // Use the signed-in user's saved location. Do not trust city/country supplied by the client.
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: profile, error: profileError } = await admin
    .from("profiles")
    .select("city,country")
    .eq("id", userResult.user.id)
    .maybeSingle();

  if (profileError) {
    console.error("Could not read profile for prayer-time sync");
    return json(500, { error: "profile_lookup_failed" });
  }
  const city = typeof profile?.city === "string" ? profile.city.trim() : "";
  const country = typeof profile?.country === "string" ? profile.country.trim() : "";
  if (!city || !country) return json(400, { error: "profile_location_required" });

  const [year, month, day] = date.split("-");
  const upstreamUrl = new URL(
    `https://api.aladhan.com/v1/timingsByCity/${day}-${month}-${year}`,
  );
  upstreamUrl.searchParams.set("city", city);
  upstreamUrl.searchParams.set("country", country);
  upstreamUrl.searchParams.set("method", "5");

  let upstream: Response;
  try {
    upstream = await fetch(upstreamUrl, { signal: AbortSignal.timeout(10000) });
  } catch {
    return json(502, { error: "prayer_times_provider_unavailable" });
  }
  if (!upstream.ok) return json(502, { error: "prayer_times_provider_unavailable" });

  let payload: any;
  try {
    payload = await upstream.json();
  } catch {
    return json(502, { error: "invalid_prayer_times_response" });
  }
  const timings = payload?.data?.timings;
  const timezone = payload?.data?.meta?.timezone;
  const fajr = cleanTime(timings?.Fajr);
  const dhuhr = cleanTime(timings?.Dhuhr);
  const asr = cleanTime(timings?.Asr);
  const maghrib = cleanTime(timings?.Maghrib);
  const isha = cleanTime(timings?.Isha);
  if (!fajr || !dhuhr || !asr || !maghrib || !isha || typeof timezone !== "string" || !timezone) {
    return json(502, { error: "invalid_prayer_times_response" });
  }

  const { error: upsertError } = await admin.from("prayer_times_cache").upsert({
    city, country, date, fajr, dhuhr, asr, maghrib, isha, tz: timezone,
  }, { onConflict: "city,country,date" });
  if (upsertError) {
    console.error("Could not write prayer-time cache");
    return json(500, { error: "prayer_times_cache_write_failed" });
  }

  return json(200, { ok: true, date, timezone });
});
