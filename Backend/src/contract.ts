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
  maxStoryContextCharacters: 160,
  maxSceneLabels: 3,
  maxSceneLabelCharacters: 48,
  bodyReadTimeoutMs: 15_000,
  defaultOpenAITimeoutMs: 30_000,
  minOpenAITimeoutMs: 5_000,
  maxOpenAITimeoutMs: 45_000,
  maxOpenAIResponseBytes: 128 * 1024,
});

export const REQUEST_VERSIONS = [1, 2, 3] as const;
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

export const PHOTO_ORIENTATIONS = ["portrait", "landscape", "square"] as const;
export type PhotoOrientation = (typeof PHOTO_ORIENTATIONS)[number];

export const PHOTO_TIME_GAPS = ["start", "burst", "same_session", "same_day", "next_day", "later"] as const;
export type PhotoTimeGap = (typeof PHOTO_TIME_GAPS)[number];

export const PHOTO_SCORE_BANDS = ["low", "medium", "high"] as const;
export type PhotoScoreBand = (typeof PHOTO_SCORE_BANDS)[number];

export const PHOTO_CONTENT_KINDS = ["scenery", "people", "food", "moment"] as const;
export type PhotoContentKind = (typeof PHOTO_CONTENT_KINDS)[number];

export const FIRST_CUT_FRAME_STYLES = ["full_bleed", "portrait_matte", "cinematic", "postcard"] as const;
export type FirstCutFrameStyle = (typeof FIRST_CUT_FRAME_STYLES)[number];

export const FIRST_CUT_TITLE_KINDS = ["opening", "chapter", "ending"] as const;
export type FirstCutTitleKind = (typeof FIRST_CUT_TITLE_KINDS)[number];

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
  context?: PhotoEditorialContext;
}

export interface PhotoEditorialContext {
  captureIndex: number;
  dayIndex: number;
  timeGap: PhotoTimeGap;
  orientation: PhotoOrientation;
  contentKind: PhotoContentKind;
  peopleCount: number;
  memory: PhotoScoreBand;
  aesthetic: PhotoScoreBand;
  similarityGroup: string;
  sceneLabels: string[];
}

export interface FirstCutSequenceItem {
  photoId: string;
  order: number;
  durationSeconds: number;
  motion: Motion;
  frameStyle: FirstCutFrameStyle;
}

export interface FirstCutTitle {
  kind: FirstCutTitleKind;
  title: string;
  subtitle: string;
  style: TitleStyle;
  durationSeconds: number;
}

export interface FirstCutInput {
  photoCount: number;
  durationSeconds: number;
  omittedPhotoCount: number;
  sequence: FirstCutSequenceItem[];
  titles: FirstCutTitle[];
  soundtrackId: string;
  look: MontageLook;
  motionIntensity: MotionIntensity;
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

export const DIAGNOSIS_KINDS = [
  "weak_hook",
  "flat_pacing",
  "repetition",
  "missing_context",
  "weak_ending",
  "limited_variety",
] as const;
export type DiagnosisKind = (typeof DIAGNOSIS_KINDS)[number];

export interface AIEditDiagnosisIssue {
  kind: DiagnosisKind;
  title: string;
  detail: string;
  evidencePhotoIds: string[];
}

export interface AIEditDiagnosis {
  verdict: string;
  issues: AIEditDiagnosisIssue[];
}

export interface AIEditPlanV3 extends Omit<AIEditPlanV2, "version"> {
  version: 3;
  diagnosis: AIEditDiagnosis;
}

export interface AIEditComparison {
  firstCutPhotoCount: number;
  aiCutPhotoCount: number;
  restoredCount: number;
  removedCount: number;
  reorderedCount: number;
  retimedCount: number;
  motionChangedCount: number;
  titleChangedCount: number;
  soundtrackChanged: boolean;
  treatmentChanged: boolean;
  score: number;
  materiallyDifferent: boolean;
}

export type PublicAIEditPlan = AIEditPlanV1 | AIEditPlanV2 | (AIEditPlanV3 & {
  comparison: AIEditComparison;
});

export type AIEditPlan = AIEditPlanV1 | AIEditPlanV2 | AIEditPlanV3;

export interface ValidatedPayload {
  version: RequestVersion;
  direction: AICutDirection;
  storyContext?: string;
  baseline?: FirstCutInput;
  photos: PhotoInput[];
}

export interface PublicAnalysisResponse {
  model: string;
  plan: PublicAIEditPlan;
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
const PLAN_V3_KEYS = [...PLAN_V2_KEYS, "diagnosis"] as const;
const ITEM_KEYS = ["photoId", "order", "durationSeconds", "role", "emphasis", "motion"] as const;
const STORY_KEYS = ["title", "arc"] as const;
const TITLE_CARD_KEYS = ["title", "subtitle", "style", "durationSeconds"] as const;
const ENDING_KEYS = ["enabled", ...TITLE_CARD_KEYS] as const;
const SOUNDTRACK_KEYS = ["trackId", "reason"] as const;
const TREATMENT_KEYS = ["look", "motionIntensity", "reason"] as const;
const DIAGNOSIS_KEYS = ["verdict", "issues"] as const;
const DIAGNOSIS_ISSUE_KEYS = ["kind", "title", "detail", "evidencePhotoIds"] as const;

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

