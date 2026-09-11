import {
  decodeBase64URL,
  decodeKeyID,
  sha256,
} from "./app-attest-encoding.ts";
import type {
  AppAttestChallengeResult,
  AppAttestDiagnostic,
  AppAttestOperationResult,
  AppAttestProtectedPath,
  AppAttestPurpose,
  AuthorizeAnalysisInput,
  IssueChallengeInput,
  RefundVideoGenerationInput,
  RegisterKeyInput,
} from "./app-attest-state.ts";
import {
  LIMITS,
  RETENTION,
  configuredModel,
  type PublicAIEditPlan,
  type PublicAnalysisResponse,
  type ValidatedPayload,
} from "./contract.ts";
import { analyzeWithOpenAI, ServiceProblem } from "./openai.ts";
import { compareAICut } from "./comparison.ts";
import { RequestProblem, validatePayload } from "./validation.ts";
import {
  OPENROUTER_VIDEO_MODEL,
  VIDEO_MAX_BODY_BYTES,
  downloadVideo,
  pollVideo,
  requireVideoConfiguration,
  submitVideo,
  validateVideoGenerateRequest,
  validateVideoJobRequest,
} from "./openrouter-video.ts";

interface AppAttestShardStub {
  issueChallenge(input: IssueChallengeInput): Promise<AppAttestChallengeResult>;
  registerKey(input: RegisterKeyInput): Promise<AppAttestOperationResult>;
  authorizeAnalysis(input: AuthorizeAnalysisInput): Promise<AppAttestOperationResult>;
  refundVideoGeneration(input: RefundVideoGenerationInput): Promise<void>;
}

interface AppAttestShardNamespace {
  getByName(name: string): AppAttestShardStub;
}

interface RateLimitBinding {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}

export interface Env {
  OPENAI_API_KEY?: string;
  TRIPREEL_AUTH_TOKEN?: string;
  ALLOWED_ORIGIN?: string;
  OPENAI_TIMEOUT_MS?: string;
  OPENAI_MODEL?: string;
  OPENROUTER_API_KEY?: string;
  APP_ATTEST_APP_ID?: string;
  APP_ATTEST_ENVIRONMENT?: string;
  APP_ATTEST_ROUTING_SECRET?: string;
  APP_ATTEST_ALLOWED_VALIDATION_CATEGORIES?: string;
  APP_ATTEST_MINIMUM_BUNDLE_VERSION?: string;
  APP_ATTEST_SHARDS?: AppAttestShardNamespace;
  APP_ATTEST_ENROLL_LIMITER?: RateLimitBinding;
  APP_ATTEST_ANALYZE_LIMITER?: RateLimitBinding;
  APP_ATTEST_DIAGNOSTICS?: AnalyticsEngineDataset;
}

type Fetcher = typeof fetch;

const ANALYZE_PATH = "/v1/analyze";
const CHALLENGE_PATH = "/v1/app-attest/challenge";
const REGISTER_PATH = "/v1/app-attest/register";
const VIDEO_GENERATE_PATH = "/v1/video/generate";
const VIDEO_STATUS_PATH = "/v1/video/status";
const VIDEO_CONTENT_PATH = "/v1/video/content";
const VIDEO_PATHS: ReadonlySet<AppAttestProtectedPath> = new Set([
  VIDEO_GENERATE_PATH,
  VIDEO_STATUS_PATH,
  VIDEO_CONTENT_PATH,
]);
const SUPPORTED_PATHS = new Set([
  ANALYZE_PATH,
  CHALLENGE_PATH,
  REGISTER_PATH,
  ...VIDEO_PATHS,
]);
const MAX_APP_ATTEST_BODY_BYTES = 128 * 1024;
const MAX_ASSERTION_HEADER_CHARACTERS = 32 * 1024;
const APP_ATTEST_AUTH_PREFIX = "AppAttest ";
const BASE_HEADERS: Readonly<Record<string, string>> = Object.freeze({
  "cache-control": "no-store, max-age=0",
  "content-type": "application/json; charset=utf-8",
  "content-security-policy": "default-src 'none'; frame-ancestors 'none'",
  "referrer-policy": "no-referrer",
  "x-content-type-options": "nosniff",
});

interface BaseConfiguration {
  apiKey: string;
  authToken?: string;
  corsOrigin?: string;
  openAITimeoutMs?: string;
  model: string;
}

interface AppAttestConfiguration {
  appID: string;
  environment: "development" | "production";
  routingSecret: string;
  namespace: AppAttestShardNamespace;
  enrollLimiter: RateLimitBinding;
  analyzeLimiter: RateLimitBinding;
}

