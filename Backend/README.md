# TripReel visual-analysis proxy

This directory is a dependency-light TypeScript Cloudflare Worker for TripReel's **explicitly opt-in AI Remix**. It accepts selected reduced JPEG previews, asks a configurable OpenAI image-capable model for a bounded editorial plan, and returns only structured editing decisions. It never renders a video and does not contain or expose an OpenAI key to the app.

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
  "version": 2,
  "direction": "better_story",
  "photos": [
    {
      "id": "p0",
      "imageBase64": "<base64-encoded JPEG bytes; no data-URL prefix>",
      "localSelection": "more_photos"
    }
  ]
}
```

Success:

```json
{
  "model": "gpt-5.6-luna",
  "plan": {
    "version": 2,
    "direction": "better_story",
    "summary": "A concise arc opening wide and ending on a shared moment.",
    "story": {
      "title": "From discovery to afterglow",
      "arc": "Open with wonder, move closer to the people, and finish on a warm shared moment."
    },
    "hook": {
      "title": "Stay for this part",
      "subtitle": "The moments between the landmarks",
      "style": "editorial",
      "durationSeconds": 2.2
    },
    "ending": {
      "enabled": true,
      "title": "Worth the long way home",
      "subtitle": "Until next time",
      "style": "clean",
      "durationSeconds": 2.0
    },
    "soundtrack": {
      "trackId": "long-way-home",
      "reason": "The nostalgic arrangement supports the reflective ending."
    },
    "treatment": {
      "look": "journal",
      "motionIntensity": "gentle",
      "reason": "Tactile framing and restrained movement keep the memories natural."
    },
    "sequence": [{
      "photoId": "p0",
      "order": 0,
      "durationSeconds": 2.4,
      "role": "opening",
      "emphasis": "highlight",
      "motion": "zoom_in"
    }]
  },
  "retention": {
    "proxyStored": false,
    "openAIStore": false,
    "abuseMonitoring": "up_to_30_days_unless_zdr"
  }
}
```

Supported directions are `better_story`, `dynamic`, `calm`, `people`, and `surprise_me`. `localSelection` is either `first_cut` or `more_photos`; it is an advisory local-editing hint, not a quality verdict. An optional normalized `storyContext` of at most 160 characters carries creator-supplied meaning such as “our students’ competition day”; it is descriptive content, not an instruction channel. The Worker temporarily defaults `localSelection` to `first_cut` and accepts request version `1` for compatibility with earlier TestFlight builds. Version `2` adds a story arc, editable opening/ending copy, one supported bundled soundtrack, and an editable look/motion treatment. It can choose only `wanderlust`, `simplicity`, `castles`, or `long-way-home`; music is shipped with the app rather than streamed or generated. A sequence may use each supplied temporary ID at most once. The Worker canonicalizes playback order and duplicate model selections before returning the plan; durations must be 0.6–4.0 seconds, and role, emphasis, and motion are fixed enums understood by the local renderer. Omitted previews are simply not included in the AI candidate. The iOS app validates the complete plan again and maps the temporary IDs locally; no model decision deletes or modifies an original.

Errors use a stable, sanitized shape and never include an upstream response body:

```json
{ "error": { "code": "invalid_image", "message": "..." } }
```

## Enforced limits

- Version `1` (legacy sequence) or `2` (director recommendations), one supported direction, and 1–36 photos per request.
- 6,500,000-byte maximum JSON body, enforced while streaming as well as by `Content-Length`.
- 128 KiB decoded JPEG maximum per photo and 4,500,000 bytes decoded maximum per batch.
- 1024 × 1024 maximum dimensions and 1,048,576 maximum pixels per photo.
- JPEG only: canonical base64, legal frame/scan marker progression, consistent component tables, entropy data, a terminal end marker, and dimensions are checked. EXIF/XMP, IPTC/Photoshop, and JPEG comment segments are rejected so metadata cannot ride along with a thumbnail. This is marker-level validation, not a full pixel decoder; OpenAI still performs the actual image decode.
- IDs must be contiguous per-request placeholders `p0`, `p1`, …; stable library identifiers are rejected.
- Fifteen seconds to upload the request body, 30 seconds for OpenAI by default, and 128 KiB maximum for the upstream response.
- Exact object keys are required; unknown fields are rejected.

The OpenAI call uses image detail `low`, `store: false`, no tools, a fixed travel-film editorial prompt, and strict JSON Schema Structured Outputs. Legacy requests use `reasoning: { "effort": "none" }`; comparative version 3 requests use bounded `low` reasoning so the director can critique the First Cut before returning its final plan. The model sees temporary IDs, selected images, the advisory local-selection label, an optional creator-entered story hint, the existing edit timeline, and coarse on-device editorial cues. It never receives GPS, exact dates, filenames, OCR text, faces, or stable Photos IDs. It is told not to identify people, infer private information, invent events, or obey text inside an image or the story hint. Successful output is checked for exact keys, known unique IDs, contiguous order, bounds, and supported enum values before it reaches the app. The Worker independently compares the validated plan with the submitted First Cut. If the first proposal is only cosmetic and sufficient request time remains, it asks for one bounded critic revision and returns the stronger valid plan; it never trusts the model to report its own change counts.

## Data handling and retention

TripReel creates reduced, re-encoded JPEG thumbnails in memory only after the user opts in. It strips metadata during re-encoding and discards each thumbnail and its base64 representation immediately when the request succeeds, fails, or is cancelled. It must not place thumbnails in a background-upload queue, on-disk cache, crash report, URL, header, or analytics event.

This Worker holds the JSON and thumbnails in memory only long enough to validate the request and make the foreground OpenAI request. It does not write them to KV, D1, R2, Cache API, logs, or any other persistence layer. Client and upstream fetches are marked `no-store`. Worker observability and invocation logging are disabled in `wrangler.toml`; also audit account-level Logpush, Tail Workers, WAF rules, reverse proxies, and error trackers before production so none capture bodies. Platform metadata such as method, URL, status, timing, and billing may still exist, so never put content in the URL.

The `tripreel_app_attest_diagnostics` Analytics Engine dataset is a narrow operational exception used only when secure-device verification fails. Each event contains the operation, a bounded failure stage, an error category, and sanitized error text. It never contains a thumbnail, request body or hash, IP address, App Attest key ID, Photos identifier, filename, or model response. Normal Worker Logs remain disabled.

`store: false` prevents this response from being stored as retrievable Responses API application state. It does **not** turn on Zero Data Retention. Under OpenAI's default API data controls, abuse-monitoring logs may contain API content and are retained for up to 30 days unless longer retention is legally or safety-required. Eligible organizations can apply for Zero Data Retention (ZDR); image inputs that are flagged by OpenAI's CSAM classifier can still be retained for manual review even with ZDR. OpenAI states that API data is not used to train or improve its models by default unless the organization explicitly opts in. See OpenAI's current [data controls documentation](https://developers.openai.com/api/docs/guides/your-data) before launch.

The model defaults to `gpt-5.6-luna`; operators may select another compatible model only with the validated `OPENAI_MODEL` Worker setting. Image-input support and Structured Outputs requirements must be checked before changing it. See the [Responses API reference](https://developers.openai.com/api/reference/cli/resources/responses/methods/create).

## Local validation

Node 22 or newer can run the unit tests without installing dependencies:

```sh
npm test
```

The tests exercise authentication, exact CORS behavior, request and JPEG validation, model configurability, `reasoning: none`, `store: false`, strict edit-plan validation, and sanitized upstream failures. They use a fake `fetch`; they never call OpenAI.

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

The live Worker uses the versioned AI edit-plan contract in this repository. Deploy reviewed changes from `Backend/` before testing a newer iOS AI Remix build against that hostname.

The `workers.dev` hostname is enabled for this initial deployment and preview URLs are disabled. Before each deployment:

1. Create a dedicated OpenAI project, use a project-scoped key, restrict its access, and configure spend/rate alerts.
2. Generate `TRIPREEL_AUTH_TOKEN` and `APP_ATTEST_ROUTING_SECRET` with a cryptographically secure generator; use at least 32 random bytes for each. The bearer token is suitable only for local tests, a private prototype, or a server-to-server caller—never as a long-lived secret embedded in the shipped iOS binary. The App Attest routing secret determines the Durable Object shard for every registered device and must remain stable across deployments.
3. Store `OPENAI_API_KEY`, `TRIPREEL_AUTH_TOKEN`, and `APP_ATTEST_ROUTING_SECRET` as encrypted Cloudflare Worker secrets, not plaintext `[vars]`. Cloudflare documents `.dev.vars` and [`wrangler secret put`](https://developers.cloudflare.com/workers/configuration/secrets/). For an atomic first deployment, `wrangler deploy --secrets-file <protected-env-file>` can upload secrets with the code; securely delete that local production file afterward.
4. Leave `ALLOWED_ORIGIN` unset for the native iOS app. CORS is then off and browser-origin requests are rejected. If a browser client is genuinely required, configure exactly one HTTPS origin. Wildcards and comma-separated origins are rejected.
5. Before production launch, consider putting the Worker behind a dedicated HTTPS custom domain. The current `workers.dev` hostname is suitable for development and TestFlight integration work; preview URLs remain disabled. Edge rate-limit bindings provide a fast abuse guard (60 assertion-route operations per minute, covering challenge plus analysis), while the Durable Object enforces the authoritative per-key assertion counter, 30 analyses/minute quota, and 1,000-photo/UTC-day quota.
6. Confirm Workers Logs remains disabled. The source contains no `console` statements, and `wrangler.toml` explicitly disables observability and invocation logs. Review Cloudflare's current [Workers Logs behavior](https://developers.cloudflare.com/workers/observability/logs/workers-logs/) whenever deployment configuration changes.
7. Confirm the `APP_ATTEST_DIAGNOSTICS` binding targets `tripreel_app_attest_diagnostics`. Retain only the minimum operational window needed for troubleshooting.
8. Run `npm test`, `npm run typecheck`, a staging smoke test with synthetic/non-sensitive images, and negative tests for authorization, size limits, timeout, and rate limiting before production traffic.

Optional `OPENAI_TIMEOUT_MS` must be an integer from 5000 through 45000. Optional `OPENAI_MODEL` must be a 1–100 character safe model identifier; it defaults to `gpt-5.6-luna`. The service fails closed with a generic configuration error if required secrets or model/timeout/origin settings are invalid.

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
- `src/openai.ts` — configurable Responses API editorial request, timeout, bounded response read, and fail-closed parsing.
- `src/contract.ts` — limits, public types, JSON Schema, and output validation.
- `test/worker.test.mjs` — dependency-free unit tests with a mocked upstream.
