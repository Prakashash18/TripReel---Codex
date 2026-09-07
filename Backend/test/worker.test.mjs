import assert from "node:assert/strict";
import test from "node:test";

import { DEFAULT_MODEL, LIMITS, parseAIEditPlan } from "../src/contract.ts";
import { handleRequest } from "../src/handler.ts";
import { RequestProblem, validatePayload } from "../src/validation.ts";

const AUTH_TOKEN = "tripreel-test-token-that-is-at-least-32-bytes";
const ENV = Object.freeze({
  OPENAI_API_KEY: "sk-test-not-a-real-key-00000000000000000000",
  TRIPREEL_AUTH_TOKEN: AUTH_TOKEN,
});
const APP_ATTEST_KEY_ID = Buffer.alloc(32, 0x5a).toString("base64");
const APP_ATTEST_CHALLENGE = Buffer.alloc(32, 0x31).toString("base64url");

function appAttestEnvironment(stub, rateLimit = async () => ({ success: true })) {
  return {
    ...ENV,
    APP_ATTEST_APP_ID: "GT9EAB8826.com.prakashash18.tripreel",
    APP_ATTEST_ENVIRONMENT: "production",
    APP_ATTEST_ROUTING_SECRET: "test-routing-secret-that-is-at-least-32-bytes",
    APP_ATTEST_ALLOWED_VALIDATION_CATEGORIES: "2,3,4",
    APP_ATTEST_MINIMUM_BUNDLE_VERSION: "1",
    APP_ATTEST_SHARDS: {
      getByName(name) {
        this.lastName = name;
        return stub;
      },
    },
    APP_ATTEST_ENROLL_LIMITER: { limit: rateLimit },
    APP_ATTEST_ANALYZE_LIMITER: { limit: rateLimit },
  };
}

function jpegBase64(width = 320, height = 240) {
  const bytes = Uint8Array.from([
    0xff, 0xd8,
    0xff, 0xe0, 0x00, 0x10,
    0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
    0xff, 0xc0, 0x00, 0x11, 0x08,
    (height >> 8) & 0xff, height & 0xff, (width >> 8) & 0xff, width & 0xff,
    0x03, 0x01, 0x11, 0x00, 0x02, 0x11, 0x00, 0x03, 0x11, 0x00,
    0xff, 0xda, 0x00, 0x0c,
    0x03, 0x01, 0x00, 0x02, 0x11, 0x03, 0x11, 0x00, 0x3f, 0x00, 0x00,
    0xff, 0xd9,
  ]);
  return Buffer.from(bytes).toString("base64");
}

function payload(ids = ["p0"], direction = "better_story") {
  return {
    version: 1,
    direction,
    photos: ids.map((id) => ({ id, imageBase64: jpegBase64() })),
  };
}

function plan(ids = ["p0"], direction = "better_story") {
  return {
    version: 1,
    direction,
    summary: "A concise arc that opens wide and ends on a warm shared moment.",
    sequence: ids.map((photoId, order) => ({
      photoId,
      order,
      durationSeconds: order === 0 ? 2.4 : 1.8,
      role: order === 0 ? "opening" : order === ids.length - 1 ? "closing" : "bridge",
      emphasis: order === 0 ? "highlight" : "normal",
      motion: order % 2 === 0 ? "zoom_in" : "pan_left",
    })),
  };
}

function openAISuccess(editPlan) {
  return new Response(JSON.stringify({
    status: "completed",
    output: [{
      type: "message",
      content: [{ type: "output_text", text: JSON.stringify(editPlan) }],
    }],
  }), { status: 200, headers: { "content-type": "application/json" } });
}

function analyzeRequest(body, headers = {}) {
  return new Request("https://analysis.example/v1/analyze", {
    method: "POST",
    headers: {
      authorization: `Bearer ${AUTH_TOKEN}`,
      "content-type": "application/json",
      ...headers,
    },
    body: JSON.stringify(body),
  });
}

test("validates only the versioned editorial request contract", () => {
  const valid = validatePayload(payload());
  assert.equal(valid.version, 1);
  assert.equal(valid.direction, "better_story");
  assert.equal(valid.photos[0].id, "p0");
  assert.throws(
    () => validatePayload({ ...payload(), filename: "IMG_0012.JPG" }),
    (error) => error instanceof RequestProblem && error.code === "invalid_request",
  );
  assert.throws(
    () => validatePayload({ version: 1, direction: "cinematic", photos: payload().photos }),
    (error) => error instanceof RequestProblem && error.code === "invalid_request",
  );
});

