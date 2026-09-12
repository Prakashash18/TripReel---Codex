import {
  AI_DIRECTIONS,
  FIRST_CUT_FRAME_STYLES,
  FIRST_CUT_TITLE_KINDS,
  LIMITS,
  LOCAL_SELECTIONS,
  MEDIA_KINDS,
  MONTAGE_LOOKS,
  MOTIONS,
  MOTION_INTENSITIES,
  PHOTO_CONTENT_KINDS,
  PHOTO_ORIENTATIONS,
  PHOTO_SCORE_BANDS,
  PHOTO_TIME_GAPS,
  REQUEST_VERSIONS,
  SOUNDTRACK_IDS,
  TITLE_STYLES,
  VIDEO_MOTION_BANDS,
  type AICutDirection,
  type FirstCutInput,
  type FirstCutTitleKind,
  type LocalSelection,
  type PhotoInput,
  type PhotoEditorialContext,
  type PhotoContentKind,
  type PhotoOrientation,
  type PhotoScoreBand,
  type PhotoTimeGap,
  type RequestVersion,
  type ValidatedPayload,
} from "./contract.ts";

export class RequestProblem extends Error {
  readonly status: number;
  readonly code: string;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.name = "RequestProblem";
    this.status = status;
    this.code = code;
  }
}

const ID_PATTERN = /^p(?:0|[1-9][0-9]?)$/u;
const BASE64_PATTERN = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;
const SOF_MARKERS = new Set([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf]);
const SCENE_LABEL_PATTERN = /^[A-Za-z0-9][A-Za-z0-9 _-]{0,47}$/u;
const SIMILARITY_GROUP_PATTERN = /^(?:|g(?:0|[1-9][0-9]?))$/u;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasExactKeys(value: Record<string, unknown>, keys: readonly string[]): boolean {
  const actual = Object.keys(value);
  return actual.length === keys.length && keys.every((key) => Object.hasOwn(value, key));
}

function cleanPlainText(value: unknown, maximum: number, allowEmpty = false): string | null {
  if (typeof value !== "string" || /[\u0000-\u001f\u007f]/u.test(value)) return null;
  const normalized = value.replace(/\s+/gu, " ").trim();
  if ((!allowEmpty && normalized.length === 0) || normalized.length > maximum) return null;
  return normalized;
}

