const encoder = new TextEncoder();

const ATTESTATION_PREFIX = encoder.encode("TripReel-App-Attest/v1\nattestation\n");
const ASSERTION_PREFIX = "TripReel-App-Attest/v1\nassertion\n";
const SHA256_LENGTH = 32;

type OwnedBytes = Uint8Array<ArrayBuffer>;

function decodeCanonicalBase64(value: string): OwnedBytes {
  if (
    value.length === 0 ||
    value.length % 4 !== 0 ||
    !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value)
  ) {
    throw new TypeError("Expected canonical padded Base64");
  }

  let binary: string;
  try {
    binary = atob(value);
  } catch {
    throw new TypeError("Expected canonical padded Base64");
  }

  if (btoa(binary) !== value) {
    throw new TypeError("Expected canonical padded Base64");
  }

  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function encodeBase64URL(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/u, "");
}

function concatenate(...parts: Uint8Array[]): OwnedBytes {
  const length = parts.reduce((total, part) => total + part.byteLength, 0);
  const result = new Uint8Array(length);
  let offset = 0;
  for (const part of parts) {
    result.set(part, offset);
    offset += part.byteLength;
  }
  return result;
}

function requireLength(bytes: Uint8Array, length: number, label: string): void {
  if (!(bytes instanceof Uint8Array) || bytes.byteLength !== length) {
    throw new TypeError(`${label} must contain exactly ${length} bytes`);
  }
}

/** Decodes the canonical, padded standard-Base64 identifier from generateKey(). */
export function decodeKeyID(value: string): OwnedBytes {
  if (typeof value !== "string") {
    throw new TypeError("keyId must be a string");
  }
  const bytes = decodeCanonicalBase64(value);
  requireLength(bytes, SHA256_LENGTH, "keyId");
  return bytes;
}

/** Decodes unpadded Base64URL and rejects noncanonical encodings. */
export function decodeBase64URL(value: string, expectedLength?: number): OwnedBytes {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.length % 4 === 1 ||
    !/^[A-Za-z0-9_-]+$/u.test(value)
  ) {
    throw new TypeError("Expected canonical unpadded Base64URL");
  }

  const padding = "=".repeat((4 - (value.length % 4)) % 4);
  let binary: string;
  try {
    binary = atob(value.replace(/-/g, "+").replace(/_/g, "/") + padding);
  } catch {
    throw new TypeError("Expected canonical unpadded Base64URL");
  }

  const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
  if (encodeBase64URL(bytes) !== value) {
    throw new TypeError("Expected canonical unpadded Base64URL");
  }
  if (expectedLength !== undefined) {
    if (!Number.isSafeInteger(expectedLength) || expectedLength < 0) {
      throw new TypeError("expectedLength must be a nonnegative safe integer");
    }
    requireLength(bytes, expectedLength, "Base64URL value");
  }
  return bytes;
}

export async function sha256(data: Uint8Array): Promise<OwnedBytes> {
  if (!(data instanceof Uint8Array)) {
    throw new TypeError("SHA-256 input must be bytes");
  }
  const digest = await crypto.subtle.digest("SHA-256", Uint8Array.from(data));
  return new Uint8Array(digest);
}

/** Bytes hashed by the client before calling attestKey(_:clientDataHash:). */
export function createAttestationClientData(challenge: Uint8Array): OwnedBytes {
  requireLength(challenge, SHA256_LENGTH, "challenge");
  return concatenate(ATTESTATION_PREFIX, challenge);
}

export interface AssertionClientDataInput {
  method: string;
  path: string;
  challenge: Uint8Array;
  bodyHash: Uint8Array;
}

/** Canonical request bytes hashed by the client before generateAssertion(). */
export function createAssertionClientData(input: AssertionClientDataInput): OwnedBytes {
  const { method, path, challenge, bodyHash } = input;
  if (typeof method !== "string" || !/^[A-Za-z]+$/u.test(method)) {
    throw new TypeError("method must contain only ASCII letters");
  }
  if (
    typeof path !== "string" ||
    !path.startsWith("/") ||
    path.length > 256 ||
    path.includes("\n") ||
    path.includes("\r")
  ) {
    throw new TypeError("path must be a bounded absolute path without line breaks");
  }
  requireLength(challenge, SHA256_LENGTH, "challenge");
  requireLength(bodyHash, SHA256_LENGTH, "bodyHash");

  const prefix = encoder.encode(`${ASSERTION_PREFIX}${method.toUpperCase()}\n${path}\n`);
  return concatenate(prefix, challenge, bodyHash);
}
