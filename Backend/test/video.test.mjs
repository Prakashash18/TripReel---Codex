import assert from "node:assert/strict";
import test from "node:test";

import { handleRequest } from "../src/handler.ts";
import {
  OPENROUTER_VIDEO_MODEL,
  validateVideoGenerateRequest,
  validateVideoJobRequest,
} from "../src/openrouter-video.ts";

const AUTH_TOKEN = "memories-test-token-that-is-at-least-32-bytes";
const ENV = Object.freeze({
  OPENAI_API_KEY: "sk-test-not-a-real-key-00000000000000000000",
  OPENROUTER_API_KEY: "sk-or-test-not-a-real-key-0000000000000000",
  TRIPREEL_AUTH_TOKEN: AUTH_TOKEN,
  APP_ATTEST_ROUTING_SECRET: "test-routing-secret-that-is-at-least-32-bytes",
});

function jpegBase64(width = 576, height = 1_024) {
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

function workerRequest(path, body) {
  return new Request(`https://analysis.example${path}`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${AUTH_TOKEN}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

function appAttestVideoRequest(path, body, keyID, challenge, assertion) {
  return new Request(`https://analysis.example${path}`, {
    method: "POST",
    headers: {
      authorization: `AppAttest ${keyID}`,
      "content-type": "application/json",
      "x-tripreel-challenge": challenge,
      "x-tripreel-app-attest": assertion,
    },
    body: JSON.stringify(body),
  });
}

test("strictly validates AI video inputs", () => {
  const ending = jpegBase64(720, 1_024);
  const valid = validateVideoGenerateRequest({
    version: 2,
    imagesBase64: [jpegBase64(), ending],
    prompt: "Use subtle cinematic depth while preserving every person and object.",
  });
  assert.match(valid.prompt, /preserving/u);
  assert.equal(valid.imagesBase64.length, 2);

  const legacy = validateVideoGenerateRequest({
    version: 1,
    imageBase64: jpegBase64(),
    prompt: "Keep this existing TestFlight request working during the rollout.",
  });
  assert.equal(legacy.imagesBase64.length, 1);

  assert.throws(() => validateVideoGenerateRequest({
    version: 2,
    imagesBase64: [jpegBase64(), ending],
    prompt: "too short",
    filename: "private-name.jpg",
  }));
  assert.throws(() => validateVideoGenerateRequest({
    version: 2,
    imagesBase64: [jpegBase64(), jpegBase64()],
    prompt: "The beginning and ending must be two different approved moments.",
  }));
  assert.throws(() => validateVideoJobRequest({ version: 1, jobToken: "not-signed" }));
});

test("submits, polls, and downloads a device-bound Seedance job", async () => {
  const imageBase64 = jpegBase64();
  const endingBase64 = jpegBase64(720, 1_024);
  let submittedBody;
  const submitResponse = await handleRequest(
    workerRequest("/v1/video/generate", {
      version: 2,
      imagesBase64: [imageBase64, endingBase64],
      prompt: "Create a restrained camera push with natural movement and no invented text.",
    }),
    ENV,
    async (url, init) => {
      assert.equal(String(url), "https://openrouter.ai/api/v1/videos");
      assert.equal(init.method, "POST");
      assert.equal(new Headers(init.headers).get("authorization"), `Bearer ${ENV.OPENROUTER_API_KEY}`);
      assert.equal(init.redirect, "manual");
      assert.equal(init.cache, "no-store");
      submittedBody = JSON.parse(init.body);
      return new Response(JSON.stringify({ id: "job-abc123", status: "pending" }), {
        status: 202,
        headers: { "content-type": "application/json" },
      });
    },
  );

  assert.equal(submitResponse.status, 202);
  assert.equal(submittedBody.model, OPENROUTER_VIDEO_MODEL);
  assert.equal(submittedBody.duration, 6);
  assert.equal(submittedBody.resolution, "720p");
  assert.equal(submittedBody.aspect_ratio, "9:16");
  assert.equal(submittedBody.generate_audio, true);
  assert.equal(submittedBody.frame_images[0].frame_type, "first_frame");
  assert.equal(submittedBody.frame_images[1].frame_type, "last_frame");
  assert.equal(
    submittedBody.frame_images[0].image_url.url,
    `data:image/jpeg;base64,${imageBase64}`,
  );
  assert.equal(
    submittedBody.frame_images[1].image_url.url,
    `data:image/jpeg;base64,${endingBase64}`,
  );
  assert.equal(Object.hasOwn(submittedBody, "filename"), false);

  const submitted = await submitResponse.json();
  assert.equal(submitted.model, OPENROUTER_VIDEO_MODEL);
  assert.equal(submitted.retention.memoriesStored, false);
  assert.equal(submitted.retention.providerTemporary, true);
  assert.match(submitted.jobToken, /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/u);

  const pollResponse = await handleRequest(
    workerRequest("/v1/video/status", { version: 1, jobToken: submitted.jobToken }),
    ENV,
    async (url, init) => {
      assert.equal(String(url), "https://openrouter.ai/api/v1/videos/job-abc123");
      assert.equal(init.method, "GET");
      return new Response(JSON.stringify({ id: "job-abc123", status: "completed" }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    },
  );
  assert.deepEqual(await pollResponse.json(), { status: "completed", progress: 1 });

  const content = Uint8Array.from([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70]);
  const contentResponse = await handleRequest(
    workerRequest("/v1/video/content", { version: 1, jobToken: submitted.jobToken }),
    ENV,
    async (url, init) => {
      assert.equal(String(url), "https://openrouter.ai/api/v1/videos/job-abc123/content?index=0");
      assert.equal(init.method, "GET");
      return new Response(content, {
        status: 200,
        headers: {
          "content-type": "video/mp4",
          "content-length": String(content.byteLength),
        },
      });
    },
  );
  assert.equal(contentResponse.status, 200);
  assert.equal(contentResponse.headers.get("cache-control"), "no-store, max-age=0");
  assert.deepEqual(new Uint8Array(await contentResponse.arrayBuffer()), content);
});

test("a signed video job cannot be replayed by a different auth subject", async () => {
  const response = await handleRequest(
    workerRequest("/v1/video/generate", {
      version: 1,
      imageBase64: jpegBase64(),
      prompt: "Animate the real scene gently while preserving identity and composition.",
    }),
    ENV,
    async () => new Response(JSON.stringify({ id: "job-bound", status: "pending" }), {
      status: 202,
      headers: { "content-type": "application/json" },
    }),
  );
  const { jobToken } = await response.json();
  const replayRequest = new Request("https://analysis.example/v1/video/status", {
    method: "POST",
    headers: {
      authorization: "Bearer a-different-token-that-is-at-least-32-bytes",
      "content-type": "application/json",
    },
    body: JSON.stringify({ version: 1, jobToken }),
  });
  const replay = await handleRequest(replayRequest, {
    ...ENV,
    TRIPREEL_AUTH_TOKEN: "a-different-token-that-is-at-least-32-bytes",
  }, async () => {
    assert.fail("OpenRouter must not be called for a token from another subject");
  });
  assert.equal(replay.status, 403);
});

test("App Attest authorizes the exact AI-video operation before spending", async () => {
  const keyID = Buffer.alloc(32, 0x74).toString("base64");
  const challenge = Buffer.alloc(32, 0x24).toString("base64url");
  const assertion = Buffer.from([0xa2, 0x01, 0x02]).toString("base64url");
  let authorizationInput;
  let providerCalls = 0;
  const stub = {
    async authorizeAnalysis(input) {
      authorizationInput = input;
      return { ok: true };
    },
  };
  const env = {
    ...ENV,
    APP_ATTEST_APP_ID: "GT9EAB8826.com.prakashash18.tripreel",
    APP_ATTEST_ENVIRONMENT: "production",
    APP_ATTEST_ALLOWED_VALIDATION_CATEGORIES: "2,3,4",
    APP_ATTEST_MINIMUM_BUNDLE_VERSION: "1",
    APP_ATTEST_SHARDS: { getByName: () => stub },
    APP_ATTEST_ENROLL_LIMITER: { limit: async () => ({ success: true }) },
    APP_ATTEST_ANALYZE_LIMITER: { limit: async () => ({ success: true }) },
  };
  const body = {
    version: 2,
    imagesBase64: [jpegBase64(), jpegBase64(720, 1_024)],
    prompt: "Create gentle subject-safe motion with one restrained camera move.",
  };

  const response = await handleRequest(
    appAttestVideoRequest("/v1/video/generate", body, keyID, challenge, assertion),
    env,
    async () => {
      providerCalls += 1;
      return new Response(JSON.stringify({ id: "job-attested", status: "pending" }), {
        status: 202,
        headers: { "content-type": "application/json" },
      });
    },
  );

  assert.equal(response.status, 202);
  assert.equal(providerCalls, 1);
  assert.equal(authorizationInput.method, "POST");
  assert.equal(authorizationInput.path, "/v1/video/generate");
  assert.equal(authorizationInput.photoCount, 2);
  assert.equal(authorizationInput.videoGenerationCount, 1);
  assert.equal(authorizationInput.bodyHash.byteLength, 32);
  assert.deepEqual(Buffer.from(authorizationInput.challenge), Buffer.alloc(32, 0x24));
});
