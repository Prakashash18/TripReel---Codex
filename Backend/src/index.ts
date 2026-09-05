import { MODEL, RETENTION, type PublicAnalysisResponse } from "./contract.ts";
import { analyzeWithOpenAI, ServiceProblem } from "./openai.ts";
import { readJsonRequest, RequestProblem, validatePayload } from "./validation.ts";

export interface Env {
  OPENAI_API_KEY?: string;
  TRIPREEL_AUTH_TOKEN?: string;
  ALLOWED_ORIGIN?: string;
  OPENAI_TIMEOUT_MS?: string;
}

type Fetcher = typeof fetch;

const ANALYZE_PATH = "/v1/analyze";
const BASE_HEADERS: Readonly<Record<string, string>> = Object.freeze({
  "cache-control": "no-store, max-age=0",
  "content-type": "application/json; charset=utf-8",
  "content-security-policy": "default-src 'none'; frame-ancestors 'none'",
  "referrer-policy": "no-referrer",
  "x-content-type-options": "nosniff",
});

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
    "access-control-allow-headers": "Authorization, Content-Type",
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

function errorResponse(
  status: number,
  code: string,
  message: string,
  origin?: string,
  extraHeaders: Readonly<Record<string, string>> = {},
): Response {
  return jsonResponse({ error: { code, message } }, status, origin, extraHeaders);
}

function requireConfiguration(env: Env): { apiKey: string; authToken: string; corsOrigin?: string } {
  if (
    typeof env.OPENAI_API_KEY !== "string" ||
    env.OPENAI_API_KEY.length < 20 ||
    env.OPENAI_API_KEY.length > 512 ||
    typeof env.TRIPREEL_AUTH_TOKEN !== "string" ||
    env.TRIPREEL_AUTH_TOKEN.length < 32 ||
    env.TRIPREEL_AUTH_TOKEN.length > 512
  ) {
    throw new ServiceProblem(500, "server_misconfigured", "The service is not configured correctly.");
  }
  return {
    apiKey: env.OPENAI_API_KEY,
    authToken: env.TRIPREEL_AUTH_TOKEN,
    corsOrigin: configuredCorsOrigin(env.ALLOWED_ORIGIN),
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
  if (requestedHeaders.some((header) => header !== "authorization" && header !== "content-type")) {
    return errorResponse(403, "preflight_not_allowed", "CORS preflight is not allowed.", origin);
  }

  return new Response(null, {
    status: 204,
    headers: {
      "cache-control": "no-store, max-age=0",
      ...corsHeaders(origin),
    },
  });
}

export async function handleRequest(request: Request, env: Env, fetcher: Fetcher = fetch): Promise<Response> {
  let responseOrigin: string | undefined;
  try {
    const url = new URL(request.url);
    if (url.pathname !== ANALYZE_PATH || url.search !== "") {
      return errorResponse(404, "not_found", "Not found.");
    }

    const configuration = requireConfiguration(env);
    responseOrigin = requestCorsOrigin(request, configuration.corsOrigin);

    if (request.method === "OPTIONS") {
      return handlePreflight(request, responseOrigin);
    }
    if (request.method !== "POST") {
      return errorResponse(405, "method_not_allowed", "Only POST is allowed.", responseOrigin, {
        allow: "POST, OPTIONS",
      });
    }

    if (!(await constantTimeTokenMatch(request.headers.get("authorization"), configuration.authToken))) {
      return errorResponse(401, "unauthorized", "Authentication is required.", responseOrigin, {
        "www-authenticate": 'Bearer realm="tripreel"',
      });
    }

    const rawBody = await readJsonRequest(request);
    const { photos } = validatePayload(rawBody);
    const analysis = await analyzeWithOpenAI(
      photos,
      configuration.apiKey,
      env.OPENAI_TIMEOUT_MS,
      fetcher,
      request.signal,
    );

    const body: PublicAnalysisResponse = {
      model: MODEL,
      photos: analysis.photos,
      retention: RETENTION,
    };
    return jsonResponse(body, 200, responseOrigin);
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

export default {
  fetch(request: Request, env: Env): Promise<Response> {
    return handleRequest(request, env);
  },
};
