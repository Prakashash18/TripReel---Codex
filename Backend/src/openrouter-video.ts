import { ServiceProblem } from "./openai.ts";
import { RequestProblem, validateJpegBase64 } from "./validation.ts";

export const OPENROUTER_VIDEO_MODEL = "bytedance/seedance-2.0" as const;
export const VIDEO_MAX_IMAGE_BYTES = 384 * 1024;
// Two metadata-free JPEGs plus base64 overhead and the bounded prompt.
export const VIDEO_MAX_BODY_BYTES = 1_080 * 1024;
const VIDEO_MAX_PROMPT_CHARACTERS = 600;
const VIDEO_JOB_TTL_MS = 30 * 60 * 1_000;
const VIDEO_MAX_PROVIDER_RESPONSE_BYTES = 64 * 1024;
const VIDEO_MAX_OUTPUT_BYTES = 100_000_000;
const OPENROUTER_VIDEO_URL = "https://openrouter.ai/api/v1/videos";

export interface VideoConfiguration {
  apiKey: string;
  signingSecret: string;
}

export interface ValidatedVideoGenerateRequest {
  imagesBase64: string[];
  prompt: string;
}

export interface ValidatedVideoJobRequest {
  jobToken: string;
}

type VideoJobStatus = "pending" | "in_progress" | "completed" | "failed" | "cancelled" | "expired";

interface ProviderJob {
  id: string;
  status: VideoJobStatus;
}

interface JobClaims {
  v: 1;
  j: string;
  s: string;
  exp: number;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasExactKeys(value: Record<string, unknown>, keys: readonly string[]): boolean {
  const actual = Object.keys(value);
  return actual.length === keys.length && keys.every((key) => Object.hasOwn(value, key));
}

function normalizedPlainText(value: unknown, maximum: number): string | null {
  if (typeof value !== "string" || /[\u0000-\u001f\u007f]/u.test(value)) return null;
  const normalized = value.replace(/\s+/gu, " ").trim();
  return normalized.length >= 10 && normalized.length <= maximum ? normalized : null;
}

export function validateVideoGenerateRequest(value: unknown): ValidatedVideoGenerateRequest {
  if (!isRecord(value)) {
    throw new RequestProblem(400, "invalid_request", "The AI video request is invalid.");
  }

  // Keep version 1 available while existing TestFlight builds age out. Version
  // 2 sends a beginning and an ending frame for a short story transition.
  let images: unknown[];
  if (
    value.version === 1 &&
    hasExactKeys(value, ["version", "imageBase64", "prompt"])
  ) {
    images = [value.imageBase64];
  } else if (
    value.version === 2 &&
    hasExactKeys(value, ["version", "imagesBase64", "prompt"]) &&
    Array.isArray(value.imagesBase64) &&
    value.imagesBase64.length >= 1 &&
    value.imagesBase64.length <= 2
  ) {
    images = value.imagesBase64;
  } else {
    throw new RequestProblem(400, "invalid_request", "The AI video request is invalid.");
  }

  const prompt = normalizedPlainText(value.prompt, VIDEO_MAX_PROMPT_CHARACTERS);
  if (prompt === null) {
    throw new RequestProblem(400, "invalid_prompt", "The AI video prompt is invalid.");
  }
  const imagesBase64 = images.map((image, index) => {
    validateJpegBase64(image, index, VIDEO_MAX_IMAGE_BYTES);
    return image as string;
  });
  if (new Set(imagesBase64).size !== imagesBase64.length) {
    throw new RequestProblem(400, "invalid_request", "Choose two different moments.");
  }
  return { imagesBase64, prompt };
}

export function validateVideoJobRequest(value: unknown): ValidatedVideoJobRequest {
  if (
    !isRecord(value) ||
    !hasExactKeys(value, ["version", "jobToken"]) ||
    value.version !== 1 ||
    typeof value.jobToken !== "string" ||
    value.jobToken.length < 32 ||
    value.jobToken.length > 1_024 ||
    !/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/u.test(value.jobToken)
  ) {
    throw new RequestProblem(400, "invalid_job", "The AI video job is invalid.");
  }
  return { jobToken: value.jobToken };
}

export function requireVideoConfiguration(env: {
  OPENROUTER_API_KEY?: string;
  APP_ATTEST_ROUTING_SECRET?: string;
}): VideoConfiguration {
  if (
    typeof env.OPENROUTER_API_KEY !== "string" ||
    env.OPENROUTER_API_KEY.length < 20 ||
    env.OPENROUTER_API_KEY.length > 512 ||
    typeof env.APP_ATTEST_ROUTING_SECRET !== "string" ||
    env.APP_ATTEST_ROUTING_SECRET.length < 32 ||
    env.APP_ATTEST_ROUTING_SECRET.length > 512
  ) {
    throw new ServiceProblem(500, "server_misconfigured", "The service is not configured correctly.");
  }
  return {
    apiKey: env.OPENROUTER_API_KEY,
    signingSecret: env.APP_ATTEST_ROUTING_SECRET,
  };
}

function encodeBase64URL(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/u, "");
}

