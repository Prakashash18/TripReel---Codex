# Memories cloud setup

The iPhone app works without this service. Supabase is used only for accounts and temporary share links.

Live project: `Memories` (`fdjxxgsvtlvdcphjvcdw`, Singapore).

Completed:

1. Applied `migrations/202609180001_memory_accounts.sql`.
2. Connected the app to the project URL using its **publishable** key (never a secret/service-role key).
3. Deployed `shared-memory` with JWT verification disabled. It performs its own opaque-token check and exposes only a short-lived signed video URL.
4. Deployed `cleanup-expired-memories`; its required secret is intentionally not stored in source control.
5. Connected `marketing-site/dist/m/share-config.js` to the live `shared-memory` endpoint. Links use `https://getmemoriesapp.com/m/?token=<token>`.

Dashboard steps still required:

1. In Authentication → Sign In / Providers, enable Apple for native Sign in with Apple. The iOS App ID must also have the Sign in with Apple capability.
2. In Edge Functions → Secrets, add a long random `MEMORIES_CLEANUP_SECRET`.
3. Schedule `cleanup-expired-memories` hourly with Supabase Cron and send the same value in the `x-cleanup-secret` header.
4. Redeploy the website so the configured public share endpoint is live on `getmemoriesapp.com`.

The `memory-exports` bucket is private. The app's publishable key is safe to ship because database and Storage access are constrained by RLS. The service-role key stays inside Edge Functions only.
