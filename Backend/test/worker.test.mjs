import assert from "node:assert/strict";
import test from "node:test";

import { LIMITS, MODEL } from "../src/contract.ts";
import { handleRequest } from "../src/index.ts";
import { RequestProblem, validatePayload } from "../src/validation.ts";

const AUTH_TOKEN = "tripreel-test-token-that-is-at-least-32-bytes";
const ENV = Object.freeze({
  OPENAI_API_KEY: "sk-test-not-a-real-key-00000000000000000000",
  TRIPREEL_AUTH_TOKEN: AUTH_TOKEN,
});

function jpegBase64(width = 320, height = 240) {
  const bytes = Uint8Array.from([
    0xff,
    0xd8, // SOI
    0xff,
    0xe0,
    0x00,
    0x10, // APP0, 16-byte segment including its length
    0x4a,
    0x46,
    0x49,
    0x46,
    0x00,
    0x01,
    0x01,
    0x00,
    0x00,
    0x01,
    0x00,
    0x01,
    0x00,
    0x00,
    0xff,
    0xc0,
    0x00,
    0x11, // SOF0, 17-byte segment including its length
    0x08,
    (height >> 8) & 0xff,
    height & 0xff,
    (width >> 8) & 0xff,
    width & 0xff,
    0x03,
    0x01,
    0x11,
    0x00,
    0x02,
    0x11,
    0x00,
    0x03,
    0x11,
    0x00,
    0xff,
    0xda,
    0x00,
    0x0c, // SOS, 12-byte segment including its length
    0x03,
    0x01,
    0x00,
    0x02,
    0x11,
    0x03,
    0x11,
    0x00,
    0x3f,
    0x00,
    0x00, // Minimal entropy data for marker-level validation.
    0xff,
    0xd9, // EOI
  ]);
  return Buffer.from(bytes).toString("base64");
}

function analysisPhoto(id, overrides = {}) {
  return {
    id,
    scenic: 0.9,
    people: 0.1,
    group: 0,
    food: 0,
    document: 0,
    screenshot: 0,
    lowQuality: 0.05,
    confidence: 0.93,
    action: "keep",
    reason: "Strong travel-reel candidate.",
    ...overrides,
  };
}

