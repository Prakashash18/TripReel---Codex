import "@abraham/reflection";

import { decode, decodeFirst } from "cborg";
import {
  BasicConstraintsExtension,
  KeyUsageFlags,
  KeyUsagesExtension,
  X509Certificate,
  X509ChainBuilder,
} from "@peculiar/x509";

import { decodeKeyID, sha256 } from "./app-attest-encoding.ts";

const APPLE_NONCE_EXTENSION_OID = "1.2.840.113635.100.8.2";
const BASIC_CONSTRAINTS_OID = "2.5.29.19";
const KEY_USAGE_OID = "2.5.29.15";

const APPLE_APP_ATTESTATION_ROOT_BASE64 =
  "MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYwJAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwKQXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNaFw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlvbiBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9ybmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdhNbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9auYen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYwCgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn53O5+FRXgeLhpJ06ysC5PrOyAjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijVoyFraWVIyd/dganmrduC1bmTBGwD";

const CBOR_OPTIONS = {
  allowIndefinite: false,
  allowUndefined: false,
  allowInfinity: false,
  allowNaN: false,
  allowBigInt: false,
  strict: true,
  useMaps: true,
  rejectDuplicateMapKeys: true,
} as const;

const ASN1_PARSE_OPTIONS = {
  berOptions: {
    maxDepth: 32,
    maxNodes: 4_096,
    maxContentLength: 16_384,
  },
} as const;

const MAX_ATTESTATION_BYTES = 128 * 1_024;
const MAX_ASSERTION_BYTES = 16 * 1_024;
const MAX_AUTH_DATA_BYTES = 16 * 1_024;
const MAX_CERTIFICATE_BYTES = 16 * 1_024;
const MAX_RECEIPT_BYTES = 96 * 1_024;
const MIN_CLIENT_DATA_HASH_BYTES = 16;
const MAX_CLIENT_DATA_HASH_BYTES = 64;
const ATTESTED_CREDENTIAL_FLAG = 0x40;
const APP_ATTEST_KEY_LENGTH = 32;

const PRODUCTION_AAGUID = new Uint8Array([
  0x61, 0x70, 0x70, 0x61, 0x74, 0x74, 0x65, 0x73,
  0x74, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
]);
const DEVELOPMENT_AAGUID = new TextEncoder().encode("appattestdevelop");

export type AppAttestEnvironment = "production" | "development";

export type AppAttestVerificationErrorCode =
  | "malformed_attestation"
  | "malformed_assertion"
  | "invalid_certificate"
  | "invalid_certificate_chain"
  | "invalid_nonce"
  | "invalid_key_id"
  | "invalid_app_id"
  | "invalid_counter"
  | "invalid_environment"
  | "invalid_signature"
  | "invalid_extensions";

export class AppAttestVerificationError extends Error {
  readonly code: AppAttestVerificationErrorCode;

  constructor(code: AppAttestVerificationErrorCode, message: string) {
    super(message);
    this.name = "AppAttestVerificationError";
    this.code = code;
  }
}

export interface VerifyAttestationInput {
  keyId: string;
  attestationObject: Uint8Array;
  clientDataHash: Uint8Array;
  appID: string;
  environment: AppAttestEnvironment;
  now: Date;
}

export interface VerifiedAttestation {
  /** The decoded keyId, which is itself SHA-256 of the uncompressed public point. */
  keyHash: Uint8Array;
  publicKeySpki: Uint8Array;
  receipt: Uint8Array;
  aaguid: Uint8Array;
  validationCategory?: number;
  bundleVersion?: string;
}

export interface VerifyAssertionInput {
  assertionObject: Uint8Array;
  clientDataHash: Uint8Array;
  appID: string;
  publicKeySpki: Uint8Array;
}

export interface VerifiedAssertion {
  signCount: number;
  validationCategory?: number;
  bundleVersion?: string;
}

interface ParsedDerElement {
  tag: number;
  contentStart: number;
  contentEnd: number;
  end: number;
}

interface ParsedExtensions {
  validationCategory?: number;
  bundleVersion?: string;
}

interface ParsedBaseAuthenticatorData extends ParsedExtensions {
  rpIdHash: Uint8Array;
  flags: number;
  signCount: number;
}