interface RoutedKey {
  keyId: string;
  keyID: Uint8Array;
  limiterKey: string;
  stub: AppAttestShardStub;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasExactKeys(value: Record<string, unknown>, keys: readonly string[]): boolean {
  const actual = Object.keys(value);
  return actual.length === keys.length && keys.every((key) => Object.hasOwn(value, key));
}

function configuredCorsOrigin(value: string | undefined): string | undefined {
  if (value === undefined || value === "") {
    return undefined;
  }
  if (value.length > 200 || value === "*" || value.includes(",")) {
    throw new ServiceProblem(500, "server_misconfigured", "The service is not configured correctly.");
  }
  try {
    const url = new URL(value);
    const localHttp = url.protocol === "http:" && (url.hostname === "localhost" || url.hostname === "127.0.0.1");
    if ((url.protocol !== "https:" && !localHttp) || url.origin !== value) {
      throw new Error("invalid origin");
    }
  } catch {
    throw new ServiceProblem(500, "server_misconfigured", "The service is not configured correctly.");
  }
  return value;
}

function corsHeaders(origin: string | undefined): Record<string, string> {
  if (origin === undefined) {
    return {};
  }
  return {
    "access-control-allow-origin": origin,
    "access-control-allow-methods": "POST, OPTIONS",
    "access-control-allow-headers":
      "Authorization, Content-Type, X-TripReel-Challenge, X-TripReel-App-Attest",
    "access-control-max-age": "600",
    vary: "Origin",
  };
}

function jsonResponse(
  body: unknown,
  status: number,
  origin?: string,
  extraHeaders: Readonly<Record<string, string>> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...BASE_HEADERS, ...corsHeaders(origin), ...extraHeaders },
  });
}

function emptyResponse(status: number, origin?: string): Response {
  const headers = { ...BASE_HEADERS, ...corsHeaders(origin) };
  delete (headers as Partial<Record<string, string>>)["content-type"];
  return new Response(null, { status, headers });
}

function errorResponse(
  status: number,
  code: string,
  message: string,
  origin?: string,
  extraHeaders: Readonly<Record<string, string>> = {},
): Response {
  return jsonResponse({ error: { code, message } }, status, origin, extraHeaders);
}

function requireBaseConfiguration(env: Env): BaseConfiguration {
  const model = configuredModel(env.OPENAI_MODEL);
  if (
    typeof env.OPENAI_API_KEY !== "string" ||
    env.OPENAI_API_KEY.length < 20 ||
    env.OPENAI_API_KEY.length > 512 ||
    (env.TRIPREEL_AUTH_TOKEN !== undefined &&
      (env.TRIPREEL_AUTH_TOKEN.length < 32 || env.TRIPREEL_AUTH_TOKEN.length > 512)) ||
    model === null
  ) {
    throw new ServiceProblem(500, "server_misconfigured", "The service is not configured correctly.");
  }
  return {
    apiKey: env.OPENAI_API_KEY,
    authToken: env.TRIPREEL_AUTH_TOKEN,
    corsOrigin: configuredCorsOrigin(env.ALLOWED_ORIGIN),
    openAITimeoutMs: env.OPENAI_TIMEOUT_MS,
    model,
  };
}

function requireAppAttestConfiguration(env: Env): AppAttestConfiguration {
  const allowedValidationCategories = env.APP_ATTEST_ALLOWED_VALIDATION_CATEGORIES
    ?.split(",")
    .map((entry) => entry.trim());
  if (
    typeof env.APP_ATTEST_APP_ID !== "string" ||
    !/^[A-Z0-9]{10}\.[A-Za-z0-9.-]{1,200}$/u.test(env.APP_ATTEST_APP_ID) ||
    (env.APP_ATTEST_ENVIRONMENT !== "development" && env.APP_ATTEST_ENVIRONMENT !== "production") ||
    allowedValidationCategories === undefined ||
    allowedValidationCategories.length === 0 ||
    allowedValidationCategories.length > 32 ||
    allowedValidationCategories.some(
      (category) => !/^(?:0|[1-9][0-9]{0,9})$/u.test(category) || Number(category) > 0xffff_ffff,
    ) ||
    typeof env.APP_ATTEST_MINIMUM_BUNDLE_VERSION !== "string" ||
    !/^[1-9][0-9]{0,8}$/u.test(env.APP_ATTEST_MINIMUM_BUNDLE_VERSION) ||
    typeof env.APP_ATTEST_ROUTING_SECRET !== "string" ||
    env.APP_ATTEST_ROUTING_SECRET.length < 32 ||
    env.APP_ATTEST_ROUTING_SECRET.length > 512 ||
    env.APP_ATTEST_SHARDS === undefined ||
    env.APP_ATTEST_ENROLL_LIMITER === undefined ||
    env.APP_ATTEST_ANALYZE_LIMITER === undefined
  ) {
    throw new ServiceProblem(500, "server_misconfigured", "The service is not configured correctly.");
  }
  return {
    appID: env.APP_ATTEST_APP_ID,
    environment: env.APP_ATTEST_ENVIRONMENT,
    routingSecret: env.APP_ATTEST_ROUTING_SECRET,
    namespace: env.APP_ATTEST_SHARDS,
    enrollLimiter: env.APP_ATTEST_ENROLL_LIMITER,
    analyzeLimiter: env.APP_ATTEST_ANALYZE_LIMITER,
  };
}