function validatePhotoContext(value: unknown, photoIndex: number): PhotoEditorialContext {
  const legacyKeys = [
    "captureIndex", "dayIndex", "timeGap", "orientation", "contentKind",
    "peopleCount", "memory", "aesthetic", "similarityGroup", "sceneLabels",
  ] as const;
  const mixedMediaKeys = [
    ...legacyKeys,
    "mediaKind", "clipDurationSeconds", "hasOriginalAudio", "videoMotion",
  ] as const;
  if (!isRecord(value)) {
    throw new RequestProblem(400, "invalid_photo_context", `photos[${photoIndex}].context is invalid.`);
  }
  // The production Worker is deployed before the matching iOS build. Keep the
  // prior photo-only context valid during that rollout, while still rejecting
  // unknown keys and normalizing it to the new contract.
  const hasMixedMediaContext = hasExactKeys(value, mixedMediaKeys);
  const hasLegacyPhotoContext = hasExactKeys(value, legacyKeys);
  const mediaKind = hasMixedMediaContext ? value.mediaKind : "photo";
  const clipDurationSeconds = hasMixedMediaContext ? value.clipDurationSeconds : 0;
  const hasOriginalAudio = hasMixedMediaContext ? value.hasOriginalAudio : false;
  const videoMotion = hasMixedMediaContext ? value.videoMotion : "still";

  if (
    (!hasMixedMediaContext && !hasLegacyPhotoContext) ||
    !Number.isInteger(value.captureIndex) || Number(value.captureIndex) < 0 || Number(value.captureIndex) > 100_000 ||
    !Number.isInteger(value.dayIndex) || Number(value.dayIndex) < 0 || Number(value.dayIndex) > 365 ||
    !PHOTO_TIME_GAPS.includes(value.timeGap as PhotoTimeGap) ||
    !PHOTO_ORIENTATIONS.includes(value.orientation as PhotoOrientation) ||
    !PHOTO_CONTENT_KINDS.includes(value.contentKind as PhotoContentKind) ||
    !Number.isInteger(value.peopleCount) || Number(value.peopleCount) < 0 || Number(value.peopleCount) > 20 ||
    !PHOTO_SCORE_BANDS.includes(value.memory as PhotoScoreBand) ||
    !PHOTO_SCORE_BANDS.includes(value.aesthetic as PhotoScoreBand) ||
    !MEDIA_KINDS.includes(mediaKind as never) ||
    typeof clipDurationSeconds !== "number" || !Number.isFinite(clipDurationSeconds) ||
    Number(clipDurationSeconds) < 0 || Number(clipDurationSeconds) > 4 ||
    typeof hasOriginalAudio !== "boolean" ||
    !VIDEO_MOTION_BANDS.includes(videoMotion as never) ||
    (mediaKind === "photo" && (
      Number(clipDurationSeconds) !== 0 || hasOriginalAudio !== false || videoMotion !== "still"
    )) ||
    (mediaKind === "video" && (
      Number(clipDurationSeconds) < 0.8
    )) ||
    typeof value.similarityGroup !== "string" || !SIMILARITY_GROUP_PATTERN.test(value.similarityGroup) ||
    !Array.isArray(value.sceneLabels) || value.sceneLabels.length > LIMITS.maxSceneLabels ||
    !value.sceneLabels.every((label) => typeof label === "string" && SCENE_LABEL_PATTERN.test(label))
  ) {
    throw new RequestProblem(400, "invalid_photo_context", `photos[${photoIndex}].context is invalid.`);
  }
  return {
    captureIndex: Number(value.captureIndex),
    dayIndex: Number(value.dayIndex),
    timeGap: value.timeGap as PhotoTimeGap,
    orientation: value.orientation as PhotoOrientation,
    contentKind: value.contentKind as PhotoContentKind,
    peopleCount: Number(value.peopleCount),
    memory: value.memory as PhotoScoreBand,
    aesthetic: value.aesthetic as PhotoScoreBand,
    similarityGroup: value.similarityGroup,
    sceneLabels: value.sceneLabels as string[],
    mediaKind: mediaKind as PhotoEditorialContext["mediaKind"],
    clipDurationSeconds: Number(clipDurationSeconds),
    hasOriginalAudio: hasOriginalAudio as boolean,
    videoMotion: videoMotion as PhotoEditorialContext["videoMotion"],
  };
}

function validateBaseline(value: unknown, requestedIds: ReadonlySet<string>): FirstCutInput {
  if (
    !isRecord(value) ||
    !hasExactKeys(value, [
      "photoCount", "durationSeconds", "omittedPhotoCount", "sequence", "titles",
      "soundtrackId", "look", "motionIntensity",
    ]) ||
    !Number.isInteger(value.photoCount) || Number(value.photoCount) < 1 || Number(value.photoCount) > 10_000 ||
    typeof value.durationSeconds !== "number" || !Number.isFinite(value.durationSeconds) || value.durationSeconds < 0 || value.durationSeconds > 40_000 ||
    !Number.isInteger(value.omittedPhotoCount) || Number(value.omittedPhotoCount) < 0 ||
    !Array.isArray(value.sequence) || value.sequence.length < 1 || value.sequence.length > LIMITS.maxPhotos ||
    Number(value.omittedPhotoCount) !== Number(value.photoCount) - value.sequence.length ||
    !Array.isArray(value.titles) || value.titles.length > 3 ||
    typeof value.soundtrackId !== "string" || ![...SOUNDTRACK_IDS, "none"].includes(value.soundtrackId) ||
    !MONTAGE_LOOKS.includes(value.look as never) ||
    !MOTION_INTENSITIES.includes(value.motionIntensity as never)
  ) {
    throw new RequestProblem(400, "invalid_baseline", "baseline is invalid.");
  }

  const sequence = value.sequence.map((item, index) => {
    if (
      !isRecord(item) ||
      !hasExactKeys(item, ["photoId", "order", "durationSeconds", "motion", "frameStyle"]) ||
      typeof item.photoId !== "string" || !requestedIds.has(item.photoId) ||
      item.order !== index ||
      typeof item.durationSeconds !== "number" || !Number.isFinite(item.durationSeconds) ||
      item.durationSeconds < 0.6 || item.durationSeconds > 4 ||
      !MOTIONS.includes(item.motion as never) ||
      !FIRST_CUT_FRAME_STYLES.includes(item.frameStyle as never)
    ) {
      throw new RequestProblem(400, "invalid_baseline", "baseline.sequence is invalid.");
    }
    return {
      photoId: item.photoId,
      order: index,
      durationSeconds: item.durationSeconds,
      motion: item.motion as FirstCutInput["sequence"][number]["motion"],
      frameStyle: item.frameStyle as FirstCutInput["sequence"][number]["frameStyle"],
    };
  });
  if (new Set(sequence.map((item) => item.photoId)).size !== sequence.length) {
    throw new RequestProblem(400, "invalid_baseline", "baseline.sequence IDs must be unique.");
  }

  const titleKinds = new Set<FirstCutTitleKind>();
  const titles = value.titles.map((item) => {
    if (!isRecord(item) || !hasExactKeys(item, ["kind", "title", "subtitle", "style", "durationSeconds"])) {
      throw new RequestProblem(400, "invalid_baseline", "baseline.titles is invalid.");
    }
    const title = cleanPlainText(item.title, LIMITS.maxShortTitleCharacters);
    const subtitle = cleanPlainText(item.subtitle, LIMITS.maxSubtitleCharacters, true);
    if (
      !FIRST_CUT_TITLE_KINDS.includes(item.kind as FirstCutTitleKind) ||
      titleKinds.has(item.kind as FirstCutTitleKind) || title === null || subtitle === null ||
      !TITLE_STYLES.includes(item.style as never) ||
      typeof item.durationSeconds !== "number" || !Number.isFinite(item.durationSeconds) ||
      item.durationSeconds < 1 || item.durationSeconds > 4
    ) {
      throw new RequestProblem(400, "invalid_baseline", "baseline.titles is invalid.");
    }
    titleKinds.add(item.kind as FirstCutTitleKind);
    return {
      kind: item.kind as FirstCutTitleKind,
      title,
      subtitle,
      style: item.style as FirstCutInput["titles"][number]["style"],
      durationSeconds: item.durationSeconds,
    };
  });

  return {
    photoCount: Number(value.photoCount),
    durationSeconds: value.durationSeconds,
    omittedPhotoCount: Number(value.omittedPhotoCount),
    sequence,
    titles,
    soundtrackId: value.soundtrackId,
    look: value.look as FirstCutInput["look"],
    motionIntensity: value.motionIntensity as FirstCutInput["motionIntensity"],
  };
}

