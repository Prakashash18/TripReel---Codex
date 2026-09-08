export const DEFAULT_MODEL = "gpt-5.6-luna" as const;

export const LIMITS = Object.freeze({
  maxPhotos: 36,
  maxBodyBytes: 6_500_000,
  maxImageBytes: 128 * 1024,
  maxBatchImageBytes: 4_500_000,
  maxImageDimension: 1024,
  maxImagePixels: 1024 * 1024,
  maxIdCharacters: 64,
  maxSummaryCharacters: 240,
  maxShortTitleCharacters: 60,
  maxSubtitleCharacters: 100,
  maxReasonCharacters: 180,
  bodyReadTimeoutMs: 15_000,
  defaultOpenAITimeoutMs: 30_000,
  minOpenAITimeoutMs: 5_000,
  maxOpenAITimeoutMs: 45_000,
  maxOpenAIResponseBytes: 128 * 1024,
});

export const REQUEST_VERSIONS = [1, 2] as const;
export type RequestVersion = (typeof REQUEST_VERSIONS)[number];

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

export const LOCAL_SELECTIONS = ["first_cut", "more_photos"] as const;
export type LocalSelection = (typeof LOCAL_SELECTIONS)[number];

export const TITLE_STYLES = ["editorial", "clean", "bold"] as const;
export type TitleStyle = (typeof TITLE_STYLES)[number];

export const SOUNDTRACK_IDS = [
  "wanderlust",
  "simplicity",
  "castles",
  "long-way-home",
] as const;
export type SoundtrackID = (typeof SOUNDTRACK_IDS)[number];

export const MONTAGE_LOOKS = ["story", "cinema", "journal", "clean"] as const;
export type MontageLook = (typeof MONTAGE_LOOKS)[number];

export const MOTION_INTENSITIES = ["still", "gentle", "expressive"] as const;
export type MotionIntensity = (typeof MOTION_INTENSITIES)[number];

export interface PhotoInput {
  id: string;
  imageBase64: string;
  localSelection: LocalSelection;
}

export interface AIEditPlanItem {
  photoId: string;
  order: number;
  durationSeconds: number;
  role: EditorialRole;
  emphasis: Emphasis;
  motion: Motion;
}

export interface AIEditPlanV1 {
  version: 1;
  direction: AICutDirection;
  summary: string;
  sequence: AIEditPlanItem[];
}

export interface AIEditStory {
  title: string;
  arc: string;
}

export interface AIEditTitleCard {
  title: string;
  subtitle: string;
  style: TitleStyle;
  durationSeconds: number;
}

export interface AIEditEnding extends AIEditTitleCard {
  enabled: boolean;
}

export interface AIEditSoundtrack {
  trackId: SoundtrackID;
  reason: string;
}

export interface AIEditTreatment {
  look: MontageLook;
  motionIntensity: MotionIntensity;
  reason: string;
}

export interface AIEditPlanV2 {
  version: 2;
  direction: AICutDirection;
  summary: string;
  story: AIEditStory;
  hook: AIEditTitleCard;
  ending: AIEditEnding;
  soundtrack: AIEditSoundtrack;
  treatment: AIEditTreatment;
  sequence: AIEditPlanItem[];
}

export type AIEditPlan = AIEditPlanV1 | AIEditPlanV2;

