import assert from "node:assert/strict";
import test from "node:test";

import {
  DEFAULT_MODEL,
  LIMITS,
  minimumSequenceCount,
  parseAIEditPlan,
} from "../src/contract.ts";
import { compareAICut } from "../src/comparison.ts";
import { handleRequest } from "../src/handler.ts";
import { RequestProblem, validatePayload } from "../src/validation.ts";

const AUTH_TOKEN = "tripreel-test-token-that-is-at-least-32-bytes";
const ENV = Object.freeze({
  OPENAI_API_KEY: "sk-test-not-a-real-key-00000000000000000000",
  TRIPREEL_AUTH_TOKEN: AUTH_TOKEN,
});
const APP_ATTEST_KEY_ID = Buffer.alloc(32, 0x5a).toString("base64");
const APP_ATTEST_CHALLENGE = Buffer.alloc(32, 0x31).toString("base64url");

function appAttestEnvironment(
  stub,
  rateLimit = async () => ({ success: true }),
  diagnostics,
) {
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
    ...(diagnostics === undefined ? {} : { APP_ATTEST_DIAGNOSTICS: diagnostics }),
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

function payload(ids = ["p0"], direction = "better_story", selections = []) {
  return {
    version: 1,
    direction,
    photos: ids.map((id, index) => ({
      id,
      imageBase64: jpegBase64(),
      localSelection: selections[index] ?? "first_cut",
    })),
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

function directorPayload(ids = ["p0"], direction = "better_story", selections = []) {
  return { ...payload(ids, direction, selections), version: 2 };
}

function directorPlan(ids = ["p0"], direction = "better_story") {
  return {
    ...plan(ids, direction),
    version: 2,
    story: {
      title: "From discovery to afterglow",
      arc: "Open on a visual invitation, build through distinct people and details, then resolve on a warm final moment.",
    },
    hook: {
      title: "Stay for this part",
      subtitle: "The moments between the landmarks",
      style: "editorial",
      durationSeconds: 2.2,
    },
    ending: {
      enabled: true,
      title: "Worth the long way home",
      subtitle: "Until next time",
      style: "clean",
      durationSeconds: 2,
    },
    soundtrack: {
      trackId: "long-way-home",
      reason: "The nostalgic arrangement supports the reflective ending without overpowering the people moments.",
    },
    treatment: {
      look: "journal",
      motionIntensity: "gentle",
      reason: "Tactile framing and restrained movement make repeated settings feel intentional.",
    },
  };
}

function photoContext(index) {
  return {
    captureIndex: index,
    dayIndex: Math.floor(index / 3),
    timeGap: index === 0 ? "start" : index % 3 === 0 ? "next_day" : "same_session",
    orientation: index % 2 === 0 ? "landscape" : "portrait",
    contentKind: index % 3 === 0 ? "people" : "scenery",
    peopleCount: index % 3 === 0 ? 2 : 0,
    memory: index % 2 === 0 ? "high" : "medium",
    aesthetic: "high",
    similarityGroup: "",
    sceneLabels: index % 3 === 0 ? ["People", "Event"] : ["Landscape"],
  };
}

function firstCutBaseline(ids) {
  return {
    photoCount: ids.length,
    durationSeconds: ids.length * 1.5 + 2.2,
    omittedPhotoCount: 0,
    sequence: ids.map((photoId, order) => ({
      photoId,
      order,
      durationSeconds: 1.5,
      motion: order % 2 === 0 ? "zoom_in" : "pan_left",
      frameStyle: order % 2 === 0 ? "full_bleed" : "portrait_matte",
    })),
    titles: [{
      kind: "opening",
      title: "The day begins",
      subtitle: "",
      style: "clean",
      durationSeconds: 2.2,
    }],
    soundtrackId: "wanderlust",
    look: "clean",
    motionIntensity: "gentle",
  };
}

function comparativePayload(ids, direction = "better_story", selections = []) {
  return {
    version: 3,
    direction,
    baseline: firstCutBaseline(ids.filter((_id, index) => (selections[index] ?? "first_cut") === "first_cut")),
    photos: ids.map((id, index) => ({
      id,
      imageBase64: jpegBase64(),
      localSelection: selections[index] ?? "first_cut",
      context: photoContext(index),
    })),
  };
}

function comparativePlan(ids, direction = "better_story") {
  return {
    ...directorPlan(ids, direction),
    version: 3,
    diagnosis: {
      verdict: "The First Cut has a steady rhythm but needs a clearer emotional build.",
      issues: [{
        kind: "flat_pacing",
        title: "One steady tempo",
        detail: "Hero moments and connective frames currently receive nearly the same amount of time.",
        evidencePhotoIds: ids.slice(0, 2),
      }],
    },
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
  assert.equal(valid.photos[0].localSelection, "first_cut");
  const legacy = validatePayload({
    ...payload(),
    photos: [{ id: "p0", imageBase64: jpegBase64() }],
  });
  assert.equal(legacy.photos[0].localSelection, "first_cut");
  assert.throws(
    () => validatePayload({
      ...payload(),
      photos: [{ id: "p0", imageBase64: jpegBase64(), localSelection: "discarded" }],
    }),
    (error) => error instanceof RequestProblem && error.code === "invalid_local_selection",
  );
  assert.throws(
    () => validatePayload({ ...payload(), filename: "IMG_0012.JPG" }),
    (error) => error instanceof RequestProblem && error.code === "invalid_request",
  );
  assert.throws(
    () => validatePayload({ version: 1, direction: "cinematic", photos: payload().photos }),
    (error) => error instanceof RequestProblem && error.code === "invalid_request",
  );
  assert.equal(validatePayload(directorPayload()).version, 2);
  const contextual = validatePayload({
    ...directorPayload(),
    storyContext: "  Our students’ competition day  ",
  });
  assert.equal(contextual.storyContext, "Our students’ competition day");
  assert.throws(
    () => validatePayload({ ...directorPayload(), storyContext: "x".repeat(161) }),
    (error) => error instanceof RequestProblem && error.code === "invalid_story_context",
  );
  assert.throws(
    () => validatePayload({ ...payload(), version: 3 }),
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
  const deduplicated = parseAIEditPlan(duplicate, ["p0", "p1"], "better_story");
  assert.equal(deduplicated, null);
  const reordered = plan(["p0", "p1"]);
  reordered.sequence[0].order = 1;
  reordered.sequence[1].order = 0;
  const canonical = parseAIEditPlan(reordered, ["p0", "p1"], "better_story");
  assert.deepEqual(canonical.sequence.map(({ photoId, order }) => ({ photoId, order })), [
    { photoId: "p0", order: 0 },
    { photoId: "p1", order: 1 },
  ]);
  const invalidOrder = plan(["p0", "p1"]);
  invalidOrder.sequence[1].order = 7;
  assert.equal(parseAIEditPlan(invalidOrder, ["p0", "p1"], "better_story"), null);
  const arbitrary = { ...plan(), executableInstructions: "open a file" };
  assert.equal(parseAIEditPlan(arbitrary, ["p0"], "better_story"), null);
  const unsupportedTransition = plan(["p0"]);
  unsupportedTransition.sequence[0].transition = "wipe";
  assert.equal(parseAIEditPlan(unsupportedTransition, ["p0"], "better_story"), null);
});

test("strictly validates version 2 story, title, music, and treatment recommendations", () => {
  const valid = directorPlan(["p0", "p1"]);
  const parsed = parseAIEditPlan(valid, ["p0", "p1"], "better_story", 2);
  assert.equal(parsed.version, 2);
  assert.equal(parsed.hook.title, "Stay for this part");
  assert.equal(parsed.soundtrack.trackId, "long-way-home");
  assert.equal(parsed.treatment.look, "journal");

  const unsupportedTrack = structuredClone(valid);
  unsupportedTrack.soundtrack.trackId = "streamed-track";
  assert.equal(parseAIEditPlan(unsupportedTrack, ["p0", "p1"], "better_story", 2), null);

  const emptyHook = structuredClone(valid);
  emptyHook.hook.title = "   ";
  assert.equal(parseAIEditPlan(emptyHook, ["p0", "p1"], "better_story", 2), null);

  assert.equal(parseAIEditPlan(valid, ["p0", "p1"], "better_story", 1), null);
});

test("requires useful coverage instead of accepting an aggressively short montage", () => {
  const ids = Array.from({ length: 24 }, (_, index) => `p${index}`);
  assert.equal(minimumSequenceCount(ids.length, "better_story"), 15);
  assert.equal(minimumSequenceCount(ids.length, "people"), 18);
  assert.equal(parseAIEditPlan(plan(ids.slice(0, 14)), ids, "better_story"), null);
});

test("calls Responses API with local-selection context and privacy settings", async () => {
  let outboundUrl;
  let outboundInit;
  const response = await handleRequest(
    analyzeRequest(payload(["p0"], "better_story", ["more_photos"])),
    ENV,
    async (url, init) => {
    outboundUrl = url;
    outboundInit = init;
    return openAISuccess(plan());
    },
  );

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store, max-age=0");
  assert.equal(outboundUrl, "https://api.openai.com/v1/responses");
  assert.equal(outboundInit.cache, "no-store");
  assert.equal(outboundInit.redirect, "manual");
  const upstream = JSON.parse(outboundInit.body);
  assert.equal(upstream.model, DEFAULT_MODEL);
  assert.deepEqual(upstream.reasoning, { effort: "none" });
  assert.equal(upstream.store, false);
  assert.equal(upstream.text.format.name, "tripreel_ai_edit_plan");
  assert.equal(upstream.text.format.strict, true);
  assert.match(upstream.instructions, /editorial assistant for a short travel film/u);
  assert.match(upstream.input[0].content[0].text, /better_story/u);
  assert.match(upstream.input[0].content[0].text, /at least 1 materially distinct moment/u);
  assert.match(upstream.input[0].content[1].text, /local selection: more_photos/u);
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

test("version 2 asks for an editable reel direction and returns it without changing privacy", async () => {
  let upstream;
  const expected = directorPlan(["p0", "p1"], "people");
  const response = await handleRequest(
    analyzeRequest({
      ...directorPayload(["p0", "p1"], "people", ["first_cut", "more_photos"]),
      storyContext: "Our students’ competition day",
    }),
    ENV,
    async (_url, init) => {
      upstream = JSON.parse(init.body);
      return openAISuccess(expected);
    },
  );

  assert.equal(response.status, 200);
  assert.match(upstream.instructions, /act as a reel director/u);
  assert.match(upstream.instructions, /specific, meaningful titles/u);
  assert.match(upstream.instructions, /long-way-home/u);
  assert.match(upstream.input[0].content[0].text, /story arc, opening hook/u);
  assert.match(upstream.input[0].content[1].text, /Our students’ competition day/u);
  assert.equal(upstream.text.format.schema.properties.version.const, 2);
  assert.deepEqual(
    new Set(upstream.text.format.schema.required),
    new Set(["version", "direction", "summary", "story", "hook", "ending", "soundtrack", "treatment", "sequence"]),
  );
  const body = await response.json();
  assert.deepEqual(body.plan, expected);
  assert.equal(body.retention.proxyStored, false);
  assert.equal(body.retention.openAIStore, false);
});

test("version 3 critiques the submitted First Cut and returns Worker-measured changes", async () => {
  const ids = ["p0", "p1", "p2", "p3", "p4", "p5"];
  const requestPayload = comparativePayload(ids, "people", [
    "first_cut", "first_cut", "first_cut", "first_cut", "more_photos", "more_photos",
  ]);
  const expected = comparativePlan([...ids].reverse(), "people");
  let upstream;
  const response = await handleRequest(
    analyzeRequest({ ...requestPayload, storyContext: "A shared achievement" }),
    ENV,
    async (_url, init) => {
      upstream = JSON.parse(init.body);
      return openAISuccess(expected);
    },
  );

  assert.equal(response.status, 200);
  assert.deepEqual(upstream.reasoning, { effort: "low" });
  assert.match(upstream.instructions, /improve the submitted First Cut/u);
  assert.match(upstream.instructions, /Privately draft, critique, and revise/u);
  assert.match(upstream.input[0].content[2].text, /Current First Cut timeline/u);
  assert.match(upstream.input[0].content[3].text, /coarse on-device context/u);
  assert.equal(upstream.text.format.schema.properties.version.const, 3);
  assert.ok(upstream.text.format.schema.properties.diagnosis);

  const body = await response.json();
  assert.equal(body.plan.version, 3);
  assert.equal(body.plan.diagnosis.issues[0].kind, "flat_pacing");
  assert.equal(body.plan.comparison.firstCutPhotoCount, 4);
  assert.equal(body.plan.comparison.restoredCount, 2);
  assert.ok(body.plan.comparison.reorderedCount > 0);
  assert.equal(body.plan.comparison.materiallyDifferent, true);
  assert.equal(body.retention.openAIStore, false);
});

test("version 3 rejects metadata-like context and computes comparison independently", () => {
  const requestPayload = comparativePayload(["p0", "p1"]);
  const validated = validatePayload(requestPayload);
  assert.equal(validated.baseline.photoCount, 2);
  assert.equal(validated.photos[0].context.dayIndex, 0);

  const withFilename = structuredClone(requestPayload);
  withFilename.photos[0].context.filename = "IMG_0001.JPG";
  assert.throws(
    () => validatePayload(withFilename),
    (error) => error instanceof RequestProblem && error.code === "invalid_photo_context",
  );

  const candidate = comparativePlan(["p1", "p0"]);
  const parsed = parseAIEditPlan(candidate, ["p0", "p1"], "better_story", 3);
  assert.equal(parsed.version, 3);
  const comparison = compareAICut(validated.baseline, validated.photos, parsed);
  assert.equal(comparison.aiCutPhotoCount, 2);
  assert.equal(comparison.reorderedCount, 1);
  assert.equal(Object.hasOwn(candidate, "comparison"), false);
});

test("version 3 runs one critic revision when the first draft is only cosmetic", async () => {
  const ids = ["p0", "p1", "p2", "p3", "p4", "p5"];
  const requestPayload = comparativePayload(ids);
  const weak = comparativePlan(ids);
  weak.story.title = "The day begins";
  weak.hook = {
    title: "The day begins",
    subtitle: "",
    style: "clean",
    durationSeconds: 2.2,
  };
  weak.ending = { enabled: false, title: "", subtitle: "", style: "clean", durationSeconds: 2 };
  weak.soundtrack = { trackId: "wanderlust", reason: "Keep the familiar acoustic bed." };
  weak.treatment = {
    look: "clean",
    motionIntensity: "gentle",
    reason: "Keep the current restrained visual language.",
  };
  weak.sequence = requestPayload.baseline.sequence.map((item) => ({
    photoId: item.photoId,
    order: item.order,
    durationSeconds: item.durationSeconds,
    role: item.order === 0 ? "opening" : item.order === ids.length - 1 ? "closing" : "bridge",
    emphasis: item.order === 0 ? "highlight" : "normal",
    motion: item.motion,
  }));
  const stronger = comparativePlan([...ids].reverse());

  const upstreamBodies = [];
  const response = await handleRequest(
    analyzeRequest(requestPayload),
    ENV,
    async (_url, init) => {
      upstreamBodies.push(JSON.parse(init.body));
      return openAISuccess(upstreamBodies.length === 1 ? weak : stronger);
    },
  );

  assert.equal(response.status, 200);
  assert.equal(upstreamBodies.length, 2);
  assert.match(
    upstreamBodies[1].input[0].content.find((item) => item.type === "input_text" && /quality check/u.test(item.text)).text,
    /too similar/u,
  );
  const body = await response.json();
  assert.deepEqual(body.plan.sequence.map((item) => item.photoId), [...ids].reverse());
  assert.equal(body.plan.comparison.materiallyDifferent, true);
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
  const dataPoints = [];
  const failed = await handleRequest(
    analyzeRequest(payload()),
    {
      ...ENV,
      APP_ATTEST_DIAGNOSTICS: {
        writeDataPoint(dataPoint) {
          dataPoints.push(dataPoint);
        },
      },
    },
    async () => new Response(JSON.stringify({ error: sentinel }), { status: 400 }),
  );
  assert.equal(failed.status, 502);
  assert.doesNotMatch(await failed.text(), new RegExp(sentinel));
  assert.deepEqual(dataPoints[0].blobs, [
    "openai",
    "upstream_error",
    "responses_api",
    "ServiceProblem",
    "provider_status_400",
  ]);
  assert.equal(JSON.stringify(dataPoints).includes(sentinel), false);
});

test("records a bounded sanitized provider exception without request content", async () => {
  const dataPoints = [];
  const privateToken = "private-provider-token-abcdefghijklmnopqrstuvwxyz";
  const response = await handleRequest(
    analyzeRequest(payload()),
    {
      ...ENV,
      APP_ATTEST_DIAGNOSTICS: {
        writeDataPoint(dataPoint) {
          dataPoints.push(dataPoint);
        },
      },
    },
    async () => {
      throw new TypeError(`Network failed with ${privateToken}`);
    },
  );

  assert.equal(response.status, 502);
  assert.equal((await response.json()).error.code, "upstream_unavailable");
  assert.equal(dataPoints.length, 1);
  assert.deepEqual(dataPoints[0].blobs.slice(0, 4), [
    "openai",
    "upstream_unavailable",
    "responses_api",
    "ServiceProblem",
  ]);
  assert.match(dataPoints[0].blobs[4], /^TypeError: Network failed with \[redacted\]$/u);
  assert.equal(JSON.stringify(dataPoints).includes(privateToken), false);
});

test("never follows an OpenAI redirect with the image-bearing request", async () => {
  let fetchCalls = 0;
  const response = await handleRequest(
    analyzeRequest(payload()),
    ENV,
    async (_url, init) => {
      fetchCalls += 1;
      assert.equal(init.redirect, "manual");
      return new Response(null, {
        status: 302,
        headers: { location: "https://redirect.example/collect" },
      });
    },
  );

  assert.equal(fetchCalls, 1);
  assert.equal(response.status, 502);
  assert.equal((await response.json()).error.code, "upstream_error");
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

test("records only sanitized App Attest registration diagnostics", async () => {
  const dataPoints = [];
  const diagnostic = {
    writeDataPoint(dataPoint) {
      dataPoints.push(dataPoint);
    },
  };
  const environment = appAttestEnvironment({
    async registerKey() {
      return {
        ok: false,
        code: "server_misconfigured",
        diagnostic: {
          stage: "registration_storage",
          errorName: "Error",
          message: "SQLITE_CONSTRAINT: missing column",
        },
      };
    },
  }, undefined, diagnostic);
  const response = await handleRequest(new Request("https://analysis.example/v1/app-attest/register", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      keyId: APP_ATTEST_KEY_ID,
      challenge: APP_ATTEST_CHALLENGE,
      attestationObject: Buffer.from("synthetic-attestation").toString("base64url"),
    }),
  }), environment);

  assert.equal(response.status, 500);
  const responseBody = await response.json();
  assert.deepEqual(responseBody, {
    error: {
      code: "server_misconfigured",
      message: "The service is not configured correctly.",
    },
  });
  assert.equal(dataPoints.length, 1);
  assert.deepEqual(dataPoints[0].blobs, [
    "registration",
    "server_misconfigured",
    "registration_storage",
    "Error",
    "SQLITE_CONSTRAINT: missing column",
  ]);
  assert.equal(dataPoints[0].doubles.length, 1);
  assert.equal(JSON.stringify(dataPoints).includes(APP_ATTEST_KEY_ID), false);
});

test("records a sanitized diagnostic when the App Attest shard call throws", async () => {
  const dataPoints = [];
  const diagnostic = {
    writeDataPoint(dataPoint) {
      dataPoints.push(dataPoint);
    },
  };
  const environment = appAttestEnvironment({
    async registerKey() {
      throw new Error(`Durable Object failed for ${APP_ATTEST_KEY_ID}`);
    },
  }, undefined, diagnostic);
  const response = await handleRequest(new Request("https://analysis.example/v1/app-attest/register", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      keyId: APP_ATTEST_KEY_ID,
      challenge: APP_ATTEST_CHALLENGE,
      attestationObject: Buffer.from("synthetic-attestation").toString("base64url"),
    }),
  }), environment);

  assert.equal(response.status, 500);
  assert.equal((await response.json()).error.code, "server_misconfigured");
  assert.equal(dataPoints.length, 1);
  assert.deepEqual(dataPoints[0].blobs.slice(0, 4), [
    "registration",
    "server_misconfigured",
    "registration_rpc",
    "Error",
  ]);
  assert.equal(dataPoints[0].blobs[4].includes(APP_ATTEST_KEY_ID), false);
  assert.equal(dataPoints[0].blobs[4].includes("[redacted]"), true);
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