function decodeBase64URL(value: string): Uint8Array {
  if (value.length === 0 || value.length % 4 === 1 || !/^[A-Za-z0-9_-]+$/u.test(value)) {
    throw new RequestProblem(400, "invalid_job", "The AI video job is invalid.");
  }
  const padding = "=".repeat((4 - (value.length % 4)) % 4);
  let binary: string;
  try {
    binary = atob(value.replaceAll("-", "+").replaceAll("_", "/") + padding);
  } catch {
    throw new RequestProblem(400, "invalid_job", "The AI video job is invalid.");
  }
  const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
  if (encodeBase64URL(bytes) !== value) {
    throw new RequestProblem(400, "invalid_job", "The AI video job is invalid.");
  }
  return bytes;
}

async function hmac(secret: string, data: Uint8Array): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  // Copy into an ArrayBuffer-backed view. TypeScript's generic Uint8Array can
  // otherwise also describe SharedArrayBuffer, which Web Crypto deliberately
  // does not accept as a BufferSource.
  const input = new Uint8Array(data.byteLength);
  input.set(data);
  return new Uint8Array(await crypto.subtle.sign("HMAC", key, input.buffer));
}

function equalBytes(left: Uint8Array, right: Uint8Array): boolean {
  if (left.byteLength !== right.byteLength) return false;
  let difference = 0;
  for (let index = 0; index < left.byteLength; index += 1) difference |= left[index] ^ right[index];
  return difference === 0;
}

async function createJobToken(
  jobID: string,
  subject: string,
  configuration: VideoConfiguration,
): Promise<string> {
  const claims: JobClaims = { v: 1, j: jobID, s: subject, exp: Date.now() + VIDEO_JOB_TTL_MS };
  const payload = new TextEncoder().encode(JSON.stringify(claims));
  const signature = await hmac(
    configuration.signingSecret,
    new Uint8Array([...new TextEncoder().encode("memories-video-job-v1\0"), ...payload]),
  );
  return `${encodeBase64URL(payload)}.${encodeBase64URL(signature)}`;
}

async function verifyJobToken(
  token: string,
  subject: string,
  configuration: VideoConfiguration,
): Promise<string> {
  const [payloadValue, signatureValue, extra] = token.split(".");
  if (extra !== undefined || payloadValue === undefined || signatureValue === undefined) {
    throw new RequestProblem(400, "invalid_job", "The AI video job is invalid.");
  }
  const payload = decodeBase64URL(payloadValue);
  const signature = decodeBase64URL(signatureValue);
  const expected = await hmac(
    configuration.signingSecret,
    new Uint8Array([...new TextEncoder().encode("memories-video-job-v1\0"), ...payload]),
  );
  if (!equalBytes(signature, expected)) {
    throw new RequestProblem(403, "invalid_job", "The AI video job is not available to this device.");
  }
  let claims: unknown;
  try {
    claims = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(payload));
  } catch {
    throw new RequestProblem(400, "invalid_job", "The AI video job is invalid.");
  }
  if (
    !isRecord(claims) ||
    !hasExactKeys(claims, ["v", "j", "s", "exp"]) ||
    claims.v !== 1 ||
    typeof claims.j !== "string" ||
    !/^[A-Za-z0-9_-]{1,200}$/u.test(claims.j) ||
    claims.s !== subject ||
    !Number.isSafeInteger(claims.exp) ||
    Number(claims.exp) < Date.now() ||
    Number(claims.exp) > Date.now() + VIDEO_JOB_TTL_MS + 60_000
  ) {
    throw new RequestProblem(403, "invalid_job", "The AI video job is not available to this device.");
  }
  return claims.j;
}

async function readProviderJSON(response: Response): Promise<Record<string, unknown>> {
  const length = response.headers.get("content-length");
  if (length !== null && Number(length) > VIDEO_MAX_PROVIDER_RESPONSE_BYTES) {
    throw new ServiceProblem(502, "invalid_upstream_response", "The video provider returned an invalid response.");
  }
  const reader = response.body?.getReader();
  if (reader === undefined) {
    throw new ServiceProblem(502, "invalid_upstream_response", "The video provider returned an invalid response.");
  }
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > VIDEO_MAX_PROVIDER_RESPONSE_BYTES) {
      await reader.cancel();
      throw new ServiceProblem(502, "invalid_upstream_response", "The video provider returned an invalid response.");
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    const value = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)) as unknown;
    if (!isRecord(value)) throw new Error("invalid response");
    return value;
  } catch {
    throw new ServiceProblem(502, "invalid_upstream_response", "The video provider returned an invalid response.");
  }
}

function providerStatus(value: unknown): VideoJobStatus | null {
  return value === "pending" || value === "in_progress" || value === "completed" ||
    value === "failed" || value === "cancelled" || value === "expired"
    ? value
    : null;
}