function decodedBase64Length(value: string): number {
  const padding = value.endsWith("==") ? 2 : value.endsWith("=") ? 1 : 0;
  return (value.length / 4) * 3 - padding;
}

function jpegDimensions(bytes: Uint8Array): { width: number; height: number } | null {
  if (bytes.length < 11 || bytes[0] !== 0xff || bytes[1] !== 0xd8) {
    return null;
  }

  let offset = 2;
  let dimensions: { width: number; height: number } | null = null;
  let frameComponents = new Set<number>();
  let sawScan = false;
  while (offset < bytes.length) {
    const markerStart = offset;
    if (bytes[offset] !== 0xff) {
      return null;
    }
    while (offset < bytes.length && bytes[offset] === 0xff) {
      offset += 1;
    }
    if (offset >= bytes.length) {
      return null;
    }

    const marker = bytes[offset];
    offset += 1;

    if (marker === 0xd9) {
      return markerStart === bytes.length - 2 && dimensions !== null && sawScan ? dimensions : null;
    }
    if (marker === 0x00 || marker === 0xd8) {
      return null;
    }

    // TEM carries no segment length. Restart markers are valid only inside scan data.
    if (marker === 0x01) {
      continue;
    }
    if (marker >= 0xd0 && marker <= 0xd7) {
      return null;
    }

    if (offset + 1 >= bytes.length) {
      return null;
    }
    const segmentLength = (bytes[offset] << 8) | bytes[offset + 1];
    if (segmentLength < 2 || offset + segmentLength > bytes.length) {
      return null;
    }

    // Reject EXIF/XMP, IPTC/Photoshop, and JPEG comment segments. A thumbnail
    // with metadata must be re-encoded by the client before it can leave device.
    if (marker === 0xe1 || marker === 0xed || marker === 0xfe) {
      return null;
    }

    if (marker === 0xda) {
      if (dimensions === null || segmentLength < 8) {
        return null;
      }
      const scanComponentCount = bytes[offset + 2];
      if (
        scanComponentCount < 1 ||
        scanComponentCount > frameComponents.size ||
        segmentLength !== 6 + 2 * scanComponentCount
      ) {
        return null;
      }
      const scanComponents = new Set<number>();
      for (let index = 0; index < scanComponentCount; index += 1) {
        const componentId = bytes[offset + 3 + 2 * index];
        if (!frameComponents.has(componentId) || scanComponents.has(componentId)) {
          return null;
        }
        scanComponents.add(componentId);
      }

      let scanOffset = offset + segmentLength;
      let hasEntropyData = false;
      while (scanOffset < bytes.length) {
        if (bytes[scanOffset] !== 0xff) {
          hasEntropyData = true;
          scanOffset += 1;
          continue;
        }
        if (scanOffset + 1 >= bytes.length) {
          return null;
        }
        const next = bytes[scanOffset + 1];
        if (next === 0x00) {
          hasEntropyData = true;
          scanOffset += 2;
          continue;
        }
        if (next >= 0xd0 && next <= 0xd7) {
          scanOffset += 2;
          continue;
        }
        if (next === 0xff) {
          scanOffset += 1;
          continue;
        }
        if (!hasEntropyData) {
          return null;
        }
        sawScan = true;
        offset = scanOffset;
        break;
      }
      if (scanOffset >= bytes.length) {
        return null;
      }
      continue;
    }

    if (SOF_MARKERS.has(marker)) {
      if (segmentLength < 11 || dimensions !== null || bytes[offset + 2] !== 8) {
        return null;
      }
      const height = (bytes[offset + 3] << 8) | bytes[offset + 4];
      const width = (bytes[offset + 5] << 8) | bytes[offset + 6];
      const componentCount = bytes[offset + 7];
      if (
        width === 0 ||
        height === 0 ||
        componentCount < 1 ||
        componentCount > 4 ||
        segmentLength !== 8 + 3 * componentCount
      ) {
        return null;
      }
      frameComponents = new Set<number>();
      for (let index = 0; index < componentCount; index += 1) {
        const componentId = bytes[offset + 8 + 3 * index];
        const sampling = bytes[offset + 9 + 3 * index];
        if (
          frameComponents.has(componentId) ||
          (sampling >> 4) < 1 ||
          (sampling >> 4) > 4 ||
          (sampling & 0x0f) < 1 ||
          (sampling & 0x0f) > 4
        ) {
          return null;
        }
        frameComponents.add(componentId);
      }
      dimensions = { width, height };
    }

    offset += segmentLength;
  }

  return null;
}