async function constantTimeTokenMatch(authorization: string | null, expected: string): Promise<boolean> {
  if (authorization === null || authorization.length > 600 || !authorization.startsWith("Bearer ")) {
    return false;
  }
  const supplied = authorization.slice("Bearer ".length);
  if (supplied.length === 0) {
    return false;
  }
  const encoder = new TextEncoder();
  const [suppliedHash, expectedHash] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(supplied)),
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
  ]);
  const suppliedBytes = new Uint8Array(suppliedHash);
  const expectedBytes = new Uint8Array(expectedHash);
  let different = suppliedBytes.length ^ expectedBytes.length;
  for (let index = 0; index < suppliedBytes.length; index += 1) {
    different |= suppliedBytes[index] ^ expectedBytes[index];
  }
  return different === 0;
}

function requestCorsOrigin(request: Request, configuredOrigin: string | undefined): string | undefined {
  const origin = request.headers.get("origin");
  if (origin === null) {
    return undefined;
  }
  if (configuredOrigin === undefined || origin !== configuredOrigin) {
    throw new RequestProblem(403, "origin_not_allowed", "Browser origin is not allowed.");
  }
  return origin;
}

function handlePreflight(request: Request, origin: string | undefined): Response {
  if (origin === undefined) {
    return errorResponse(403, "origin_not_allowed", "Browser origin is not allowed.");
  }
  if (request.headers.get("access-control-request-method")?.toUpperCase() !== "POST") {
    return errorResponse(403, "preflight_not_allowed", "CORS preflight is not allowed.", origin);
  }
  const requestedHeaders = (request.headers.get("access-control-request-headers") ?? "")
    .split(",")
    .map((header) => header.trim().toLowerCase())
    .filter(Boolean);
  const allowed = new Set([
    "authorization",
    "content-type",
    "x-tripreel-challenge",
    "x-tripreel-app-attest",
  ]);
  if (requestedHeaders.some((header) => !allowed.has(header))) {
    return errorResponse(403, "preflight_not_allowed", "CORS preflight is not allowed.", origin);
  }
  return new Response(null, {
    status: 204,
    headers: { "cache-control": "no-store, max-age=0", ...corsHeaders(origin) },
  });
}

async function readStreamBounded(
  stream: ReadableStream<Uint8Array>,
  maxBytes: number,
  timeoutMs: number,
): Promise<Uint8Array> {
  const reader = stream.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  let timeoutHandle: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_resolve, reject) => {
    timeoutHandle = setTimeout(() => {
      reject(new RequestProblem(408, "request_timeout", "Request body took too long to read."));
    }, timeoutMs);
  });
  const read = (async () => {
    while (true) {
      const { done, value } = await reader.read();
      if (done) {
        break;
      }
      total += value.byteLength;
      if (total > maxBytes) {
        throw new RequestProblem(413, "body_too_large", `Request body exceeds ${maxBytes} bytes.`);
      }
      chunks.push(value);
    }
    const result = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) {
      result.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return result;
  })();
  try {
    return await Promise.race([read, timeout]);
  } catch (error) {
    try {
      await reader.cancel();
    } catch {
      // Best effort; preserve the original error.
    }
    throw error;
  } finally {
    if (timeoutHandle !== undefined) {
      clearTimeout(timeoutHandle);
    }
  }
}