  const expectedPlanKeys = requestVersion === 3 ? PLAN_V3_KEYS : PLAN_V2_KEYS;
  if (
    !hasExactKeys(value, expectedPlanKeys) ||
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

  const directorPlan = {
    version: requestVersion,
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

  if (requestVersion === 2) {
    return directorPlan as AIEditPlanV2;
  }

  if (!isRecord(value.diagnosis) || !hasExactKeys(value.diagnosis, DIAGNOSIS_KEYS)) {
    return null;
  }
  const verdict = cleanText(value.diagnosis.verdict, 1, LIMITS.maxReasonCharacters);
  if (
    verdict === null ||
    !Array.isArray(value.diagnosis.issues) ||
    value.diagnosis.issues.length < 1 ||
    value.diagnosis.issues.length > 3
  ) {
    return null;
  }
  const requested = new Set(expectedIds);
  const issues: AIEditDiagnosisIssue[] = [];
  for (const issue of value.diagnosis.issues) {
    if (!isRecord(issue) || !hasExactKeys(issue, DIAGNOSIS_ISSUE_KEYS)) return null;
    const title = cleanText(issue.title, 1, LIMITS.maxShortTitleCharacters);
    const detail = cleanText(issue.detail, 1, LIMITS.maxReasonCharacters);
    if (
      !DIAGNOSIS_KINDS.includes(issue.kind as DiagnosisKind) ||
      title === null ||
      detail === null ||
      !Array.isArray(issue.evidencePhotoIds) ||
      issue.evidencePhotoIds.length > 3 ||
      !issue.evidencePhotoIds.every((id) => typeof id === "string" && requested.has(id))
    ) {
      return null;
    }
    issues.push({
      kind: issue.kind as DiagnosisKind,
      title,
      detail,
      evidencePhotoIds: [...new Set(issue.evidencePhotoIds as string[])],
    });
  }
  return {
    ...(directorPlan as Omit<AIEditPlanV3, "diagnosis">),
    version: 3,
    diagnosis: { verdict, issues },
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

  const properties: Record<string, unknown> = {
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
  };
  if (requestVersion === 3) {
    properties.diagnosis = {
      type: "object",
      additionalProperties: false,
      properties: {
        verdict: { type: "string", minLength: 1, maxLength: LIMITS.maxReasonCharacters },
        issues: {
          type: "array",
          minItems: 1,
          maxItems: 3,
          items: {
            type: "object",
            additionalProperties: false,
            properties: {
              kind: { type: "string", enum: [...DIAGNOSIS_KINDS] },
              title: { type: "string", minLength: 1, maxLength: LIMITS.maxShortTitleCharacters },
              detail: { type: "string", minLength: 1, maxLength: LIMITS.maxReasonCharacters },
              evidencePhotoIds: {
                type: "array",
                minItems: 0,
                maxItems: 3,
                items: { type: "string", enum: [...expectedIds] },
              },
            },
            required: [...DIAGNOSIS_ISSUE_KEYS],
          },
        },
      },
      required: [...DIAGNOSIS_KEYS],
    };
  }

  return {
    type: "object",
    additionalProperties: false,
    properties,
    required: requestVersion === 3 ? [...PLAN_V3_KEYS] : [...PLAN_V2_KEYS],
  };
}

export function configuredModel(raw: string | undefined): string | null {
  const candidate = raw?.trim() || DEFAULT_MODEL;
  return /^[A-Za-z0-9][A-Za-z0-9._:-]{0,99}$/u.test(candidate) ? candidate : null;
}
