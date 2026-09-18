import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "https://getmemoriesapp.com",
  "Access-Control-Allow-Headers": "content-type",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (request.method !== "GET") return json({ error: "method_not_allowed" }, 405);

  const url = new URL(request.url);
  const token = url.searchParams.get("token") ?? url.pathname.split("/").filter(Boolean).at(-1);
  if (!token || !/^[0-9a-f-]{36}$/i.test(token)) return json({ error: "not_found" }, 404);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const { data: memory, error } = await supabase
    .from("memories")
    .select("title,duration_seconds,export_tier,storage_path,created_at,expires_at,share_enabled")
    .eq("share_token", token)
    .maybeSingle();

  if (error || !memory || !memory.share_enabled) return json({ error: "not_found" }, 404);
  if (new Date(memory.expires_at).getTime() <= Date.now()) return json({ error: "expired" }, 410);

  const { data: signed, error: signedError } = await supabase.storage
    .from("memory-exports")
    .createSignedUrl(memory.storage_path, 15 * 60);
  if (signedError || !signed) return json({ error: "temporarily_unavailable" }, 503);

  return json({
    title: memory.title,
    duration_seconds: memory.duration_seconds,
    export_tier: memory.export_tier,
    created_at: memory.created_at,
    expires_at: memory.expires_at,
    video_url: signed.signedUrl,
  });
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}