async function readJSONWithBytes(
  request: Request,
  maxBytes: number,
): Promise<{ value: unknown; bytes: Uint8Array }> {
  const encoding = request.headers.get("content-encoding")?.trim().toLowerCase();
  if (encoding !== undefined && encoding !== "identity") {
    throw new RequestProblem(415, "unsupported_content_encoding", "Compressed request bodies are not accepted.");
  }
  const contentType = request.headers.get("content-type")?.split(";", 1)[0]?.trim().toLowerCase();
  if (contentType !== "application/json") {
    throw new RequestProblem(415, "unsupported_media_type", "Content-Type must be application/json.");
  }
  const contentLength = request.headers.get("content-length");
  if (contentLength !== null) {
    if (!/^\d+$/u.test(contentLength)) {
      throw new RequestProblem(400, "invalid_content_length", "Content-Length is invalid.");
    }
    if (Number(contentLength) > maxBytes) {
      throw new RequestProblem(413, "body_too_large", `Request body exceeds ${maxBytes} bytes.`);
    }
  }
  if (request.body === null) {
    throw new RequestProblem(400, "missing_body", "A JSON request body is required.");
  }
  const bytes = await readStreamBounded(request.body, maxBytes, LIMITS.bodyReadTimeoutMs);
  let text: string;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    throw new RequestProblem(400, "invalid_json", "Request body must be valid UTF-8 JSON.");
  }
  try {
    return { value: JSON.parse(text) as unknown, bytes };
  } catch {
    throw new RequestProblem(400, "invalid_json", "Request body must be valid JSON.");
  }
}

function encodeBase64URL(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/u, "");
}

async function hmacSHA256(secret: string, data: Uint8Array): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return new Uint8Array(await crypto.subtle.sign("HMAC", key, Uint8Array.from(data)));
}

async function routeKey(
  keyId: string,
  configuration: AppAttestConfiguration,
): Promise<RoutedKey> {
  let keyID: Uint8Array;
  try {
    // A canonical standard-Base64 encoding of Apple's 32-byte key identifier
    // is always 44 characters. Reject oversized input before decoding it.
    if (keyId.length !== 44) {
      throw new TypeError("invalid key identifier length");
    }
    keyID = decodeKeyID(keyId);
  } catch {
    throw new RequestProblem(400, "invalid_key_id", "The App Attest key identifier is invalid.");
  }
  const environment = new TextEncoder().encode(`${configuration.environment}\0`);
  const routingInput = new Uint8Array(environment.byteLength + keyID.byteLength);
  routingInput.set(environment, 0);
  routingInput.set(keyID, environment.byteLength);
  const routingHash = await hmacSHA256(configuration.routingSecret, routingInput);
  const bucket = routingHash[0].toString(16).padStart(2, "0");
  return {
    keyId,
    keyID,
    limiterKey: encodeBase64URL(routingHash),
    stub: configuration.namespace.getByName(`app-attest-v1-${configuration.environment}-${bucket}`),
  };
}

async function enforceRateLimit(binding: RateLimitBinding, key: string): Promise<void> {
  let success: boolean;
  try {
    ({ success } = await binding.limit({ key }));
  } catch {
    throw new ServiceProblem(
      503,
      "authentication_unavailable",
      "Device authentication is temporarily unavailable.",
      "10",
    );
  }
  if (!success) {
    throw new ServiceProblem(429, "rate_limited", "Too many requests. Try again later.", "60");
  }
}

async function enforceEnrollmentRateLimit(
  request: Request,
  routedKey: RoutedKey,
  configuration: AppAttestConfiguration,
): Promise<void> {
  const address = request.headers.get("cf-connecting-ip") ?? "unknown";
  const addressHash = await hmacSHA256(configuration.routingSecret, new TextEncoder().encode(`ip\0${address}`));
  await Promise.all([
    enforceRateLimit(configuration.enrollLimiter, `key:${routedKey.limiterKey}`),
    enforceRateLimit(configuration.enrollLimiter, `ip:${encodeBase64URL(addressHash)}`),
  ]);
}

function responseForStateResult(
  result: AppAttestOperationResult | AppAttestChallengeResult,
  origin?: string,
): Response | null {
  if (result.ok) {
    return null;
  }
  const definitions: Record<string, { status: number; message: string }> = {
    key_not_registered: { status: 404, message: "The device key is not registered." },
    key_already_registered: { status: 409, message: "The device key is already registered." },
    challenge_used: { status: 409, message: "The device challenge is invalid or was already used." },
    challenge_expired: { status: 410, message: "The device challenge has expired." },
    invalid_attestation: { status: 401, message: "Device attestation could not be verified." },
    invalid_assertion: { status: 401, message: "Device assertion could not be verified." },
    counter_replay: { status: 409, message: "The device assertion was already used." },
    rate_limited: { status: 429, message: "The device has reached its analysis limit." },
    video_generation_limit: { status: 429, message: "The device has reached its daily AI video limit." },
    server_misconfigured: { status: 500, message: "The service is not configured correctly." },
  };
  const definition = definitions[result.code] ?? definitions.server_misconfigured;
  const headers: Record<string, string> = {};
  if (result.retryAfter !== undefined) {
    headers["retry-after"] = String(result.retryAfter);
  }
  return errorResponse(definition.status, result.code, definition.message, origin, headers);
}