export function validateJpegBase64(
  value: unknown,
  photoIndex: number,
  maximumBytes: number = LIMITS.maxImageBytes,
): number {
  const field = `photos[${photoIndex}].imageBase64`;
  if (typeof value !== "string" || value.length === 0) {
    throw new RequestProblem(400, "invalid_image", `${field} must be a base64 string.`);
  }
  if (value.startsWith("data:")) {
    throw new RequestProblem(400, "invalid_image", `${field} must not include a data URL prefix.`);
  }
  if (value.length % 4 !== 0 || !BASE64_PATTERN.test(value)) {
    throw new RequestProblem(400, "invalid_image", `${field} is not canonical base64.`);
  }

  const byteLength = decodedBase64Length(value);
  if (byteLength < 32) {
    throw new RequestProblem(400, "invalid_image", `${field} is too short to be a JPEG image.`);
  }
  if (byteLength > maximumBytes) {
    throw new RequestProblem(
      413,
      "image_too_large",
      `${field} must decode to no more than ${maximumBytes} bytes.`,
    );
  }

  let bytes: Uint8Array;
  try {
    const binary = atob(value);
    if (binary.length !== byteLength) {
      throw new Error("length mismatch");
    }
    bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
  } catch {
    throw new RequestProblem(400, "invalid_image", `${field} is not valid base64.`);
  }

  if (
    bytes[0] !== 0xff ||
    bytes[1] !== 0xd8 ||
    bytes[bytes.length - 2] !== 0xff ||
    bytes[bytes.length - 1] !== 0xd9
  ) {
    throw new RequestProblem(400, "invalid_image", `${field} must contain a complete JPEG image.`);
  }

  const dimensions = jpegDimensions(bytes);
  if (dimensions === null) {
    throw new RequestProblem(400, "invalid_image", `${field} has an invalid JPEG structure.`);
  }
  if (
    dimensions.width > LIMITS.maxImageDimension ||
    dimensions.height > LIMITS.maxImageDimension ||
    dimensions.width * dimensions.height > LIMITS.maxImagePixels
  ) {
    throw new RequestProblem(
      413,
      "image_dimensions_too_large",
      `${field} must be at most ${LIMITS.maxImageDimension}x${LIMITS.maxImageDimension} pixels.`,
    );
  }

  return byteLength;
}

