import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (request) => {
  const expected = Deno.env.get("MEMORIES_CLEANUP_SECRET");
  if (!expected || request.headers.get("x-cleanup-secret") !== expected) {
    return new Response("Unauthorized", { status: 401 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
  const now = new Date().toISOString();
  const { data: expired, error } = await supabase
    .from("memories")
    .select("id,storage_path")
    .lte("expires_at", now)
    .limit(250);

  if (error) return response({ error: error.message }, 500);
  if (!expired?.length) return response({ deleted: 0 });

  const paths = expired.map((memory) => memory.storage_path);
  const { error: storageError } = await supabase.storage.from("memory-exports").remove(paths);
  if (storageError) return response({ error: storageError.message }, 500);

  const { error: deleteError } = await supabase
    .from("memories")
    .delete()
    .in("id", expired.map((memory) => memory.id));
  if (deleteError) return response({ error: deleteError.message }, 500);

  return response({ deleted: expired.length });
});

function response(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}