interface ParsedAttestationAuthenticatorData extends ParsedBaseAuthenticatorData {
  aaguid: Uint8Array;
  credentialId: Uint8Array;
  cosePublicPoint: Uint8Array;
}

type OwnedBytes = Uint8Array<ArrayBuffer>;

function fail(code: AppAttestVerificationErrorCode, message: string): never {
  throw new AppAttestVerificationError(code, message);
}

function copyBytes(value: Uint8Array): OwnedBytes {
  const result = new Uint8Array(value.byteLength);
  result.set(value);
  return result;
}

function requireBytes(
  value: unknown,
  code: AppAttestVerificationErrorCode,
  label: string,
  minimum: number,
  maximum: number,
): Uint8Array {
  if (!(value instanceof Uint8Array) || value.byteLength < minimum || value.byteLength > maximum) {
    fail(code, `${label} has an invalid size`);
  }
  return value;
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

function bytesEqual(left: Uint8Array, right: Uint8Array): boolean {
  if (left.byteLength !== right.byteLength) {
    return false;
  }
  let difference = 0;
  for (let index = 0; index < left.byteLength; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference === 0;
}

function expectMap(
  value: unknown,
  code: AppAttestVerificationErrorCode,
  label: string,
): Map<unknown, unknown> {
  if (!(value instanceof Map)) {
    fail(code, `${label} must be a CBOR map`);
  }
  return value;
}

function requireExactKeys(
  map: Map<unknown, unknown>,
  allowed: readonly (string | number)[],
  code: AppAttestVerificationErrorCode,
  label: string,
): void {
  if (map.size !== allowed.length || allowed.some((key) => !map.has(key))) {
    fail(code, `${label} has unexpected fields`);
  }
}

function decodeCbor(
  bytes: Uint8Array,
  code: AppAttestVerificationErrorCode,
  label: string,
): unknown {
  try {
    return decode(bytes, CBOR_OPTIONS) as unknown;
  } catch {
    fail(code, `${label} is not strict CBOR`);
  }
}

function decodeFirstCbor(
  bytes: Uint8Array,
  code: AppAttestVerificationErrorCode,
  label: string,
): [unknown, Uint8Array] {
  try {
    const [value, remainder] = decodeFirst(bytes, CBOR_OPTIONS);
    return [value as unknown, remainder];
  } catch {
    fail(code, `${label} is not strict CBOR`);
  }
}

function validateAppID(appID: string): Uint8Array {
  if (
    typeof appID !== "string" ||
    appID.length === 0 ||
    appID.length > 512 ||
    !/^[A-Za-z0-9.-]+$/u.test(appID) ||
    !appID.includes(".")
  ) {
    fail("invalid_app_id", "App ID is invalid");
  }
  return new TextEncoder().encode(appID);
}

function validateClientDataHash(value: unknown, code: AppAttestVerificationErrorCode): Uint8Array {
  return requireBytes(
    value,
    code,
    "clientDataHash",
    MIN_CLIENT_DATA_HASH_BYTES,
    MAX_CLIENT_DATA_HASH_BYTES,
  );
}

function readUint32BigEndian(bytes: Uint8Array, offset: number): number {
  return new DataView(bytes.buffer, bytes.byteOffset + offset, 4).getUint32(0, false);
}

function parseExtensions(bytes: Uint8Array): ParsedExtensions {
  if (bytes.byteLength === 0) {
    return {};
  }

  const map = expectMap(decodeCbor(bytes, "invalid_extensions", "authenticator extensions"), "invalid_extensions", "authenticator extensions");
  for (const key of map.keys()) {
    if (typeof key !== "string") {
      fail("invalid_extensions", "Authenticator extension keys must be strings");
    }
  }

  const result: ParsedExtensions = {};
  if (map.has("apple_validation_category_01")) {
    const category = map.get("apple_validation_category_01");
    if (typeof category === "number") {
      if (!Number.isInteger(category) || category < 0 || category > 0xffff_ffff) {
        fail("invalid_extensions", "Validation category is invalid");
      }
      result.validationCategory = category;
    } else if (category instanceof Uint8Array && category.byteLength === 4) {
      result.validationCategory = new DataView(
        category.buffer,
        category.byteOffset,
        category.byteLength,
      ).getUint32(0, true);
    } else {
      fail("invalid_extensions", "Validation category is invalid");
    }
  }

  if (map.has("apple_bundle_version_01")) {
    const version = map.get("apple_bundle_version_01");
    if (
      typeof version !== "string" ||
      version.length === 0 ||
      version.length > 128 ||
      version.includes("\0") ||
      version.includes("\n") ||
      version.includes("\r")
    ) {
      fail("invalid_extensions", "Bundle version is invalid");
    }
    result.bundleVersion = version;
  }
  return result;
}

function parseBaseAuthenticatorData(
  authData: Uint8Array,
  code: AppAttestVerificationErrorCode,
): ParsedBaseAuthenticatorData {
  requireBytes(authData, code, "authenticatorData", 37, MAX_AUTH_DATA_BYTES);
  const extensions = parseExtensions(authData.subarray(37));
  return {
    rpIdHash: copyBytes(authData.subarray(0, 32)),
    flags: authData[32],
    signCount: readUint32BigEndian(authData, 33),
    ...extensions,
  };
}

function parseCosePublicPoint(coseValue: unknown): Uint8Array {
  const cose = expectMap(coseValue, "malformed_attestation", "COSE key");
  requireExactKeys(cose, [1, 3, -1, -2, -3], "malformed_attestation", "COSE key");
  if (cose.get(1) !== 2 || cose.get(3) !== -7 || cose.get(-1) !== 1) {
    fail("malformed_attestation", "COSE key is not an ES256 P-256 key");
  }
  const x = requireBytes(cose.get(-2), "malformed_attestation", "COSE x coordinate", 32, 32);
  const y = requireBytes(cose.get(-3), "malformed_attestation", "COSE y coordinate", 32, 32);
  const point = new Uint8Array(65);
  point[0] = 0x04;
  point.set(x, 1);
  point.set(y, 33);
  return point;
}

function parseAttestationAuthenticatorData(authData: Uint8Array): ParsedAttestationAuthenticatorData {
  requireBytes(authData, "malformed_attestation", "authData", 55 + APP_ATTEST_KEY_LENGTH + 1, MAX_AUTH_DATA_BYTES);
  const flags = authData[32];
  if ((flags & ATTESTED_CREDENTIAL_FLAG) === 0) {
    fail("malformed_attestation", "Attested credential data is missing");
  }

  const credentialLength = (authData[53] << 8) | authData[54];
  if (credentialLength !== APP_ATTEST_KEY_LENGTH) {
    fail("invalid_key_id", "Credential ID must contain 32 bytes");
  }
  const credentialStart = 55;
  const credentialEnd = credentialStart + credentialLength;
  if (credentialEnd >= authData.byteLength) {
    fail("malformed_attestation", "Authenticator data is truncated");
  }

  const [coseValue, extensionBytes] = decodeFirstCbor(
    authData.subarray(credentialEnd),
    "malformed_attestation",
    "COSE key",
  );
  const extensions = parseExtensions(extensionBytes);
  return {
    rpIdHash: copyBytes(authData.subarray(0, 32)),
    flags,
    signCount: readUint32BigEndian(authData, 33),
    aaguid: copyBytes(authData.subarray(37, 53)),
    credentialId: copyBytes(authData.subarray(credentialStart, credentialEnd)),
    cosePublicPoint: parseCosePublicPoint(coseValue),
    ...extensions,
  };
}

function decodePinnedRoot(): Uint8Array {
  const binary = atob(APPLE_APP_ATTESTATION_ROOT_BASE64);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function readDerElement(
  bytes: Uint8Array,
  offset: number,
  code: AppAttestVerificationErrorCode,
): ParsedDerElement {
  const start = offset;
  if (offset >= bytes.byteLength) {
    fail(code, "DER value is truncated");
  }

  const firstTagByte = bytes[offset];
  offset += 1;
  if ((firstTagByte & 0x1f) === 0x1f) {
    if (offset >= bytes.byteLength || (bytes[offset] & 0x7f) === 0) {
      fail(code, "DER tag is not canonical");
    }
    do {
      if (offset >= bytes.byteLength) {
        fail(code, "DER tag is truncated");
      }
    } while ((bytes[offset++] & 0x80) !== 0);
  }

  if (offset >= bytes.byteLength) {
    fail(code, "DER length is truncated");
  }
  const firstLengthByte = bytes[offset];
  offset += 1;
  let contentLength: number;
  if (firstLengthByte < 0x80) {
    contentLength = firstLengthByte;
  } else {
    const count = firstLengthByte & 0x7f;
    if (count === 0 || count > 4 || offset + count > bytes.byteLength || bytes[offset] === 0) {
      fail(code, "DER length is invalid");
    }
    contentLength = 0;
    for (let index = 0; index < count; index += 1) {
      contentLength = contentLength * 256 + bytes[offset + index];
    }
    if (contentLength < 0x80 || !Number.isSafeInteger(contentLength)) {
      fail(code, "DER length is not canonical");
    }
    offset += count;
  }

  const contentStart = offset;
  const contentEnd = contentStart + contentLength;
  if (contentEnd > bytes.byteLength) {
    fail(code, "DER value is truncated");
  }
  return { tag: firstTagByte, contentStart, contentEnd, end: contentEnd };
}

function validateDerRegion(
  bytes: Uint8Array,
  start: number,
  end: number,
  depth: number,
  nodeBudget: { remaining: number },
  code: AppAttestVerificationErrorCode,
): void {
  if (depth > 32) {
    fail(code, "DER nesting is too deep");
  }
  let offset = start;
  while (offset < end) {
    nodeBudget.remaining -= 1;
    if (nodeBudget.remaining < 0) {
      fail(code, "DER value is too complex");
    }
    const element = readDerElement(bytes, offset, code);
    if (element.end > end) {
      fail(code, "DER child exceeds its parent");
    }
    if ((element.tag & 0x20) !== 0) {
      validateDerRegion(bytes, element.contentStart, element.contentEnd, depth + 1, nodeBudget, code);
    }
    offset = element.end;
  }
  if (offset !== end) {
    fail(code, "DER value has trailing data");
  }
}

function validateCompleteDer(bytes: Uint8Array, code: AppAttestVerificationErrorCode): void {
  const top = readDerElement(bytes, 0, code);
  if (top.tag !== 0x30 || top.end !== bytes.byteLength) {
    fail(code, "DER value must be one complete sequence");
  }
  validateDerRegion(bytes, top.contentStart, top.contentEnd, 1, { remaining: 4_096 }, code);
}

function parseCertificate(bytes: Uint8Array): X509Certificate {
  requireBytes(bytes, "invalid_certificate", "certificate", 1, MAX_CERTIFICATE_BYTES);
  validateCompleteDer(bytes, "invalid_certificate");
  try {
    return new X509Certificate(copyBytes(bytes), ASN1_PARSE_OPTIONS);
  } catch {
    fail("invalid_certificate", "Certificate is not valid DER X.509");
  }
}

function assertUniqueCertificateExtensions(certificate: X509Certificate): void {
  const seen = new Set<string>();
  for (const extension of certificate.extensions) {
    if (seen.has(extension.type)) {
      fail("invalid_certificate", "Certificate contains a duplicate extension");
    }
    seen.add(extension.type);
    if (extension.critical && extension.type !== BASIC_CONSTRAINTS_OID && extension.type !== KEY_USAGE_OID) {
      fail("invalid_certificate", "Certificate contains an unsupported critical extension");
    }
  }
}

function assertCertificateRole(certificate: X509Certificate, isLeaf: boolean, caCertificatesBelow: number): void {
  assertUniqueCertificateExtensions(certificate);
  const basicConstraints = certificate.getExtension(BasicConstraintsExtension);
  const keyUsage = certificate.getExtension(KeyUsagesExtension);
  if (!basicConstraints || !basicConstraints.critical || !keyUsage || !keyUsage.critical) {
    fail("invalid_certificate", "Certificate constraints and key usage must be critical");
  }

  if (isLeaf) {
    if (basicConstraints.ca || (keyUsage.usages & KeyUsageFlags.digitalSignature) === 0 || (keyUsage.usages & KeyUsageFlags.keyCertSign) !== 0) {
      fail("invalid_certificate", "Credential certificate has an invalid role");
    }
    return;
  }

  if (!basicConstraints.ca || (keyUsage.usages & KeyUsageFlags.keyCertSign) === 0) {
    fail("invalid_certificate", "Issuer certificate is not a certificate authority");
  }
  if (basicConstraints.pathLength !== undefined && caCertificatesBelow > basicConstraints.pathLength) {
    fail("invalid_certificate_chain", "Certificate path length constraint failed");
  }
}

async function verifyCertificateChain(x5c: Uint8Array[], now: Date): Promise<X509Certificate> {
  if (!(now instanceof Date) || !Number.isFinite(now.getTime())) {
    fail("invalid_certificate", "Certificate validation time is invalid");
  }
  if (x5c.length < 2 || x5c.length > 4) {
    fail("invalid_certificate_chain", "App Attest x5c must include a leaf and issuer certificate");
  }

  const supplied = x5c.map(parseCertificate);
  const pinnedRootBytes = decodePinnedRoot();
  const pinnedRoot = parseCertificate(pinnedRootBytes);
  const all = [...supplied, pinnedRoot];

  for (let index = 0; index < all.length; index += 1) {
    const certificate = all[index];
    if (now < certificate.notBefore || now > certificate.notAfter) {
      fail("invalid_certificate", "Certificate is outside its validity interval");
    }
    assertCertificateRole(certificate, index === 0, Math.max(0, index - 1));
  }

  let built: X509Certificate[];
  try {
    const builder = new X509ChainBuilder({ certificates: [...supplied.slice(1), pinnedRoot] });
    built = Array.from(await builder.build(supplied[0], crypto));
  } catch {
    fail("invalid_certificate_chain", "Certificate chain validation failed");
  }
  if (built.length !== all.length) {
    fail("invalid_certificate_chain", "Certificate chain does not terminate at the pinned Apple root");
  }
  for (let index = 0; index < all.length; index += 1) {
    if (!bytesEqual(new Uint8Array(built[index].rawData), new Uint8Array(all[index].rawData))) {
      fail("invalid_certificate_chain", "Certificate chain is not in the expected order");
    }
  }

  try {
    const rootIsValid = await pinnedRoot.verify({ publicKey: pinnedRoot, date: now }, crypto);
    if (!rootIsValid || !bytesEqual(new Uint8Array(built.at(-1)!.rawData), pinnedRootBytes)) {
      fail("invalid_certificate_chain", "Pinned Apple root validation failed");
    }
  } catch (error) {
    if (error instanceof AppAttestVerificationError) {
      throw error;
    }
    fail("invalid_certificate_chain", "Pinned Apple root validation failed");
  }
  return supplied[0];
}

function extractNonceExtension(certificate: X509Certificate): Uint8Array {
  const extension = certificate.getExtension(APPLE_NONCE_EXTENSION_OID);
  if (!extension) {
    fail("invalid_nonce", "Credential certificate nonce extension is missing");
  }
  const bytes = new Uint8Array(extension.value);
  const sequence = readDerElement(bytes, 0, "invalid_nonce");
  if (sequence.tag !== 0x30 || sequence.end !== bytes.byteLength) {
    fail("invalid_nonce", "Credential certificate nonce extension is malformed");
  }
  const context = readDerElement(bytes, sequence.contentStart, "invalid_nonce");
  if (context.tag !== 0xa1 || context.end !== sequence.contentEnd) {
    fail("invalid_nonce", "Credential certificate nonce extension is malformed");
  }
  const octetString = readDerElement(bytes, context.contentStart, "invalid_nonce");
  if (octetString.tag !== 0x04 || octetString.end !== context.contentEnd || octetString.contentEnd - octetString.contentStart !== 32) {
    fail("invalid_nonce", "Credential certificate nonce extension is malformed");
  }
  return copyBytes(bytes.subarray(octetString.contentStart, octetString.contentEnd));
}

async function exportCredentialPublicKey(certificate: X509Certificate): Promise<{
  spki: Uint8Array;
  point: Uint8Array;
}> {
  try {
    const key = await certificate.publicKey.export(
      { name: "ECDSA", namedCurve: "P-256" },
      ["verify"],
      crypto,
    );
    const point = new Uint8Array(await crypto.subtle.exportKey("raw", key));
    if (point.byteLength !== 65 || point[0] !== 0x04) {
      fail("invalid_certificate", "Credential certificate key is not uncompressed P-256");
    }
    return { spki: new Uint8Array(certificate.publicKey.rawData), point };
  } catch (error) {
    if (error instanceof AppAttestVerificationError) {
      throw error;
    }
    fail("invalid_certificate", "Credential certificate key is not P-256");
  }
}

function expectedAaguid(environment: AppAttestEnvironment): Uint8Array {
  if (environment === "production") {
    return PRODUCTION_AAGUID;
  }
  if (environment === "development") {
    return DEVELOPMENT_AAGUID;
  }
  fail("invalid_environment", "App Attest environment is invalid");
}

function parseEcdsaDerSignature(signature: Uint8Array): Uint8Array {
  requireBytes(signature, "invalid_signature", "assertion signature", 8, 80);
  const sequence = readDerElement(signature, 0, "invalid_signature");
  if (sequence.tag !== 0x30 || sequence.end !== signature.byteLength) {
    fail("invalid_signature", "Assertion signature is not canonical DER");
  }

  const r = readDerElement(signature, sequence.contentStart, "invalid_signature");
  const s = readDerElement(signature, r.end, "invalid_signature");
  if (r.tag !== 0x02 || s.tag !== 0x02 || s.end !== sequence.contentEnd) {
    fail("invalid_signature", "Assertion signature is not an ECDSA pair");
  }

  const normalizeInteger = (element: ParsedDerElement): Uint8Array => {
    let integer = signature.subarray(element.contentStart, element.contentEnd);
    if (
      integer.byteLength === 0 ||
      (integer[0] & 0x80) !== 0 ||
      (integer.byteLength > 1 && integer[0] === 0 && (integer[1] & 0x80) === 0)
    ) {
      fail("invalid_signature", "Assertion signature integer is not canonical and positive");
    }
    if (integer[0] === 0) {
      integer = integer.subarray(1);
    }
    if (integer.byteLength === 0 || integer.byteLength > 32 || integer.every((byte) => byte === 0)) {
      fail("invalid_signature", "Assertion signature integer is out of range");
    }
    const normalized = new Uint8Array(32);
    normalized.set(integer, 32 - integer.byteLength);
    return normalized;
  };

  return concatenate(normalizeInteger(r), normalizeInteger(s));
}

async function assertRpIdHash(actual: Uint8Array, appID: string): Promise<void> {
  const expected = await sha256(validateAppID(appID));
  if (!bytesEqual(actual, expected)) {
    fail("invalid_app_id", "Authenticator RP ID hash does not match the app");
  }
}

export async function verifyAttestation(input: VerifyAttestationInput): Promise<VerifiedAttestation> {
  const attestationBytes = requireBytes(
    input.attestationObject,
    "malformed_attestation",
    "attestationObject",
    1,
    MAX_ATTESTATION_BYTES,
  );
  const clientDataHash = validateClientDataHash(input.clientDataHash, "malformed_attestation");

  let keyHash: Uint8Array;
  try {
    keyHash = decodeKeyID(input.keyId);
  } catch {
    fail("invalid_key_id", "keyId is not Apple's canonical 32-byte Base64 identifier");
  }

  const object = expectMap(
    decodeCbor(attestationBytes, "malformed_attestation", "attestationObject"),
    "malformed_attestation",
    "attestationObject",
  );
  requireExactKeys(object, ["fmt", "attStmt", "authData"], "malformed_attestation", "attestationObject");
  if (object.get("fmt") !== "apple-appattest") {
    fail("malformed_attestation", "Attestation format is not apple-appattest");
  }

  const statement = expectMap(object.get("attStmt"), "malformed_attestation", "attStmt");
  requireExactKeys(statement, ["x5c", "receipt"], "malformed_attestation", "attStmt");
  const rawCertificates = statement.get("x5c");
  if (!Array.isArray(rawCertificates)) {
    fail("malformed_attestation", "attStmt.x5c must be an array");
  }
  const certificateBytes = rawCertificates.map((value) =>
    requireBytes(value, "invalid_certificate", "x5c certificate", 1, MAX_CERTIFICATE_BYTES),
  );
  const receipt = requireBytes(statement.get("receipt"), "malformed_attestation", "receipt", 1, MAX_RECEIPT_BYTES);
  const authData = requireBytes(object.get("authData"), "malformed_attestation", "authData", 1, MAX_AUTH_DATA_BYTES);

  const credentialCertificate = await verifyCertificateChain(certificateBytes, input.now);
  const parsed = parseAttestationAuthenticatorData(authData);
  if (parsed.signCount !== 0) {
    fail("invalid_counter", "Attestation signature counter must be zero");
  }
  if (!bytesEqual(parsed.aaguid, expectedAaguid(input.environment))) {
    fail("invalid_environment", "Authenticator AAGUID does not match the configured environment");
  }
  if (!bytesEqual(parsed.credentialId, keyHash)) {
    fail("invalid_key_id", "Credential ID does not match keyId");
  }
  await assertRpIdHash(parsed.rpIdHash, input.appID);

  const nonce = await sha256(concatenate(authData, clientDataHash));
  if (!bytesEqual(extractNonceExtension(credentialCertificate), nonce)) {
    fail("invalid_nonce", "Credential certificate nonce does not match the challenge");
  }

  const publicKey = await exportCredentialPublicKey(credentialCertificate);
  if (!bytesEqual(publicKey.point, parsed.cosePublicPoint)) {
    fail("invalid_key_id", "Authenticator COSE key does not match the credential certificate");
  }
  const publicKeyHash = await sha256(publicKey.point);
  if (!bytesEqual(publicKeyHash, keyHash)) {
    fail("invalid_key_id", "Credential certificate public key does not match keyId");
  }

  return {
    keyHash: copyBytes(keyHash),
    publicKeySpki: copyBytes(publicKey.spki),
    receipt: copyBytes(receipt),
    aaguid: copyBytes(parsed.aaguid),
    validationCategory: parsed.validationCategory,
    bundleVersion: parsed.bundleVersion,
  };
}

export async function verifyAssertion(input: VerifyAssertionInput): Promise<VerifiedAssertion> {
  const assertionBytes = requireBytes(
    input.assertionObject,
    "malformed_assertion",
    "assertionObject",
    1,
    MAX_ASSERTION_BYTES,
  );
  const clientDataHash = validateClientDataHash(input.clientDataHash, "malformed_assertion");
  const publicKeySpki = requireBytes(input.publicKeySpki, "invalid_certificate", "publicKeySpki", 1, 256);
  validateCompleteDer(publicKeySpki, "invalid_certificate");

  const object = expectMap(
    decodeCbor(assertionBytes, "malformed_assertion", "assertionObject"),
    "malformed_assertion",
    "assertionObject",
  );
  requireExactKeys(object, ["signature", "authenticatorData"], "malformed_assertion", "assertionObject");
  const signature = requireBytes(object.get("signature"), "invalid_signature", "assertion signature", 1, 80);
  const authData = requireBytes(
    object.get("authenticatorData"),
    "malformed_assertion",
    "authenticatorData",
    37,
    MAX_AUTH_DATA_BYTES,
  );
  const parsed = parseBaseAuthenticatorData(authData, "malformed_assertion");
  await assertRpIdHash(parsed.rpIdHash, input.appID);
  if (parsed.signCount === 0) {
    fail("invalid_counter", "Assertion signature counter must be greater than zero");
  }

  let publicKey: CryptoKey;
  try {
    publicKey = await crypto.subtle.importKey(
      "spki",
      copyBytes(publicKeySpki).buffer,
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["verify"],
    );
  } catch {
    fail("invalid_certificate", "Stored public key is not a P-256 SPKI key");
  }

  const nonce = await sha256(concatenate(authData, clientDataHash));
  const rawSignature = parseEcdsaDerSignature(signature);
  let valid = false;
  try {
    valid = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      publicKey,
      copyBytes(rawSignature).buffer,
      copyBytes(nonce).buffer,
    );
  } catch {
    valid = false;
  }
  if (!valid) {
    fail("invalid_signature", "Assertion signature validation failed");
  }

  return {
    signCount: parsed.signCount,
    validationCategory: parsed.validationCategory,
    bundleVersion: parsed.bundleVersion,
  };
}