function recordAppAttestDiagnostic(
  env: Env,
  operation: string,
  result: AppAttestOperationResult | AppAttestChallengeResult,
): void {
  if (result.ok || result.diagnostic === undefined) {
    return;
  }
  const diagnostic: AppAttestDiagnostic = result.diagnostic;
  try {
    env.APP_ATTEST_DIAGNOSTICS?.writeDataPoint({
      blobs: [
        operation,
        result.code,
        diagnostic.stage,
        diagnostic.errorName,
        diagnostic.message,
      ],
      doubles: [Date.now()],
    });
  } catch {
    // Operational telemetry must never alter the authentication response.
  }
}

function diagnosticForRPC(stage: string, error: unknown): AppAttestDiagnostic {
  const sanitize = (value: string, maximumLength: number): string => value
    .replace(/[\u0000-\u001f\u007f]+/gu, " ")
    .replace(/(?:[A-Za-z0-9+/_=-]{24,})/gu, "[redacted]")
    .replace(/\s+/gu, " ")
    .trim()
    .slice(0, maximumLength) || "unknown";
  return {
    stage: sanitize(stage, 64),
    errorName: sanitize(error instanceof Error ? error.name : typeof error, 64),
    message: sanitize(error instanceof Error ? error.message : "non_error_throw", 240),
  };
}

function recordOpenAIDiagnostic(env: Env, error: ServiceProblem): void {
  if (!error.code.startsWith("upstream_") && error.code !== "invalid_upstream_response") {
    return;
  }
  try {
    env.APP_ATTEST_DIAGNOSTICS?.writeDataPoint({
      blobs: [
        "openai",
        error.code,
        "responses_api",
        error.name,
        error.providerStatus !== undefined
          ? `provider_status_${error.providerStatus}`
          : error.providerDiagnostic ?? "no_provider_status",
      ],
      doubles: [Date.now()],
    });
  } catch {
    // Operational telemetry must never alter the analysis response.
  }
}

async function handleChallenge(
  request: Request,
  env: Env,
  configuration: AppAttestConfiguration,
  origin?: string,
): Promise<Response> {
  const { value } = await readJSONWithBytes(request, MAX_APP_ATTEST_BODY_BYTES);
  if (
    !isRecord(value) ||
    !hasExactKeys(value, ["purpose", "keyId"]) ||
    (value.purpose !== "attestation" && value.purpose !== "assertion") ||
    typeof value.keyId !== "string"
  ) {
    throw new RequestProblem(400, "invalid_request", "The challenge request is invalid.");
  }
  const routedKey = await routeKey(value.keyId, configuration);
  if (value.purpose === "attestation") {
    await enforceEnrollmentRateLimit(request, routedKey, configuration);
  } else {
    // One edge token is spent when the challenge is issued and another when
    // the resulting assertion reaches /analyze. The binding is therefore set
    // to twice the authoritative 30-request Durable Object quota.
    await enforceRateLimit(configuration.analyzeLimiter, `key:${routedKey.limiterKey}`);
  }
  let result: AppAttestChallengeResult;
  try {
    result = await routedKey.stub.issueChallenge({
      keyID: routedKey.keyID,
      purpose: value.purpose as AppAttestPurpose,
      nowMs: Date.now(),
    });
  } catch (error) {
    result = {
      ok: false,
      code: "server_misconfigured",
      diagnostic: diagnosticForRPC(`challenge_${value.purpose}_rpc`, error),
    };
  }
  recordAppAttestDiagnostic(env, `challenge_${value.purpose}`, result);
  if (!result.ok) {
    return responseForStateResult(result, origin) ?? errorResponse(
      500,
      "internal_error",
      "The service could not complete the request.",
      origin,
    );
  }
  return jsonResponse({ challenge: result.challenge, expiresAt: result.expiresAt }, 200, origin);
}

