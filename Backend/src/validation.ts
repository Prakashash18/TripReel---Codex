import {
  AI_DIRECTIONS,
  LIMITS,
  LOCAL_SELECTIONS,
  REQUEST_VERSIONS,
  type AICutDirection,
  type LocalSelection,
  type PhotoInput,
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

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasExactKeys(value: Record<string, unknown>, keys: readonly string[]): boolean {
  const actual = Object.keys(value);
  return actual.length === keys.length && keys.every((key) => Object.hasOwn(value, key));
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

export function validateJpegBase64(value: unknown, photoIndex: number): number {
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
  if (byteLength > LIMITS.maxImageBytes) {
    throw new RequestProblem(
      413,
      "image_too_large",
      `${field} must decode to no more than ${LIMITS.maxImageBytes} bytes.`,
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
  if (
    !isRecord(value) ||
    !hasExactKeys(value, ["version", "direction", "photos"]) ||
    typeof value.version !== "number" ||
    !REQUEST_VERSIONS.includes(value.version as RequestVersion) ||
    typeof value.direction !== "string" ||
    !AI_DIRECTIONS.includes(value.direction as AICutDirection) ||
    !Array.isArray(value.photos)
  ) {
    throw new RequestProblem(
      400,
      "invalid_request",
      "Body must contain only version, direction, and photos using supported values.",
    );
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
    if (!hasLegacyShape && !hasCurrentShape) {
      throw new RequestProblem(
        400,
        "invalid_photo",
        `photos[${index}] contains unsupported fields.`,
      );
    }
    const localSelection: LocalSelection = hasCurrentShape &&
      typeof photo.localSelection === "string" &&
      LOCAL_SELECTIONS.includes(photo.localSelection as LocalSelection)
      ? photo.localSelection as LocalSelection
      : "first_cut";
    if (hasCurrentShape && localSelection !== photo.localSelection) {
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
    });
  }

  return {
    version: value.version as RequestVersion,
    direction: value.direction as AICutDirection,
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