function openAISuccess(photos) {
  return new Response(
    JSON.stringify({
      status: "completed",
      output: [
        {
          type: "message",
          content: [{ type: "output_text", text: JSON.stringify({ photos }) }],
        },
      ],
    }),
    { status: 200, headers: { "content-type": "application/json" } },
  );
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

test("validates the bounded request contract", () => {
  const payload = validatePayload({ photos: [{ id: "asset-1", imageBase64: jpegBase64() }] });
  assert.equal(payload.photos.length, 1);
  assert.equal(payload.photos[0].id, "asset-1");
});

test("rejects duplicate IDs and dimensions above the thumbnail limit", () => {
  const imageBase64 = jpegBase64();
  assert.throws(
    () =>
      validatePayload({
        photos: [
          { id: "duplicate", imageBase64 },
          { id: "duplicate", imageBase64 },
        ],
      }),
    (error) => error instanceof RequestProblem && error.code === "duplicate_photo_id",
  );

  assert.throws(
    () => validatePayload({ photos: [{ id: "wide", imageBase64: jpegBase64(1025, 100) }] }),
    (error) => error instanceof RequestProblem && error.code === "image_dimensions_too_large",
  );
});

test("rejects data URLs, non-JPEG data, and oversized batches before upstream fetch", async () => {
  let fetchCalls = 0;
  const fetcher = async () => {
    fetchCalls += 1;
    return openAISuccess([]);
  };

  const dataUrlResponse = await handleRequest(
    analyzeRequest({ photos: [{ id: "asset-1", imageBase64: `data:image/jpeg;base64,${jpegBase64()}` }] }),
    ENV,
    fetcher,
  );
  assert.equal(dataUrlResponse.status, 400);

  const nonJpegResponse = await handleRequest(
    analyzeRequest({ photos: [{ id: "asset-1", imageBase64: Buffer.from("x".repeat(40)).toString("base64") }] }),
    ENV,
    fetcher,
  );
  assert.equal(nonJpegResponse.status, 400);

  const tooMany = Array.from({ length: LIMITS.maxPhotos + 1 }, (_, index) => ({
    id: `asset-${index}`,
    imageBase64: jpegBase64(),
  }));
  const countResponse = await handleRequest(analyzeRequest({ photos: tooMany }), ENV, fetcher);
  assert.equal(countResponse.status, 400);
  assert.equal(fetchCalls, 0);
});

test("calls Responses API with the fixed privacy and structured-output settings", async () => {
  let outboundUrl;
  let outboundInit;
  const fetcher = async (url, init) => {
    outboundUrl = url;
    outboundInit = init;
    return openAISuccess([analysisPhoto("asset-1")]);
  };

  const response = await handleRequest(
    analyzeRequest({ photos: [{ id: "asset-1", imageBase64: jpegBase64() }] }),
    ENV,
    fetcher,
  );
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store, max-age=0");
  assert.equal(response.headers.get("access-control-allow-origin"), null);

  assert.equal(outboundUrl, "https://api.openai.com/v1/responses");
  assert.equal(outboundInit.method, "POST");
  assert.equal(outboundInit.cache, "no-store");
  assert.equal(outboundInit.redirect, "error");
  assert.equal(outboundInit.headers.authorization, `Bearer ${ENV.OPENAI_API_KEY}`);
  const upstreamBody = JSON.parse(outboundInit.body);
  assert.equal(upstreamBody.model, MODEL);
  assert.deepEqual(upstreamBody.reasoning, { effort: "none" });
  assert.equal(upstreamBody.store, false);
  assert.deepEqual(upstreamBody.prompt_cache_options, { mode: "explicit" });
  assert.equal(upstreamBody.text.format.type, "json_schema");
  assert.equal(upstreamBody.text.format.strict, true);
  assert.equal(upstreamBody.input[0].content[2].type, "input_image");
  assert.equal(upstreamBody.input[0].content[2].detail, "low");

  const body = await response.json();
  assert.equal(body.model, MODEL);
  assert.deepEqual(body.photos, [analysisPhoto("asset-1")]);
  assert.deepEqual(body.retention, {
    proxyStored: false,
    openAIStore: false,
    abuseMonitoring: "up_to_30_days_unless_zdr",
  });
});

test("requires bearer authentication without calling upstream", async () => {
  let fetchCalls = 0;
  const fetcher = async () => {
    fetchCalls += 1;
    return openAISuccess([]);
  };
  const request = analyzeRequest(
    { photos: [{ id: "asset-1", imageBase64: jpegBase64() }] },
    { authorization: "Bearer incorrect-token-that-is-long-enough" },
  );
  const response = await handleRequest(request, ENV, fetcher);
  assert.equal(response.status, 401);
  assert.match(response.headers.get("www-authenticate"), /^Bearer/);
  assert.equal(fetchCalls, 0);
});

test("never relays an upstream error body", async () => {
  const sentinel = "PRIVATE_IMAGE_OR_PROMPT_MUST_NOT_ESCAPE";
  const fetcher = async () => new Response(JSON.stringify({ error: sentinel }), { status: 400 });
  const response = await handleRequest(
    analyzeRequest({ photos: [{ id: "asset-1", imageBase64: jpegBase64() }] }),
    ENV,
    fetcher,
  );
  assert.equal(response.status, 502);
  assert.doesNotMatch(await response.text(), new RegExp(sentinel));
});

test("rejects structurally invalid model output", async () => {
  const fetcher = async () => openAISuccess([analysisPhoto("wrong-id")]);
  const response = await handleRequest(
    analyzeRequest({ photos: [{ id: "asset-1", imageBase64: jpegBase64() }] }),
    ENV,
    fetcher,
  );
  assert.equal(response.status, 502);
  assert.equal((await response.json()).error.code, "invalid_upstream_response");
});

test("CORS is off by default and exact-origin when explicitly configured", async () => {
  const blocked = await handleRequest(
    analyzeRequest(
      { photos: [{ id: "asset-1", imageBase64: jpegBase64() }] },
      { origin: "https://app.example" },
    ),
    ENV,
    async () => openAISuccess([]),
  );
  assert.equal(blocked.status, 403);
  assert.equal(blocked.headers.get("access-control-allow-origin"), null);

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
  assert.equal(allowed.headers.get("vary"), "Origin");
});
