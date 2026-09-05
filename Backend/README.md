# TripReel visual-analysis proxy

This directory is a dependency-light TypeScript Cloudflare Worker for TripReel's **explicitly opt-in** cloud visual enhancement. It accepts reduced JPEG thumbnails, calls the OpenAI Responses API with exactly `gpt-5.6-luna`, and returns bounded visual-triage scores. It does not contain or expose an OpenAI key to the app.

The implementation deliberately has no database, object storage, cache writes, analytics SDK, or `console` calls. It never logs or persists request bodies or images.

## API contract

`POST /v1/analyze`

Production iOS requests use a fresh App Attest assertion:

```http
Authorization: AppAttest <App-Attest-key-ID>
X-TripReel-Challenge: <single-use-base64url-challenge>
X-TripReel-App-Attest: <base64url-assertion>
Content-Type: application/json
```

The Worker also retains `Authorization: Bearer <development-token>` for local/private smoke tests only.

```json
{
  "photos": [
    {
      "id": "p0",
      "imageBase64": "<base64-encoded JPEG bytes; no data-URL prefix>"
    }
  ]
}
```

Success:

```json
{
  "model": "gpt-5.6-luna",
  "photos": [
    {
      "id": "p0",
      "scenic": 0.94,
      "people": 0.12,
      "group": 0,
      "food": 0,
      "document": 0,
      "screenshot": 0,
      "lowQuality": 0.04,
      "confidence": 0.96,
      "action": "keep",
      "reason": "Strong travel-reel candidate."
    }
  ],
  "retention": {
    "proxyStored": false,
    "openAIStore": false,
    "abuseMonitoring": "up_to_30_days_unless_zdr"
  }
}
```

All scores are numbers from 0 through 1. `action` is `keep`, `review`, or `discard`. `reason` is constrained to a fixed allowlist of safe phrases; the model cannot use it to echo names, receipt text, or another string visible in a photo. The response has exactly one result for every input ID, in input order. Treat scores as suggestions; do not delete originals automatically from a model result.

Errors use a stable, sanitized shape and never include an upstream response body:

```json
{ "error": { "code": "invalid_image", "message": "..." } }
```

## Enforced limits

- 1–12 photos per request.
- 4,500,000-byte maximum JSON body, enforced while streaming as well as by `Content-Length`.
- 256 KiB decoded JPEG maximum per photo and 3 MiB decoded maximum per batch.
- 1024 × 1024 maximum dimensions and 1,048,576 maximum pixels per photo.
- JPEG only: canonical base64, legal frame/scan marker progression, consistent component tables, entropy data, a terminal end marker, and dimensions are checked. EXIF/XMP, IPTC/Photoshop, and JPEG comment segments are rejected so metadata cannot ride along with a thumbnail. This is marker-level validation, not a full pixel decoder; OpenAI still performs the actual image decode.
- Unique IDs of 1–64 characters matching `[A-Za-z0-9][A-Za-z0-9._:-]{0,63}`.
- Fifteen seconds to upload the request body, 30 seconds for OpenAI by default, and 128 KiB maximum for the upstream response.
- Exact object keys are required; unknown fields are rejected.

The OpenAI call uses image detail `low`, `reasoning: { "effort": "none" }`, `store: false`, no tools, a fixed prompt, and strict JSON Schema Structured Outputs. It sets prompt caching to explicit mode without defining a breakpoint, disabling the automatic implicit cache breakpoint. Successful model output is validated again before it reaches the app. Text visible in an image is explicitly treated as untrusted content rather than an instruction.

## Data handling and retention

TripReel creates reduced, re-encoded JPEG thumbnails in memory only after the user opts in. It strips metadata during re-encoding and discards each thumbnail and its base64 representation immediately when the request succeeds, fails, or is cancelled. It must not place thumbnails in a background-upload queue, on-disk cache, crash report, URL, header, or analytics event.

This Worker holds the JSON and thumbnails in memory only long enough to validate the request and make the foreground OpenAI request. It does not write them to KV, D1, R2, Cache API, logs, or any other persistence layer. Client and upstream fetches are marked `no-store`. Worker observability and invocation logging are disabled in `wrangler.toml`; also audit account-level Logpush, Tail Workers, WAF rules, reverse proxies, and error trackers before production so none capture bodies. Platform metadata such as method, URL, status, timing, and billing may still exist, so never put content in the URL.

`store: false` prevents this response from being stored as retrievable Responses API application state. It does **not** turn on Zero Data Retention. Under OpenAI's default API data controls, abuse-monitoring logs may contain API content and are retained for up to 30 days unless longer retention is legally or safety-required. Eligible organizations can apply for Zero Data Retention (ZDR); image inputs that are flagged by OpenAI's CSAM classifier can still be retained for manual review even with ZDR. OpenAI states that API data is not used to train or improve its models by default unless the organization explicitly opts in. See OpenAI's current [data controls documentation](https://developers.openai.com/api/docs/guides/your-data) before launch.

