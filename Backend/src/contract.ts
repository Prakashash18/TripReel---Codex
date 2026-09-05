export const MODEL = "gpt-5.6-luna" as const;

export const LIMITS = Object.freeze({
  maxPhotos: 12,
  maxBodyBytes: 4_500_000,
  maxImageBytes: 256 * 1024,
  maxBatchImageBytes: 3 * 1024 * 1024,
  maxImageDimension: 1024,
  maxImagePixels: 1024 * 1024,
  maxIdCharacters: 64,
  maxReasonCharacters: 200,
  bodyReadTimeoutMs: 15_000,
  defaultOpenAITimeoutMs: 30_000,
  minOpenAITimeoutMs: 5_000,
  maxOpenAITimeoutMs: 45_000,
  maxOpenAIResponseBytes: 128 * 1024,
});

export type Action = "keep" | "review" | "discard";

export const SAFE_REASONS = [
  "Strong travel-reel candidate.",
  "Usable travel photo.",
  "People-focused memory.",
  "Food or drink is the main subject.",
  "Document or text-heavy image.",
  "Screen capture rather than a camera photo.",
  "Image quality is too low for a reel.",
  "Mixed signals; manual review recommended.",
] as const;

export type SafeReason = (typeof SAFE_REASONS)[number];

export interface PhotoInput {
  id: string;
  imageBase64: string;
}

export interface AnalysisPhoto {
  id: string;
  scenic: number;
  people: number;
  group: number;
  food: number;
  document: number;
  screenshot: number;
  lowQuality: number;
  confidence: number;
  action: Action;
  reason: SafeReason;
}

export interface AnalysisOutput {
  photos: AnalysisPhoto[];
}

export interface PublicAnalysisResponse extends AnalysisOutput {
  model: typeof MODEL;
  retention: {
    proxyStored: false;
    openAIStore: false;
    abuseMonitoring: "up_to_30_days_unless_zdr";
  };
}

export const RETENTION: PublicAnalysisResponse["retention"] = Object.freeze({
  proxyStored: false,
  openAIStore: false,
  abuseMonitoring: "up_to_30_days_unless_zdr",
});

const ANALYSIS_KEYS = [
  "id",
  "scenic",
  "people",
  "group",
  "food",
  "document",
  "screenshot",
  "lowQuality",
  "confidence",
  "action",
  "reason",
] as const;

const SCORE_KEYS = [
  "scenic",
  "people",
  "group",
  "food",
  "document",
  "screenshot",
  "lowQuality",
  "confidence",
] as const;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasExactKeys(value: Record<string, unknown>, keys: readonly string[]): boolean {
  const actual = Object.keys(value);
  return actual.length === keys.length && keys.every((key) => Object.hasOwn(value, key));
}

/** Treat upstream model output as untrusted even though Structured Outputs is enabled. */
export function parseAnalysisOutput(value: unknown, expectedIds: readonly string[]): AnalysisOutput | null {
  if (!isRecord(value) || !hasExactKeys(value, ["photos"]) || !Array.isArray(value.photos)) {
    return null;
  }

  if (value.photos.length !== expectedIds.length) {
    return null;
  }

  const photos: AnalysisPhoto[] = [];
  for (let index = 0; index < value.photos.length; index += 1) {
    const item = value.photos[index];
    if (!isRecord(item) || !hasExactKeys(item, ANALYSIS_KEYS)) {
      return null;
    }

    if (item.id !== expectedIds[index]) {
      return null;
    }

    for (const key of SCORE_KEYS) {
      const score = item[key];
      if (typeof score !== "number" || !Number.isFinite(score) || score < 0 || score > 1) {
        return null;
      }
    }

    if (item.action !== "keep" && item.action !== "review" && item.action !== "discard") {
      return null;
    }

    if (
      typeof item.reason !== "string" ||
      item.reason.length > LIMITS.maxReasonCharacters ||
      !SAFE_REASONS.includes(item.reason as SafeReason)
    ) {
      return null;
    }

    photos.push(item as unknown as AnalysisPhoto);
  }

  return { photos };
}

export function buildAnalysisSchema(expectedIds: readonly string[]): Record<string, unknown> {
  const score = { type: "number", minimum: 0, maximum: 1 };

  return {
    type: "object",
    additionalProperties: false,
    properties: {
      photos: {
        type: "array",
        minItems: expectedIds.length,
        maxItems: expectedIds.length,
        items: {
          type: "object",
          additionalProperties: false,
          properties: {
            id: { type: "string", enum: [...expectedIds] },
            scenic: score,
            people: score,
            group: score,
            food: score,
            document: score,
            screenshot: score,
            lowQuality: score,
            confidence: score,
            action: { type: "string", enum: ["keep", "review", "discard"] },
            reason: {
              type: "string",
              enum: [...SAFE_REASONS],
            },
          },
          required: [...ANALYSIS_KEYS],
        },
      },
    },
    required: ["photos"],
  };
}