async function handleRegistration(
  request: Request,
  env: Env,
  configuration: AppAttestConfiguration,
  origin?: string,
): Promise<Response> {
  const { value } = await readJSONWithBytes(request, MAX_APP_ATTEST_BODY_BYTES);
  if (
    !isRecord(value) ||
    !hasExactKeys(value, ["keyId", "challenge", "attestationObject"]) ||
    typeof value.keyId !== "string" ||
    typeof value.challenge !== "string" ||
    typeof value.attestationObject !== "string" ||
    value.attestationObject.length > MAX_APP_ATTEST_BODY_BYTES
  ) {
    throw new RequestProblem(400, "invalid_request", "The registration request is invalid.");
  }
  const routedKey = await routeKey(value.keyId, configuration);
  await enforceEnrollmentRateLimit(request, routedKey, configuration);
  let challenge: Uint8Array;
  let attestationObject: Uint8Array;
  try {
    challenge = decodeBase64URL(value.challenge, 32);
    attestationObject = decodeBase64URL(value.attestationObject);
    if (attestationObject.byteLength === 0 || attestationObject.byteLength > 96 * 1024) {
      throw new TypeError("invalid attestation length");
    }
  } catch {
    throw new RequestProblem(400, "invalid_request", "The registration request is invalid.");
  }
  let result: AppAttestOperationResult;
  try {
    result = await routedKey.stub.registerKey({
      keyId: routedKey.keyId,
      keyID: routedKey.keyID,
      challenge,
      attestationObject,
      nowMs: Date.now(),
    });
  } catch (error) {
    result = {
      ok: false,
      code: "server_misconfigured",
      diagnostic: diagnosticForRPC("registration_rpc", error),
    };
  }
  recordAppAttestDiagnostic(env, "registration", result);
  const failure = responseForStateResult(result, origin);
  return failure ?? emptyResponse(204, origin);
}

async function performAnalysis(
  payload: ValidatedPayload,
  request: Request,
  env: Env,
  configuration: BaseConfiguration,
  fetcher: Fetcher,
  origin?: string,
): Promise<Response> {
  let analysis: Awaited<ReturnType<typeof analyzeWithOpenAI>>;
  try {
    analysis = await analyzeWithOpenAI(
      payload,
      configuration.apiKey,
      configuration.model,
      configuration.openAITimeoutMs,
      fetcher,
      request.signal,
    );
  } catch (error) {
    if (error instanceof ServiceProblem) {
      recordOpenAIDiagnostic(env, error);
    }
    throw error;
  }
  let publicPlan: PublicAIEditPlan;
  if (analysis.version === 3) {
    if (payload.baseline === undefined) {
      throw new ServiceProblem(502, "invalid_upstream_response", "The analysis provider returned an invalid response.");
    }
    publicPlan = {
      ...analysis,
      comparison: compareAICut(payload.baseline, payload.photos, analysis),
    };
  } else {
    publicPlan = analysis;
  }
  const body: PublicAnalysisResponse = {
    model: configuration.model,
    plan: publicPlan,
    retention: RETENTION,
  };
  return jsonResponse(body, 200, origin);
}

async function handleAnalyze(
  request: Request,
  env: Env,
  configuration: BaseConfiguration,
  origin: string | undefined,
  fetcher: Fetcher,
): Promise<Response> {
  const authorization = request.headers.get("authorization");
  if (
    configuration.authToken !== undefined &&
    authorization?.startsWith("Bearer ") === true &&
    (await constantTimeTokenMatch(authorization, configuration.authToken))
  ) {
    const { value } = await readJSONWithBytes(request, LIMITS.maxBodyBytes);
    return performAnalysis(validatePayload(value), request, env, configuration, fetcher, origin);
  }

  if (authorization?.startsWith(APP_ATTEST_AUTH_PREFIX) !== true) {
    return errorResponse(401, "unauthorized", "Authentication is required.", origin, {
      "www-authenticate": 'Bearer realm="tripreel", AppAttest realm="tripreel"',
    });
  }

  const appAttest = requireAppAttestConfiguration(env);
  const routedKey = await routeKey(authorization.slice(APP_ATTEST_AUTH_PREFIX.length), appAttest);
  await enforceRateLimit(appAttest.analyzeLimiter, `key:${routedKey.limiterKey}`);

  const challengeValue = request.headers.get("x-tripreel-challenge");
  const assertionValue = request.headers.get("x-tripreel-app-attest");
  if (
    challengeValue === null ||
    assertionValue === null ||
    assertionValue.length === 0 ||
    assertionValue.length > MAX_ASSERTION_HEADER_CHARACTERS
  ) {
    throw new RequestProblem(400, "invalid_request", "Device authentication headers are invalid.");
  }
  let challenge: Uint8Array;
  let assertionObject: Uint8Array;
  try {
    challenge = decodeBase64URL(challengeValue, 32);
    assertionObject = decodeBase64URL(assertionValue);
    if (assertionObject.byteLength === 0 || assertionObject.byteLength > 24 * 1024) {
      throw new TypeError("invalid assertion length");
    }
  } catch {
    throw new RequestProblem(400, "invalid_request", "Device authentication headers are invalid.");
  }

  const { value, bytes } = await readJSONWithBytes(request, LIMITS.maxBodyBytes);
  const payload = validatePayload(value);
  let result: AppAttestOperationResult;
  try {
    result = await routedKey.stub.authorizeAnalysis({
      keyID: routedKey.keyID,
      challenge,
      assertionObject,
      method: "POST",
      path: ANALYZE_PATH,
      bodyHash: await sha256(bytes),
      photoCount: payload.photos.length,
      videoGenerationCount: 0,
      nowMs: Date.now(),
    });
  } catch (error) {
    result = {
      ok: false,
      code: "server_misconfigured",
      diagnostic: diagnosticForRPC("assertion_rpc", error),
    };
  }
  recordAppAttestDiagnostic(env, "assertion", result);
  const failure = responseForStateResult(result, origin);
  if (failure !== null) {
    return failure;
  }
  return performAnalysis(payload, request, env, configuration, fetcher, origin);
}