function providerFailure(response: Response): ServiceProblem {
  if (response.status === 429) {
    return new ServiceProblem(429, "upstream_rate_limited", "The AI video provider is busy.", "60");
  }
  if (response.status >= 500) {
    return new ServiceProblem(502, "upstream_unavailable", "The AI video provider is temporarily unavailable.");
  }
  return new ServiceProblem(502, "provider_rejected", "The AI video provider rejected the request.");
}

function providerHeaders(apiKey: string): Headers {
  const headers = new Headers();
  headers.set("authorization", `Bearer ${apiKey}`);
  headers.set("accept", "application/json");
  return headers;
}

export async function submitVideo(
  input: ValidatedVideoGenerateRequest,
  subject: string,
  configuration: VideoConfiguration,
  fetcher: typeof fetch,
  signal: AbortSignal,
): Promise<{ jobToken: string; status: VideoJobStatus }> {
  const headers = providerHeaders(configuration.apiKey);
  headers.set("content-type", "application/json");
  const frameImages = input.imagesBase64.map((imageBase64, index) => ({
    type: "image_url",
    image_url: { url: `data:image/jpeg;base64,${imageBase64}` },
    frame_type: index === 0 ? "first_frame" : "last_frame",
  }));
  const hasStoryPair = frameImages.length === 2;
  const response = await fetcher(OPENROUTER_VIDEO_URL, {
    method: "POST",
    headers,
    body: JSON.stringify({
      model: OPENROUTER_VIDEO_MODEL,
      prompt: hasStoryPair
        ? `Preserve both source memories faithfully. Create a natural story transition from the first real moment to the second without blending identities, replacing people, or inventing text. ${input.prompt}`
        : `Preserve the source memory faithfully. ${input.prompt}`,
      duration: hasStoryPair ? 6 : 4,
      resolution: "720p",
      aspect_ratio: "9:16",
      frame_images: frameImages,
      generate_audio: true,
    }),
    cache: "no-store",
    redirect: "manual",
    signal,
  });
  if (response.status !== 200 && response.status !== 202) throw providerFailure(response);
  const value = await readProviderJSON(response);
  const status = providerStatus(value.status);
  if (
    typeof value.id !== "string" ||
    !/^[A-Za-z0-9_-]{1,200}$/u.test(value.id) ||
    (status !== "pending" && status !== "in_progress")
  ) {
    throw new ServiceProblem(502, "invalid_upstream_response", "The video provider returned an invalid response.");
  }
  return {
    jobToken: await createJobToken(value.id, subject, configuration),
    status,
  };
}

export async function pollVideo(
  input: ValidatedVideoJobRequest,
  subject: string,
  configuration: VideoConfiguration,
  fetcher: typeof fetch,
  signal: AbortSignal,
): Promise<{ status: VideoJobStatus; progress: number }> {
  const jobID = await verifyJobToken(input.jobToken, subject, configuration);
  const response = await fetcher(`${OPENROUTER_VIDEO_URL}/${encodeURIComponent(jobID)}`, {
    method: "GET",
    headers: providerHeaders(configuration.apiKey),
    cache: "no-store",
    redirect: "manual",
    signal,
  });
  if (response.status !== 200) throw providerFailure(response);
  const value = await readProviderJSON(response);
  const status = providerStatus(value.status);
  if (value.id !== jobID || status === null) {
    throw new ServiceProblem(502, "invalid_upstream_response", "The video provider returned an invalid response.");
  }
  if (status === "failed" || status === "cancelled" || status === "expired") {
    throw new ServiceProblem(502, `generation_${status}`, "The AI video generation did not finish.");
  }
  const progress = status === "completed" ? 1 : status === "in_progress" ? 0.72 : 0.28;
  return { status, progress };
}

export async function downloadVideo(
  input: ValidatedVideoJobRequest,
  subject: string,
  configuration: VideoConfiguration,
  fetcher: typeof fetch,
  signal: AbortSignal,
): Promise<Response> {
  const jobID = await verifyJobToken(input.jobToken, subject, configuration);
  const response = await fetcher(`${OPENROUTER_VIDEO_URL}/${encodeURIComponent(jobID)}/content?index=0`, {
    method: "GET",
    headers: providerHeaders(configuration.apiKey),
    cache: "no-store",
    redirect: "manual",
    signal,
  });
  if (response.status !== 200 || response.body === null) throw providerFailure(response);
  const contentType = response.headers.get("content-type")?.toLowerCase() ?? "";
  const lengthValue = response.headers.get("content-length");
  const length = lengthValue === null ? null : Number(lengthValue);
  if (
    !contentType.startsWith("video/") ||
    (length !== null && (!Number.isSafeInteger(length) || length < 1 || length > VIDEO_MAX_OUTPUT_BYTES))
  ) {
    throw new ServiceProblem(502, "invalid_upstream_response", "The video provider returned an invalid video.");
  }
  return new Response(response.body, {
    status: 200,
    headers: {
      "cache-control": "no-store, max-age=0",
      "content-type": contentType,
      ...(length === null ? {} : { "content-length": String(length) }),
    },
  });
}
