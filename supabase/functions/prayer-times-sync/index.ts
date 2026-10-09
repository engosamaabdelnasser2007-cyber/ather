// Supabase Edge Function: prayer-times-sync
// Review draft: validate the caller, derive location from their profile,
// validate upstream data, and never expose service-role credentials.
// Verify schema and test in a staging Supabase project before deployment.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
};
const reply = (status: number, payload: Record<string, unknown>) =>
  new Response(JSON.stringify(payload), { status, headers });

function isValidDate(value: unknown): value is string {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [y, m, d] = value.split("-").map(Number);
  const parsed = new Date(Date.UTC(y, m - 1, d));
  return parsed.getUTCFullYear() === y && parsed.getUTCMonth() === m - 1 && parsed.getUTCDate() === d;
}
function timeValue(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const match = value.match(/^(\d{1,2}):(\d{2})(?::\d{2})?(?:\s*\([^)]*\))?$/);
  if (!match) return null;
  const h = Number(match[1]), m = Number(match[2]);
  return h <= 23 && m <= 59 ? `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}` : null;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return reply(405, { error: "method_not_allowed" });

  const bearer = req.headers.get("Authorization")?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!bearer) return reply(401, { error: "authentication_required" });

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) {
    console.error("Prayer-time sync configuration missing");
    return reply(500, { error: "server_configuration_error" });
  }

  const userClient = createClient(url, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser(bearer);
  if (authError || !authData.user) return reply(401, { error: "invalid_session" });

  let input: unknown;
  try { input = await req.json(); } catch { return reply(400, { error: "invalid_json" }); }
  if (!input || typeof input !== "object" || !isValidDate((input as Record<string, unknown>).date)) {
    return reply(400, { error: "invalid_date" });
  }
  const date = (input as { date: string }).date;
  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // The caller cannot choose arbitrary city/country; use their saved profile.
  const { data: profile, error: profileError } = await admin
    .from("profiles").select("city,country").eq("id", authData.user.id).maybeSingle();
  if (profileError) {
    console.error("Profile lookup failed during prayer-time sync");
    return reply(500, { error: "profile_lookup_failed" });
  }
  const city = typeof profile?.city === "string" ? profile.city.trim() : "";
  const country = typeof profile?.country === "string" ? profile.country.trim() : "";
  if (!city || !country) return reply(400, { error: "profile_location_required" });

  const [year, month, day] = date.split("-");
  const providerUrl = new URL(`https://api.aladhan.com/v1/timingsByCity/${day}-${month}-${year}`);
  providerUrl.searchParams.set("city", city);
  providerUrl.searchParams.set("country", country);
  providerUrl.searchParams.set("method", "5");

  let response: Response;
  try { response = await fetch(providerUrl, { signal: AbortSignal.timeout(10000) }); }
  catch { return reply(502, { error: "prayer_times_provider_unavailable" }); }
  if (!response.ok) return reply(502, { error: "prayer_times_provider_unavailable" });

  let payload: any;
  try { payload = await response.json(); }
  catch { return reply(502, { error: "invalid_provider_response" }); }

  const source = payload?.data?.timings;
  const timezone = payload?.data?.meta?.timezone;
  const fajr = timeValue(source?.Fajr), dhuhr = timeValue(source?.Dhuhr);
  const asr = timeValue(source?.Asr), maghrib = timeValue(source?.Maghrib);
  const isha = timeValue(source?.Isha);
  if (!fajr || !dhuhr || !asr || !maghrib || !isha ||
      typeof timezone !== "string" || timezone.length > 80) {
    return reply(502, { error: "invalid_provider_response" });
  }

  const { error: writeError } = await admin.from("prayer_times_cache").upsert(
    { city, country, date, fajr, dhuhr, asr, maghrib, isha, tz: timezone },
    { onConflict: "city,country,date" },
  );
  if (writeError) {
    console.error("Prayer-time cache upsert failed");
    return reply(500, { error: "prayer_times_cache_write_failed" });
  }
  return reply(200, { ok: true, date, timezone });
});