export function validatePayload(value: unknown): ValidatedPayload {
  const hasLegacyRequestShape = isRecord(value) && hasExactKeys(value, ["version", "direction", "photos"]);
  const hasContextRequestShape = isRecord(value) && hasExactKeys(
    value,
    ["version", "direction", "storyContext", "photos"],
  );
  const hasDirectorRequestShape = isRecord(value) && hasExactKeys(
    value,
    ["version", "direction", "baseline", "photos"],
  );
  const hasDirectorContextRequestShape = isRecord(value) && hasExactKeys(
    value,
    ["version", "direction", "storyContext", "baseline", "photos"],
  );
  if (
    !isRecord(value) ||
    (!hasLegacyRequestShape && !hasContextRequestShape && !hasDirectorRequestShape && !hasDirectorContextRequestShape) ||
    typeof value.version !== "number" ||
    !REQUEST_VERSIONS.includes(value.version as RequestVersion) ||
    typeof value.direction !== "string" ||
    !AI_DIRECTIONS.includes(value.direction as AICutDirection) ||
    !Array.isArray(value.photos)
  ) {
    throw new RequestProblem(
      400,
      "invalid_request",
      "Body must contain only the supported version, direction, optional storyContext, baseline, and photos fields.",
    );
  }

  if (
    (value.version === 3 && !hasDirectorRequestShape && !hasDirectorContextRequestShape) ||
    (value.version !== 3 && (hasDirectorRequestShape || hasDirectorContextRequestShape))
  ) {
    throw new RequestProblem(400, "invalid_request", "Version 3 requires a First Cut baseline.");
  }

  let storyContext: string | undefined;
  if (hasContextRequestShape || hasDirectorContextRequestShape) {
    if (
      typeof value.storyContext !== "string" ||
      /[\u0000-\u001f\u007f]/u.test(value.storyContext)
    ) {
      throw new RequestProblem(400, "invalid_story_context", "storyContext must be plain text.");
    }
    const normalized = value.storyContext.replace(/\s+/gu, " ").trim();
    if (normalized.length < 1 || normalized.length > LIMITS.maxStoryContextCharacters) {
      throw new RequestProblem(
        400,
        "invalid_story_context",
        `storyContext must contain between 1 and ${LIMITS.maxStoryContextCharacters} characters.`,
      );
    }
    storyContext = normalized;
  }
  if (value.photos.length < 1 || value.photos.length > LIMITS.maxPhotos) {
    throw new RequestProblem(
      400,
      "invalid_photo_count",
      `photos must contain between 1 and ${LIMITS.maxPhotos} items.`,
    );
  }

  const ids = new Set<string>();
  const photos: PhotoInput[] = [];
  let totalImageBytes = 0;

  for (let index = 0; index < value.photos.length; index += 1) {
    const photo = value.photos[index];
    if (!isRecord(photo)) {
      throw new RequestProblem(
        400,
        "invalid_photo",
        `photos[${index}] must be an object.`,
      );
    }
    // Keep the deployed endpoint compatible with the previous TestFlight
    // request while new clients add the local editorial hint.
    const hasLegacyShape = hasExactKeys(photo, ["id", "imageBase64"]);
    const hasCurrentShape = hasExactKeys(photo, ["id", "imageBase64", "localSelection"]);
    const hasDirectorShape = hasExactKeys(photo, ["id", "imageBase64", "localSelection", "context"]);
    if (!hasLegacyShape && !hasCurrentShape && !hasDirectorShape) {
      throw new RequestProblem(
        400,
        "invalid_photo",
        `photos[${index}] contains unsupported fields.`,
      );
    }
    if (value.version === 3 && !hasDirectorShape) {
      throw new RequestProblem(400, "invalid_photo_context", `photos[${index}].context is required.`);
    }
    if (value.version !== 3 && hasDirectorShape) {
      throw new RequestProblem(400, "invalid_photo_context", "Photo context requires request version 3.");
    }
    const localSelection: LocalSelection = (hasCurrentShape || hasDirectorShape) &&
      typeof photo.localSelection === "string" &&
      LOCAL_SELECTIONS.includes(photo.localSelection as LocalSelection)
      ? photo.localSelection as LocalSelection
      : "first_cut";
    if ((hasCurrentShape || hasDirectorShape) && localSelection !== photo.localSelection) {
      throw new RequestProblem(
        400,
        "invalid_local_selection",
        `photos[${index}].localSelection is not supported.`,
      );
    }
    if (
      typeof photo.id !== "string" ||
      photo.id.length > LIMITS.maxIdCharacters ||
      !ID_PATTERN.test(photo.id)
    ) {
      throw new RequestProblem(
        400,
        "invalid_photo_id",
        `photos[${index}].id must match ${ID_PATTERN.source}.`,
      );
    }
    if (ids.has(photo.id)) {
      throw new RequestProblem(400, "duplicate_photo_id", "Photo IDs must be unique within a request.");
    }
    if (photo.id !== `p${index}`) {
      throw new RequestProblem(
        400,
        "invalid_photo_id",
        "Photo IDs must be contiguous temporary values starting at p0.",
      );
    }

    totalImageBytes += validateJpegBase64(photo.imageBase64, index);
    if (totalImageBytes > LIMITS.maxBatchImageBytes) {
      throw new RequestProblem(
        413,
        "batch_too_large",
        `Decoded images must total no more than ${LIMITS.maxBatchImageBytes} bytes.`,
      );
    }

    ids.add(photo.id);
    photos.push({
      id: photo.id,
      imageBase64: photo.imageBase64 as string,
      localSelection,
      ...(hasDirectorShape ? { context: validatePhotoContext(photo.context, index) } : {}),
    });
  }

  const baseline = value.version === 3
    ? validateBaseline(value.baseline, ids)
    : undefined;
  if (baseline !== undefined) {
    const selectionByID = new Map(photos.map((photo) => [photo.id, photo.localSelection]));
    if (baseline.sequence.some((item) => selectionByID.get(item.photoId) !== "first_cut")) {
      throw new RequestProblem(
        400,
        "invalid_baseline",
        "baseline.sequence may reference only submitted First Cut previews.",
      );
    }
  }

  return {
    version: value.version as RequestVersion,
    direction: value.direction as AICutDirection,
    ...(storyContext === undefined ? {} : { storyContext }),
    ...(baseline === undefined ? {} : { baseline }),
    photos,
  };
}