async function handleVideo(
  request: Request,
  env: Env,
  configuration: BaseConfiguration,
  path: AppAttestProtectedPath,
  origin: string | undefined,
  fetcher: Fetcher,
): Promise<Response> {
  const videoConfiguration = requireVideoConfiguration(env);
  const authorization = request.headers.get("authorization");
  const hasBearer = configuration.authToken !== undefined &&
    authorization?.startsWith("Bearer ") === true &&
    await constantTimeTokenMatch(authorization, configuration.authToken);

  let routedKey: RoutedKey | undefined;
  let challenge: Uint8Array | undefined;
  let assertionObject: Uint8Array | undefined;
  if (!hasBearer) {
    if (authorization?.startsWith(APP_ATTEST_AUTH_PREFIX) !== true) {
      return errorResponse(401, "unauthorized", "Authentication is required.", origin, {
        "www-authenticate": 'Bearer realm="tripreel", AppAttest realm="tripreel"',
      });
    }
    const appAttest = requireAppAttestConfiguration(env);
    routedKey = await routeKey(authorization.slice(APP_ATTEST_AUTH_PREFIX.length), appAttest);
    await enforceRateLimit(appAttest.analyzeLimiter, `key:${routedKey.limiterKey}`);
    const challengeValue = request.headers.get("x-tripreel-challenge");
    const assertionValue = request.headers.get("x-tripreel-app-attest");
    if (
      challengeValue === null ||
      assertionValue === null ||
      assertionValue.length === 0 ||
      assertionValue.length > MAX_ASSERTION_HEADER_CHARACTERS
    ) {
      throw new RequestProblem(400, "invalid_request", "Device authentication headers are invalid.");
    }
    try {
      challenge = decodeBase64URL(challengeValue, 32);
      assertionObject = decodeBase64URL(assertionValue);
      if (assertionObject.byteLength === 0 || assertionObject.byteLength > 24 * 1024) {
        throw new TypeError("invalid assertion length");
      }
    } catch {
      throw new RequestProblem(400, "invalid_request", "Device authentication headers are invalid.");
    }
  }

  const maximumBodyBytes = path === VIDEO_GENERATE_PATH ? VIDEO_MAX_BODY_BYTES : 8 * 1024;
  const { value, bytes } = await readJSONWithBytes(request, maximumBodyBytes);
  const generateInput = path === VIDEO_GENERATE_PATH
    ? validateVideoGenerateRequest(value)
    : undefined;
  const jobInput = path === VIDEO_GENERATE_PATH
    ? undefined
    : validateVideoJobRequest(value);

  // Even the local-development bearer path gets a non-reversible identity so
  // its signed job token cannot be replayed after the credential changes.
  const subject = routedKey?.limiterKey ?? encodeBase64URL(
    await sha256(new TextEncoder().encode(configuration.authToken ?? "")),
  );
  let reservedVideoGeneration = false;
  if (routedKey !== undefined && challenge !== undefined && assertionObject !== undefined) {
    let result: AppAttestOperationResult;
    try {
      result = await routedKey.stub.authorizeAnalysis({
        keyID: routedKey.keyID,
        challenge,
        assertionObject,
        method: "POST",
        path,
        bodyHash: await sha256(bytes),
        photoCount: generateInput?.imagesBase64.length ?? 0,
        videoGenerationCount: path === VIDEO_GENERATE_PATH ? 1 : 0,
        nowMs: Date.now(),
      });
    } catch (error) {
      result = {
        ok: false,
        code: "server_misconfigured",
        diagnostic: diagnosticForRPC("video_assertion_rpc", error),
      };
    }
    recordAppAttestDiagnostic(env, "video_assertion", result);
    const failure = responseForStateResult(result, origin);
    if (failure !== null) return failure;
    reservedVideoGeneration = path === VIDEO_GENERATE_PATH;
  }

  if (path === VIDEO_GENERATE_PATH && generateInput !== undefined) {
    let result: Awaited<ReturnType<typeof submitVideo>>;
    try {
      result = await submitVideo(
        generateInput,
        subject,
        videoConfiguration,
        fetcher,
        request.signal,
      );
    } catch (error) {
      const shouldRefund = error instanceof ServiceProblem && [
        "upstream_rate_limited",
        "upstream_unavailable",
        "provider_rejected",
      ].includes(error.code);
      if (shouldRefund && reservedVideoGeneration && routedKey !== undefined) {
        try {
          await routedKey.stub.refundVideoGeneration({
            keyID: routedKey.keyID,
            nowMs: Date.now(),
          });
        } catch {
          // Fail closed on spending: a failed refund may inconvenience one
          // retry, but must never turn a provider error into extra allowance.
        }
      }
      throw error;
    }
    return jsonResponse({
      jobToken: result.jobToken,
      model: OPENROUTER_VIDEO_MODEL,
      status: result.status,
      retention: {
        memoriesStored: false,
        providerTemporary: true,
      },
    }, 202, origin);
  }
  if (path === VIDEO_STATUS_PATH && jobInput !== undefined) {
    const result = await pollVideo(
      jobInput,
      subject,
      videoConfiguration,
      fetcher,
      request.signal,
    );
    return jsonResponse(result, 200, origin);
  }
  if (path === VIDEO_CONTENT_PATH && jobInput !== undefined) {
    const upstream = await downloadVideo(
      jobInput,
      subject,
      videoConfiguration,
      fetcher,
      request.signal,
    );
    const headers: Record<string, string> = {
      "cache-control": "no-store, max-age=0",
      "content-type": upstream.headers.get("content-type") ?? "video/mp4",
      "content-security-policy": "default-src 'none'; frame-ancestors 'none'",
      "referrer-policy": "no-referrer",
      "x-content-type-options": "nosniff",
      ...corsHeaders(origin),
    };
    const length = upstream.headers.get("content-length");
    if (length !== null) headers["content-length"] = length;
    return new Response(upstream.body, { status: 200, headers });
  }
  throw new RequestProblem(404, "not_found", "Not found.");
}

