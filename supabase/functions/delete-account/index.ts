import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const bucket = "memory-exports";

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const authorization = request.headers.get("Authorization") ?? "";
  const token = authorization.startsWith("Bearer ")
    ? authorization.slice("Bearer ".length).trim()
    : "";
  if (!token) return json({ error: "unauthorized" }, 401);

  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  // Never trust a user id from the request body. Resolve the caller from the
  // signed session token and use that id for every cleanup operation.
  const { data: authData, error: authError } = await supabaseAdmin.auth.getUser(token);
  const user = authData.user;
  if (authError || !user) return json({ error: "unauthorized" }, 401);

  try {
    const paths = await storagePathsForUser(supabaseAdmin, user.id);
    for (let start = 0; start < paths.length; start += 100) {
      const { error } = await supabaseAdmin.storage
        .from(bucket)
        .remove(paths.slice(start, start + 100));
      if (error) throw error;
    }

    // The database rows reference auth.users with ON DELETE CASCADE, so this
    // removes the profile, memories, and monthly export claims after Storage
    // is empty. Supabase does not allow deletion while the user owns objects.
    const { error: deleteError } = await supabaseAdmin.auth.admin.deleteUser(user.id);
    if (deleteError) throw deleteError;

    return json({ deleted: true });
  } catch (error) {
    console.error("delete-account failed", {
      userId: user.id,
      error: error instanceof Error ? error.message : String(error),
    });
    return json({ error: "deletion_failed" }, 500);
  }
});

async function storagePathsForUser(
  supabaseAdmin: ReturnType<typeof createClient>,
  userID: string,
) {
  const paths = new Set<string>();
  let offset = 0;

  while (true) {
    const { data, error } = await supabaseAdmin.storage.from(bucket).list(userID, {
      limit: 1_000,
      offset,
      sortBy: { column: "name", order: "asc" },
    });
    if (error) throw error;

    for (const object of data ?? []) {
      if (object.name) paths.add(`${userID}/${object.name}`);
    }
    if (!data || data.length < 1_000) break;
    offset += data.length;
  }

  // Include database paths as a second source of truth in case Storage's list
  // endpoint is eventually paginated or shaped differently.
  const { data: memories, error: memoriesError } = await supabaseAdmin
    .from("memories")
    .select("storage_path")
    .eq("owner_id", userID);
  if (memoriesError) throw memoriesError;
  for (const memory of memories ?? []) paths.add(memory.storage_path);

  return [...paths];
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}