async function readStreamBounded(
  stream: ReadableStream<Uint8Array>,
  maxBytes: number,
  timeoutMs: number,
): Promise<Uint8Array> {
  const reader = stream.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  let timedOut = false;
  let timeoutHandle: ReturnType<typeof setTimeout> | undefined;

  const timeout = new Promise<never>((_resolve, reject) => {
    timeoutHandle = setTimeout(() => {
      timedOut = true;
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
      // Cancellation is best effort and its error must not replace the original problem.
    }
    throw error;
  } finally {
    if (timeoutHandle !== undefined) {
      clearTimeout(timeoutHandle);
    }
    if (timedOut) {
      try {
        await reader.cancel();
      } catch {
        // Best effort.
      }
    }
  }
}

export async function readJsonRequest(request: Request): Promise<unknown> {
  const contentEncoding = request.headers.get("content-encoding")?.trim().toLowerCase();
  if (contentEncoding !== undefined && contentEncoding !== "identity") {
    throw new RequestProblem(415, "unsupported_content_encoding", "Compressed request bodies are not accepted.");
  }

  const contentType = request.headers.get("content-type")?.split(";", 1)[0]?.trim().toLowerCase();
  if (contentType !== "application/json") {
    throw new RequestProblem(415, "unsupported_media_type", "Content-Type must be application/json.");
  }

  const contentLength = request.headers.get("content-length");
  if (contentLength !== null) {
    if (!/^\d+$/.test(contentLength)) {
      throw new RequestProblem(400, "invalid_content_length", "Content-Length is invalid.");
    }
    if (Number(contentLength) > LIMITS.maxBodyBytes) {
      throw new RequestProblem(413, "body_too_large", `Request body exceeds ${LIMITS.maxBodyBytes} bytes.`);
    }
  }

  if (request.body === null) {
    throw new RequestProblem(400, "missing_body", "A JSON request body is required.");
  }

  const bytes = await readStreamBounded(request.body, LIMITS.maxBodyBytes, LIMITS.bodyReadTimeoutMs);
  let text: string;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    throw new RequestProblem(400, "invalid_json", "Request body must be valid UTF-8 JSON.");
  }

  try {
    return JSON.parse(text) as unknown;
  } catch {
    throw new RequestProblem(400, "invalid_json", "Request body must be valid JSON.");
  }
}
