export const DEFAULT_MODEL = "gpt-5.6-luna" as const;

export const LIMITS = Object.freeze({
  maxPhotos: 24,
  maxBodyBytes: 4_500_000,
  maxImageBytes: 128 * 1024,
  maxBatchImageBytes: 3 * 1024 * 1024,
  maxImageDimension: 1024,
  maxImagePixels: 1024 * 1024,
  maxIdCharacters: 64,
  maxSummaryCharacters: 240,
  bodyReadTimeoutMs: 15_000,
  defaultOpenAITimeoutMs: 30_000,
  minOpenAITimeoutMs: 5_000,
  maxOpenAITimeoutMs: 45_000,
  maxOpenAIResponseBytes: 128 * 1024,
});

export const AI_DIRECTIONS = [
  "better_story",
  "dynamic",
  "calm",
  "people",
  "surprise_me",
] as const;
export type AICutDirection = (typeof AI_DIRECTIONS)[number];

export const EDITORIAL_ROLES = [
  "opening",
  "establishing",
  "people",
  "scenery",
  "detail",
  "food",
  "bridge",
  "closing",
] as const;
export type EditorialRole = (typeof EDITORIAL_ROLES)[number];

export const EMPHASES = ["normal", "highlight"] as const;
export type Emphasis = (typeof EMPHASES)[number];

export const MOTIONS = [
  "automatic",
  "zoom_in",
  "zoom_out",
  "pan_left",
  "pan_right",
  "rise",
  "settle",
] as const;
export type Motion = (typeof MOTIONS)[number];

export interface PhotoInput {
  id: string;
  imageBase64: string;
}

export interface AIEditPlanItem {
  photoId: string;
  order: number;
  durationSeconds: number;
  role: EditorialRole;
  emphasis: Emphasis;
  motion: Motion;
}

export interface AIEditPlan {
  version: 1;
  direction: AICutDirection;
  summary: string;
  sequence: AIEditPlanItem[];
}

export interface ValidatedPayload {
  version: 1;
  direction: AICutDirection;
  photos: PhotoInput[];
}

export interface PublicAnalysisResponse {
  model: string;
  plan: AIEditPlan;
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

const PLAN_KEYS = ["version", "direction", "summary", "sequence"] as const;
const ITEM_KEYS = ["photoId", "order", "durationSeconds", "role", "emphasis", "motion"] as const;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasExactKeys(value: Record<string, unknown>, keys: readonly string[]): boolean {
  const actual = Object.keys(value);
  return actual.length === keys.length && keys.every((key) => Object.hasOwn(value, key));
}

/** Structured Outputs narrows shape; this remains the final untrusted-output gate. */
export function parseAIEditPlan(
  value: unknown,
  expectedIds: readonly string[],
  direction: AICutDirection,
): AIEditPlan | null {
  if (!isRecord(value) || !hasExactKeys(value, PLAN_KEYS)) {
    return null;
  }
  if (
    value.version !== 1 ||
    value.direction !== direction ||
    typeof value.summary !== "string" ||
    value.summary.trim().length < 1 ||
    value.summary.length > LIMITS.maxSummaryCharacters ||
    !Array.isArray(value.sequence) ||
    value.sequence.length < 1 ||
    value.sequence.length > expectedIds.length ||
    value.sequence.length > LIMITS.maxPhotos
  ) {
    return null;
  }

  const requested = new Set(expectedIds);
  const used = new Set<string>();
  const sequence: AIEditPlanItem[] = [];
  for (let index = 0; index < value.sequence.length; index += 1) {
    const item = value.sequence[index];
    if (!isRecord(item) || !hasExactKeys(item, ITEM_KEYS)) {
      return null;
    }
    if (
      typeof item.photoId !== "string" ||
      !requested.has(item.photoId) ||
      used.has(item.photoId) ||
      item.order !== index ||
      typeof item.durationSeconds !== "number" ||
      !Number.isFinite(item.durationSeconds) ||
      item.durationSeconds < 0.6 ||
      item.durationSeconds > 4 ||
      !EDITORIAL_ROLES.includes(item.role as EditorialRole) ||
      !EMPHASES.includes(item.emphasis as Emphasis) ||
      !MOTIONS.includes(item.motion as Motion)
    ) {
      return null;
    }
    used.add(item.photoId);
    sequence.push(item as unknown as AIEditPlanItem);
  }

  return {
    version: 1,
    direction,
    summary: value.summary,
    sequence,
  };
}

export function buildAIEditPlanSchema(
  expectedIds: readonly string[],
  direction: AICutDirection,
): Record<string, unknown> {
  return {
    type: "object",
    additionalProperties: false,
    properties: {
      version: { type: "integer", const: 1 },
      direction: { type: "string", const: direction },
      summary: { type: "string", minLength: 1, maxLength: LIMITS.maxSummaryCharacters },
      sequence: {
        type: "array",
        minItems: 1,
        maxItems: expectedIds.length,
        items: {
          type: "object",
          additionalProperties: false,
          properties: {
            photoId: { type: "string", enum: [...expectedIds] },
            order: { type: "integer", minimum: 0, maximum: Math.max(0, expectedIds.length - 1) },
            durationSeconds: { type: "number", minimum: 0.6, maximum: 4 },
            role: { type: "string", enum: [...EDITORIAL_ROLES] },
            emphasis: { type: "string", enum: [...EMPHASES] },
            motion: { type: "string", enum: [...MOTIONS] },
          },
          required: [...ITEM_KEYS],
        },
      },
    },
    required: [...PLAN_KEYS],
  };
}

export function configuredModel(raw: string | undefined): string | null {
  const candidate = raw?.trim() || DEFAULT_MODEL;
  return /^[A-Za-z0-9][A-Za-z0-9._:-]{0,99}$/u.test(candidate) ? candidate : null;
}