export async function handleRequest(request: Request, env: Env, fetcher: Fetcher = fetch): Promise<Response> {
  let responseOrigin: string | undefined;
  try {
    const url = new URL(request.url);
    if (!SUPPORTED_PATHS.has(url.pathname) || url.search !== "") {
      return errorResponse(404, "not_found", "Not found.");
    }

    const configuration = requireBaseConfiguration(env);
    responseOrigin = requestCorsOrigin(request, configuration.corsOrigin);
    if (request.method === "OPTIONS") {
      return handlePreflight(request, responseOrigin);
    }
    if (request.method !== "POST") {
      return errorResponse(405, "method_not_allowed", "Only POST is allowed.", responseOrigin, {
        allow: "POST, OPTIONS",
      });
    }

    if (url.pathname === CHALLENGE_PATH) {
      return await handleChallenge(request, env, requireAppAttestConfiguration(env), responseOrigin);
    }
    if (url.pathname === REGISTER_PATH) {
      return await handleRegistration(request, env, requireAppAttestConfiguration(env), responseOrigin);
    }
    if (VIDEO_PATHS.has(url.pathname as AppAttestProtectedPath)) {
      return await handleVideo(
        request,
        env,
        configuration,
        url.pathname as AppAttestProtectedPath,
        responseOrigin,
        fetcher,
      );
    }
    return await handleAnalyze(request, env, configuration, responseOrigin, fetcher);
  } catch (error) {
    if (error instanceof RequestProblem) {
      return errorResponse(error.status, error.code, error.message, responseOrigin);
    }
    if (error instanceof ServiceProblem) {
      const headers: Record<string, string> = {};
      if (error.retryAfter !== undefined) {
        headers["retry-after"] = error.retryAfter;
      }
      return errorResponse(error.status, error.code, error.message, responseOrigin, headers);
    }
    return errorResponse(500, "internal_error", "The service could not complete the request.", responseOrigin);
  }
}