export interface ValidatedPayload {
  version: RequestVersion;
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

const PLAN_V1_KEYS = ["version", "direction", "summary", "sequence"] as const;
const PLAN_V2_KEYS = [
  "version",
  "direction",
  "summary",
  "story",
  "hook",
  "ending",
  "soundtrack",
  "treatment",
  "sequence",
] as const;
const ITEM_KEYS = ["photoId", "order", "durationSeconds", "role", "emphasis", "motion"] as const;
const STORY_KEYS = ["title", "arc"] as const;
const TITLE_CARD_KEYS = ["title", "subtitle", "style", "durationSeconds"] as const;
const ENDING_KEYS = ["enabled", ...TITLE_CARD_KEYS] as const;
const SOUNDTRACK_KEYS = ["trackId", "reason"] as const;
const TREATMENT_KEYS = ["look", "motionIntensity", "reason"] as const;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasExactKeys(value: Record<string, unknown>, keys: readonly string[]): boolean {
  const actual = Object.keys(value);
  return actual.length === keys.length && keys.every((key) => Object.hasOwn(value, key));
}

function cleanText(
  value: unknown,
  minimumLength: number,
  maximumLength: number,
): string | null {
  if (typeof value !== "string" || /[\u0000-\u001f\u007f]/u.test(value)) return null;
  const result = value.replace(/\s+/gu, " ").trim();
  return result.length >= minimumLength && result.length <= maximumLength ? result : null;
}

function parseDuration(value: unknown, minimum = 1, maximum = 4): number | null {
  return typeof value === "number" && Number.isFinite(value) && value >= minimum && value <= maximum
    ? value
    : null;
}

export function minimumSequenceCount(
  photoCount: number,
  direction: AICutDirection,
): number {
  if (photoCount <= 1) return Math.max(0, photoCount);
  const coverage = direction === "people" ? 0.75 : 0.60;
  return Math.min(photoCount, Math.max(2, Math.ceil(photoCount * coverage)));
}

function parseSequence(
  value: unknown,
  expectedIds: readonly string[],
  direction: AICutDirection,
): AIEditPlanItem[] | null {
  if (
    !Array.isArray(value) ||
    value.length < minimumSequenceCount(expectedIds.length, direction) ||
    value.length > expectedIds.length ||
    value.length > LIMITS.maxPhotos
  ) {
    return null;
  }

  const requested = new Set(expectedIds);
  const used = new Set<string>();
  const sequence: AIEditPlanItem[] = [];
  for (const item of value) {
    if (!isRecord(item) || !hasExactKeys(item, ITEM_KEYS)) return null;
    if (
      typeof item.photoId !== "string" ||
      !requested.has(item.photoId) ||
      typeof item.order !== "number" ||
      !Number.isInteger(item.order) ||
      item.order < 0 ||
      item.order >= expectedIds.length ||
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
    if (used.has(item.photoId)) continue;
    used.add(item.photoId);
    sequence.push({
      photoId: item.photoId,
      order: sequence.length,
      durationSeconds: item.durationSeconds,
      role: item.role as EditorialRole,
      emphasis: item.emphasis as Emphasis,
      motion: item.motion as Motion,
    });
  }
  return sequence.length >= minimumSequenceCount(expectedIds.length, direction) ? sequence : null;
}

/** Structured Outputs narrows shape; this remains the final untrusted-output gate. */
export function parseAIEditPlan(
  value: unknown,
  expectedIds: readonly string[],
  direction: AICutDirection,
  requestVersion: RequestVersion = 1,
): AIEditPlan | null {
  if (!isRecord(value)) return null;

  const summary = cleanText(value.summary, 1, LIMITS.maxSummaryCharacters);
  const sequence = parseSequence(value.sequence, expectedIds, direction);
  if (value.version !== requestVersion || value.direction !== direction || summary === null || sequence === null) {
    return null;
  }

  if (requestVersion === 1) {
    if (!hasExactKeys(value, PLAN_V1_KEYS)) return null;
    return { version: 1, direction, summary, sequence };
  }

  if (
    !hasExactKeys(value, PLAN_V2_KEYS) ||
    !isRecord(value.story) || !hasExactKeys(value.story, STORY_KEYS) ||
    !isRecord(value.hook) || !hasExactKeys(value.hook, TITLE_CARD_KEYS) ||
    !isRecord(value.ending) || !hasExactKeys(value.ending, ENDING_KEYS) ||
    !isRecord(value.soundtrack) || !hasExactKeys(value.soundtrack, SOUNDTRACK_KEYS) ||
    !isRecord(value.treatment) || !hasExactKeys(value.treatment, TREATMENT_KEYS)
  ) {
    return null;
  }

  const storyTitle = cleanText(value.story.title, 1, LIMITS.maxShortTitleCharacters);
  const storyArc = cleanText(value.story.arc, 1, LIMITS.maxSummaryCharacters);
  const hookTitle = cleanText(value.hook.title, 1, LIMITS.maxShortTitleCharacters);
  const hookSubtitle = cleanText(value.hook.subtitle, 0, LIMITS.maxSubtitleCharacters);
  const hookDuration = parseDuration(value.hook.durationSeconds);
  const endingEnabled = value.ending.enabled;
  const endingTitle = cleanText(
    value.ending.title,
    endingEnabled === true ? 1 : 0,
    LIMITS.maxShortTitleCharacters,
  );
  const endingSubtitle = cleanText(value.ending.subtitle, 0, LIMITS.maxSubtitleCharacters);
  const endingDuration = parseDuration(value.ending.durationSeconds);
  const soundtrackReason = cleanText(value.soundtrack.reason, 1, LIMITS.maxReasonCharacters);
  const treatmentReason = cleanText(value.treatment.reason, 1, LIMITS.maxReasonCharacters);

  if (
    storyTitle === null || storyArc === null || hookTitle === null || hookSubtitle === null || hookDuration === null ||
    typeof endingEnabled !== "boolean" || endingTitle === null || endingSubtitle === null || endingDuration === null ||
    !TITLE_STYLES.includes(value.hook.style as TitleStyle) ||
    !TITLE_STYLES.includes(value.ending.style as TitleStyle) ||
    !SOUNDTRACK_IDS.includes(value.soundtrack.trackId as SoundtrackID) || soundtrackReason === null ||
    !MONTAGE_LOOKS.includes(value.treatment.look as MontageLook) ||
    !MOTION_INTENSITIES.includes(value.treatment.motionIntensity as MotionIntensity) ||
    treatmentReason === null
  ) {
    return null;
  }

  return {
    version: 2,
    direction,
    summary,
    story: { title: storyTitle, arc: storyArc },
    hook: {
      title: hookTitle,
      subtitle: hookSubtitle,
      style: value.hook.style as TitleStyle,
      durationSeconds: hookDuration,
    },
    ending: {
      enabled: endingEnabled,
      title: endingTitle,
      subtitle: endingSubtitle,
      style: value.ending.style as TitleStyle,
      durationSeconds: endingDuration,
    },
    soundtrack: {
      trackId: value.soundtrack.trackId as SoundtrackID,
      reason: soundtrackReason,
    },
    treatment: {
      look: value.treatment.look as MontageLook,
      motionIntensity: value.treatment.motionIntensity as MotionIntensity,
      reason: treatmentReason,
    },
    sequence,
  };
}

function sequenceSchema(
  expectedIds: readonly string[],
  direction: AICutDirection,
): Record<string, unknown> {
  return {
    type: "array",
    minItems: minimumSequenceCount(expectedIds.length, direction),
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
  };
}

function titleCardSchema(includeEnabled: boolean): Record<string, unknown> {
  const properties: Record<string, unknown> = {
    title: { type: "string", minLength: includeEnabled ? 0 : 1, maxLength: LIMITS.maxShortTitleCharacters },
    subtitle: { type: "string", minLength: 0, maxLength: LIMITS.maxSubtitleCharacters },
    style: { type: "string", enum: [...TITLE_STYLES] },
    durationSeconds: { type: "number", minimum: 1, maximum: 4 },
  };
  if (includeEnabled) properties.enabled = { type: "boolean" };
  return {
    type: "object",
    additionalProperties: false,
    properties,
    required: includeEnabled ? [...ENDING_KEYS] : [...TITLE_CARD_KEYS],
  };
}

export function buildAIEditPlanSchema(
  expectedIds: readonly string[],
  direction: AICutDirection,
  requestVersion: RequestVersion = 1,
): Record<string, unknown> {
  const commonProperties = {
    version: { type: "integer", const: requestVersion },
    direction: { type: "string", const: direction },
    summary: { type: "string", minLength: 1, maxLength: LIMITS.maxSummaryCharacters },
  };
  if (requestVersion === 1) {
    return {
      type: "object",
      additionalProperties: false,
      properties: {
        ...commonProperties,
        sequence: sequenceSchema(expectedIds, direction),
      },
      required: [...PLAN_V1_KEYS],
    };
  }

  return {
    type: "object",
    additionalProperties: false,
    properties: {
      ...commonProperties,
      story: {
        type: "object",
        additionalProperties: false,
        properties: {
          title: { type: "string", minLength: 1, maxLength: LIMITS.maxShortTitleCharacters },
          arc: { type: "string", minLength: 1, maxLength: LIMITS.maxSummaryCharacters },
        },
        required: [...STORY_KEYS],
      },
      hook: titleCardSchema(false),
      ending: titleCardSchema(true),
      soundtrack: {
        type: "object",
        additionalProperties: false,
        properties: {
          trackId: { type: "string", enum: [...SOUNDTRACK_IDS] },
          reason: { type: "string", minLength: 1, maxLength: LIMITS.maxReasonCharacters },
        },
        required: [...SOUNDTRACK_KEYS],
      },
      treatment: {
        type: "object",
        additionalProperties: false,
        properties: {
          look: { type: "string", enum: [...MONTAGE_LOOKS] },
          motionIntensity: { type: "string", enum: [...MOTION_INTENSITIES] },
          reason: { type: "string", minLength: 1, maxLength: LIMITS.maxReasonCharacters },
        },
        required: [...TREATMENT_KEYS],
      },
      sequence: sequenceSchema(expectedIds, direction),
    },
    required: [...PLAN_V2_KEYS],
  };
}

export function configuredModel(raw: string | undefined): string | null {
  const candidate = raw?.trim() || DEFAULT_MODEL;
  return /^[A-Za-z0-9][A-Za-z0-9._:-]{0,99}$/u.test(candidate) ? candidate : null;
}