test("rejects duplicate IDs, oversized dimensions, and excessive counts", () => {
  const imageBase64 = jpegBase64();
  assert.throws(
    () => validatePayload({
      version: 1,
      direction: "calm",
      photos: [{ id: "p0", imageBase64 }, { id: "p0", imageBase64 }],
    }),
    (error) => error instanceof RequestProblem && error.code === "duplicate_photo_id",
  );
  assert.throws(
    () => validatePayload({ ...payload(), photos: [{ id: "p0", imageBase64: jpegBase64(1025, 100) }] }),
    (error) => error instanceof RequestProblem && error.code === "image_dimensions_too_large",
  );
  assert.throws(
    () => validatePayload(payload(Array.from({ length: LIMITS.maxPhotos + 1 }, (_, index) => `p${index}`))),
    (error) => error instanceof RequestProblem && error.code === "invalid_photo_count",
  );
});

test("strictly validates model plans and rejects unknown, duplicate, or arbitrary output", () => {
  assert.ok(parseAIEditPlan(plan(["p0", "p1"]), ["p0", "p1"], "better_story"));
  assert.equal(parseAIEditPlan(plan(["unknown"]), ["p0"], "better_story"), null);
  const duplicate = plan(["p0", "p0"]);
  assert.equal(parseAIEditPlan(duplicate, ["p0", "p1"], "better_story"), null);
  const invalidOrder = plan(["p0", "p1"]);
  invalidOrder.sequence[1].order = 7;
  assert.equal(parseAIEditPlan(invalidOrder, ["p0", "p1"], "better_story"), null);
  const arbitrary = { ...plan(), executableInstructions: "open a file" };
  assert.equal(parseAIEditPlan(arbitrary, ["p0"], "better_story"), null);
  const unsupportedTransition = plan(["p0"]);
  unsupportedTransition.sequence[0].transition = "wipe";
  assert.equal(parseAIEditPlan(unsupportedTransition, ["p0"], "better_story"), null);
});

test("calls Responses API as a travel-film editor with privacy settings", async () => {
  let outboundUrl;
  let outboundInit;
  const response = await handleRequest(analyzeRequest(payload()), ENV, async (url, init) => {
    outboundUrl = url;
    outboundInit = init;
    return openAISuccess(plan());
  });

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store, max-age=0");
  assert.equal(outboundUrl, "https://api.openai.com/v1/responses");
  assert.equal(outboundInit.cache, "no-store");
  assert.equal(outboundInit.redirect, "error");
  const upstream = JSON.parse(outboundInit.body);
  assert.equal(upstream.model, DEFAULT_MODEL);
  assert.deepEqual(upstream.reasoning, { effort: "none" });
  assert.equal(upstream.store, false);
  assert.equal(upstream.text.format.name, "tripreel_ai_edit_plan");
  assert.equal(upstream.text.format.strict, true);
  assert.match(upstream.instructions, /editorial assistant for a short travel film/u);
  assert.match(upstream.input[0].content[0].text, /better_story/u);
  assert.equal(upstream.input[0].content[2].type, "input_image");
  assert.equal(upstream.input[0].content[2].detail, "low");

  const body = await response.json();
  assert.equal(body.model, DEFAULT_MODEL);
  assert.deepEqual(body.plan, plan());
  assert.deepEqual(body.retention, {
    proxyStored: false,
    openAIStore: false,
    abuseMonitoring: "up_to_30_days_unless_zdr",
  });
});

test("allows a validated server-side model override", async () => {
  let upstream;
  const response = await handleRequest(
    analyzeRequest(payload()),
    { ...ENV, OPENAI_MODEL: "gpt-5.6-luna-2026-08-01" },
    async (_url, init) => {
      upstream = JSON.parse(init.body);
      return openAISuccess(plan());
    },
  );
  assert.equal(response.status, 200);
  assert.equal(upstream.model, "gpt-5.6-luna-2026-08-01");
  assert.equal((await response.json()).model, "gpt-5.6-luna-2026-08-01");
});

test("requires authentication without reading private output or calling upstream", async () => {
  let fetchCalls = 0;
  const response = await handleRequest(
    analyzeRequest(payload(), { authorization: "Bearer incorrect-token-that-is-long-enough" }),
    ENV,
    async () => {
      fetchCalls += 1;
      return openAISuccess(plan());
    },
  );
  assert.equal(response.status, 401);
  assert.match(response.headers.get("www-authenticate"), /^Bearer/u);
  assert.equal(fetchCalls, 0);
});