The model ID, image-input support, reasoning levels, and Structured Outputs support are documented in the current [GPT-5.6 Luna model page](https://developers.openai.com/api/docs/models/gpt-5.6-luna) and [Responses API reference](https://developers.openai.com/api/reference/cli/resources/responses/methods/create).

## Local validation

Node 22 or newer can run the unit tests without installing dependencies:

```sh
npm test
```

The tests exercise authentication, exact CORS behavior, request and JPEG validation, the fixed `gpt-5.6-luna`/`reasoning: none`/`store: false` upstream payload, strict output validation, and sanitized upstream failures. They use a fake `fetch`; they never call OpenAI.

For TypeScript checking and local Worker execution:

```sh
npm install
cp .dev.vars.example .dev.vars
npm run typecheck
npm run dev
```

Put only local test values in `.dev.vars`. That file and environment-specific variants are ignored by Git. Do not use a production OpenAI key while developing against sample photos.

## Cloudflare configuration and deployment

The Worker is deployed to the connected Cloudflare account as `tripreel-visual-analysis` at:

```text
https://tripreel-visual-analysis.tripreel-prakashash18.workers.dev/v1/analyze
```

The `workers.dev` hostname is enabled for this initial deployment and preview URLs are disabled. Before each deployment:

1. Create a dedicated OpenAI project, use a project-scoped key, restrict its access, and configure spend/rate alerts.
2. Generate `TRIPREEL_AUTH_TOKEN` and `APP_ATTEST_ROUTING_SECRET` with a cryptographically secure generator; use at least 32 random bytes for each. The bearer token is suitable only for local tests, a private prototype, or a server-to-server caller—never as a long-lived secret embedded in the shipped iOS binary. The App Attest routing secret determines the Durable Object shard for every registered device and must remain stable across deployments.
3. Store `OPENAI_API_KEY`, `TRIPREEL_AUTH_TOKEN`, and `APP_ATTEST_ROUTING_SECRET` as encrypted Cloudflare Worker secrets, not plaintext `[vars]`. Cloudflare documents `.dev.vars` and [`wrangler secret put`](https://developers.cloudflare.com/workers/configuration/secrets/). For an atomic first deployment, `wrangler deploy --secrets-file <protected-env-file>` can upload secrets with the code; securely delete that local production file afterward.
4. Leave `ALLOWED_ORIGIN` unset for the native iOS app. CORS is then off and browser-origin requests are rejected. If a browser client is genuinely required, configure exactly one HTTPS origin. Wildcards and comma-separated origins are rejected.
5. Before production launch, consider putting the Worker behind a dedicated HTTPS custom domain. The current `workers.dev` hostname is suitable for development and TestFlight integration work; preview URLs remain disabled. Edge rate-limit bindings provide a fast abuse guard (60 assertion-route operations per minute, covering challenge plus analysis), while the Durable Object enforces the authoritative per-key assertion counter, 30 analyses/minute quota, and 1,000-photo/UTC-day quota.
6. Confirm Workers Logs remains disabled. The source contains no `console` statements, and `wrangler.toml` explicitly disables observability and invocation logs. Review Cloudflare's current [Workers Logs behavior](https://developers.cloudflare.com/workers/observability/logs/workers-logs/) whenever deployment configuration changes.
7. Run `npm test`, `npm run typecheck`, a staging smoke test with synthetic/non-sensitive images, and negative tests for authorization, size limits, timeout, and rate limiting before production traffic.

Optional `OPENAI_TIMEOUT_MS` must be an integer from 5000 through 45000. The service fails closed with a generic configuration error if required secrets or timeout/origin settings are invalid.

The configuration opts in to Cloudflare's `enable_request_signal` flag so a disconnected client aborts the image-bearing OpenAI subrequest. It also disables importable/global environment bindings and the automatically enabled Node compatibility layer; this Worker uses Web Platform APIs only. Recheck these flags against Cloudflare's current [compatibility flags documentation](https://developers.cloudflare.com/workers/configuration/compatibility-flags/) when updating the compatibility date.

## Production mobile authentication: App Attest

The Worker implements Apple's [server validation procedure](https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server). `POST /v1/app-attest/challenge` issues a random five-minute, single-use challenge for registration or assertion. `POST /v1/app-attest/register` validates Apple's pinned App Attestation certificate chain, nonce, production AAGUID, App ID/RP ID, credential ID, public key, and initial counter. Every `POST /v1/analyze` assertion is bound to its one-time challenge, method, path, and SHA-256 of the exact JSON body.

Verification metadata is distributed across 256 secret-HMAC-selected SQLite Durable Object shards. They retain only the verified public key, opaque Apple receipt, environment, assertion counter, challenge hashes, quota counters, and timestamps. They never receive or store photo bytes, the request body, its hash, filenames, Photos identifiers, or model results. Up to four overlapping challenges per key and purpose are retained so concurrent network requests cannot invalidate each other; challenge consumption, counter advancement, and quota charging are atomic. Inactive keys are removed after 180 days.

The production app uses no shared bearer secret: the private App Attest key is created and held by the iPhone. The bearer path remains for local Debug smoke tests and must never be compiled into or configured for TestFlight. Devices where App Attest is unsupported fail closed to TripReel's on-device analysis.

## Source layout

- `src/index.ts` — Worker entry point and Durable Object export.
- `src/handler.ts` — routing, exact-origin CORS, dual App Attest/development-bearer authentication, security headers, and sanitized errors.
- `src/app-attest-encoding.ts` — strict base64/CBOR-adjacent encoding and canonical request bindings.
- `src/app-attest-verifier.ts` — Apple certificate, nonce, authenticator data, and assertion verification.
- `src/app-attest-state.ts` — sharded Durable Object challenge, key, replay, quota, and retention state.
- `src/validation.ts` — streaming body cap, strict wire validation, base64/JPEG/dimension checks.
- `src/openai.ts` — fixed Responses API request, timeout, bounded response read, and fail-closed parsing.
- `src/contract.ts` — limits, public types, JSON Schema, and output validation.
- `test/worker.test.mjs` — dependency-free unit tests with a mocked upstream.