test("rejects malformed upstream plans and never relays upstream error bodies", async () => {
  const malformed = await handleRequest(analyzeRequest(payload()), ENV, async () => openAISuccess({ prose: "Use p0" }));
  assert.equal(malformed.status, 502);
  assert.equal((await malformed.json()).error.code, "invalid_upstream_response");

  const sentinel = "PRIVATE_IMAGE_OR_PROMPT_MUST_NOT_ESCAPE";
  const failed = await handleRequest(
    analyzeRequest(payload()),
    ENV,
    async () => new Response(JSON.stringify({ error: sentinel }), { status: 400 }),
  );
  assert.equal(failed.status, 502);
  assert.doesNotMatch(await failed.text(), new RegExp(sentinel));
});

test("CORS remains off by default and exact-origin when configured", async () => {
  const blocked = await handleRequest(
    analyzeRequest(payload(), { origin: "https://app.example" }),
    ENV,
    async () => openAISuccess(plan()),
  );
  assert.equal(blocked.status, 403);
  const preflight = new Request("https://analysis.example/v1/analyze", {
    method: "OPTIONS",
    headers: {
      origin: "https://app.example",
      "access-control-request-method": "POST",
      "access-control-request-headers": "authorization, content-type",
    },
  });
  const allowed = await handleRequest(preflight, { ...ENV, ALLOWED_ORIGIN: "https://app.example" });
  assert.equal(allowed.status, 204);
  assert.equal(allowed.headers.get("access-control-allow-origin"), "https://app.example");
});

test("issues a bounded App Attest challenge through a deterministic shard", async () => {
  let issued;
  const environment = appAttestEnvironment({
    async issueChallenge(input) {
      issued = input;
      return { ok: true, challenge: APP_ATTEST_CHALLENGE, expiresAt: "2026-09-05T12:05:00.000Z" };
    },
  });
  const response = await handleRequest(new Request("https://analysis.example/v1/app-attest/challenge", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ purpose: "attestation", keyId: APP_ATTEST_KEY_ID }),
  }), environment);
  assert.equal(response.status, 200);
  assert.equal(issued.purpose, "attestation");
  assert.deepEqual(Buffer.from(issued.keyID), Buffer.alloc(32, 0x5a));
  assert.match(environment.APP_ATTEST_SHARDS.lastName, /^app-attest-v1-production-[0-9a-f]{2}$/u);
});

test("maps already-registered challenges to a stable conflict", async () => {
  const environment = appAttestEnvironment({
    async issueChallenge() { return { ok: false, code: "key_already_registered" }; },
  });
  const response = await handleRequest(new Request("https://analysis.example/v1/app-attest/challenge", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ purpose: "attestation", keyId: APP_ATTEST_KEY_ID }),
  }), environment);
  assert.equal(response.status, 409);
  assert.equal((await response.json()).error.code, "key_already_registered");
});

test("authorizes the exact editorial body with App Attest before OpenAI", async () => {
  let authorizationInput;
  const environment = appAttestEnvironment({
    async authorizeAnalysis(input) {
      authorizationInput = input;
      return { ok: true };
    },
  });
  const requestBody = JSON.stringify(payload());
  const response = await handleRequest(new Request("https://analysis.example/v1/analyze", {
    method: "POST",
    headers: {
      authorization: `AppAttest ${APP_ATTEST_KEY_ID}`,
      "content-type": "application/json",
      "x-tripreel-challenge": APP_ATTEST_CHALLENGE,
      "x-tripreel-app-attest": Buffer.from("synthetic-cbor-assertion").toString("base64url"),
    },
    body: requestBody,
  }), environment, async () => openAISuccess(plan()));
  assert.equal(response.status, 200);
  assert.equal(authorizationInput.photoCount, 1);
  const expectedHash = Buffer.from(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(requestBody)));
  assert.deepEqual(Buffer.from(authorizationInput.bodyHash), expectedHash);
});

test("never calls OpenAI when App Attest rejects an assertion", async () => {
  let fetchCalls = 0;
  const environment = appAttestEnvironment({
    async authorizeAnalysis() { return { ok: false, code: "counter_replay" }; },
  });
  const response = await handleRequest(new Request("https://analysis.example/v1/analyze", {
    method: "POST",
    headers: {
      authorization: `AppAttest ${APP_ATTEST_KEY_ID}`,
      "content-type": "application/json",
      "x-tripreel-challenge": APP_ATTEST_CHALLENGE,
      "x-tripreel-app-attest": Buffer.from("synthetic-cbor-assertion").toString("base64url"),
    },
    body: JSON.stringify(payload()),
  }), environment, async () => {
    fetchCalls += 1;
    return openAISuccess(plan());
  });
  assert.equal(response.status, 409);
  assert.equal(fetchCalls, 0);
});
