import { DurableObject } from "cloudflare:workers";

import {
  createAssertionClientData,
  createAttestationClientData,
  sha256,
} from "./app-attest-encoding.ts";
import {
  AppAttestVerificationError,
  verifyAssertion,
  verifyAttestation,
} from "./app-attest-verifier.ts";
import { LIMITS } from "./contract.ts";

export type AppAttestPurpose = "attestation" | "assertion";

export interface AppAttestStateEnv {
  APP_ATTEST_APP_ID?: string;
  APP_ATTEST_ENVIRONMENT?: string;
  APP_ATTEST_ALLOWED_VALIDATION_CATEGORIES?: string;
  APP_ATTEST_MINIMUM_BUNDLE_VERSION?: string;
}

export interface IssueChallengeInput {
  keyID: Uint8Array;
  purpose: AppAttestPurpose;
  nowMs: number;
}

export interface RegisterKeyInput {
  keyId: string;
  keyID: Uint8Array;
  challenge: Uint8Array;
  attestationObject: Uint8Array;
  nowMs: number;
}

export interface AuthorizeAnalysisInput {
  keyID: Uint8Array;
  challenge: Uint8Array;
  assertionObject: Uint8Array;
  method: "POST";
  path: "/v1/analyze";
  bodyHash: Uint8Array;
  photoCount: number;
  nowMs: number;
}

export type AppAttestStateFailureCode =
  | "key_not_registered"
  | "key_already_registered"
  | "challenge_used"
  | "challenge_expired"
  | "invalid_attestation"
  | "invalid_assertion"
  | "counter_replay"
  | "rate_limited"
  | "server_misconfigured";

export interface AppAttestStateFailure {
  ok: false;
  code: AppAttestStateFailureCode;
  retryAfter?: number;
}

export interface AppAttestChallengeSuccess {
  ok: true;
  challenge: string;
  expiresAt: string;
}

export interface AppAttestAuthorizationSuccess {
  ok: true;
}

export type AppAttestChallengeResult = AppAttestChallengeSuccess | AppAttestStateFailure;
export type AppAttestOperationResult = AppAttestAuthorizationSuccess | AppAttestStateFailure;

interface ChallengeRow {
  [column: string]: string | number | ArrayBuffer;
  expires_at_ms: number;
}

interface KeyRow {
  [column: string]: string | number | ArrayBuffer;
  public_key_spki: ArrayBuffer;
  sign_count: number;
  status: "active" | "revoked";
  minute_bucket: number;
  minute_requests: number;
  utc_day: number;
  day_photos: number;
}

const CHALLENGE_BYTES = 32;
const CHALLENGE_TTL_MS = 5 * 60 * 1_000;
const MAX_OUTSTANDING_CHALLENGES_PER_PURPOSE = 4;
const KEY_RETENTION_MS = 180 * 24 * 60 * 60 * 1_000;
const MAX_REQUESTS_PER_MINUTE = 30;
const MAX_PHOTOS_PER_UTC_DAY = 1_000;

function isValidNow(value: number): boolean {
  return Number.isSafeInteger(value) && value >= 1_577_836_800_000 && value <= 4_102_444_800_000;
}

function exactBuffer(bytes: Uint8Array): ArrayBuffer {
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
}

function bytesFromBlob(value: ArrayBuffer | ArrayBufferView): Uint8Array {
  if (value instanceof ArrayBuffer) {
    return new Uint8Array(value);
  }
  return new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
}

function equalBytes(left: Uint8Array, right: Uint8Array): boolean {
  if (left.byteLength !== right.byteLength) {
    return false;
  }
  let difference = 0;
  for (let index = 0; index < left.byteLength; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference === 0;
}

function encodeBase64URL(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/u, "");
}

function configuredSet(value: string | undefined): ReadonlySet<string> | null {
  if (value === undefined || value.length === 0 || value.length > 512) {
    return null;
  }
  const entries = value.split(",").map((entry) => entry.trim()).filter(Boolean);
  if (entries.length === 0 || entries.length > 32 || entries.some((entry) => entry.length > 64)) {
    return null;
  }
  return new Set(entries);
}

function verificationMetadataAllowed(
  env: AppAttestStateEnv,
  validationCategory: number | undefined,
  bundleVersion: string | undefined,
): boolean {
  if (validationCategory !== undefined) {
    const allowedCategories = configuredSet(env.APP_ATTEST_ALLOWED_VALIDATION_CATEGORIES);
    if (allowedCategories === null || !allowedCategories.has(String(validationCategory))) {
      return false;
    }
  }
  if (bundleVersion !== undefined) {
    const minimum = env.APP_ATTEST_MINIMUM_BUNDLE_VERSION;
    if (
      !/^[1-9][0-9]{0,8}$/u.test(bundleVersion) ||
      minimum === undefined ||
      !/^[1-9][0-9]{0,8}$/u.test(minimum) ||
      Number(bundleVersion) < Number(minimum)
    ) {
      return false;
    }
  }
  return true;
}

function stateFailure(code: AppAttestStateFailureCode, retryAfter?: number): AppAttestStateFailure {
  return retryAfter === undefined ? { ok: false, code } : { ok: false, code, retryAfter };
}

/**
 * Stores only App Attest authentication state. Photo bytes, request bodies,
 * body hashes, Photos identifiers, and model results must never enter this object.
 */
export class AppAttestShard extends DurableObject<AppAttestStateEnv> {
  constructor(ctx: DurableObjectState, env: AppAttestStateEnv) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      this.migrate();
    });
  }

  private migrate(): void {
    const sql = this.ctx.storage.sql;
    sql.exec(`
      CREATE TABLE IF NOT EXISTS _sql_schema_migrations (
        version INTEGER PRIMARY KEY,
        applied_at_ms INTEGER NOT NULL
      )
    `);
    const current = sql
      .exec<{ version: number }>(
        "SELECT COALESCE(MAX(version), 0) AS version FROM _sql_schema_migrations",
      )
      .one().version;

    if (current < 1) {
      this.ctx.storage.transactionSync(() => {
        sql.exec(`
          CREATE TABLE IF NOT EXISTS app_attest_keys (
            key_hash BLOB PRIMARY KEY CHECK(length(key_hash) = 32),
            public_key_spki BLOB NOT NULL,
            receipt BLOB NOT NULL,
            environment TEXT NOT NULL CHECK(environment IN ('development', 'production')),
            aaguid BLOB NOT NULL CHECK(length(aaguid) = 16),
            sign_count INTEGER NOT NULL DEFAULT 0 CHECK(sign_count >= 0),
            status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active', 'revoked')),
            minute_bucket INTEGER NOT NULL DEFAULT 0,
            minute_requests INTEGER NOT NULL DEFAULT 0,
            utc_day INTEGER NOT NULL DEFAULT 0,
            day_photos INTEGER NOT NULL DEFAULT 0,
            last_validation_category INTEGER,
            last_bundle_version TEXT,
            created_at_ms INTEGER NOT NULL,
            last_seen_at_ms INTEGER NOT NULL
          ) WITHOUT ROWID
        `);
        sql.exec(`
          CREATE TABLE IF NOT EXISTS app_attest_challenges (
            key_hash BLOB NOT NULL CHECK(length(key_hash) = 32),
            purpose TEXT NOT NULL CHECK(purpose IN ('attestation', 'assertion')),
            challenge_hash BLOB NOT NULL CHECK(length(challenge_hash) = 32),
            issued_at_ms INTEGER NOT NULL,
            expires_at_ms INTEGER NOT NULL,
            PRIMARY KEY(key_hash, purpose, challenge_hash)
          ) WITHOUT ROWID
        `);
        sql.exec(
          "CREATE INDEX IF NOT EXISTS idx_app_attest_challenge_expiry ON app_attest_challenges(expires_at_ms)",
        );
        sql.exec(
          "INSERT INTO _sql_schema_migrations(version, applied_at_ms) VALUES(1, ?)",
          Date.now(),
        );
      });
    }
  }

  private keyRow(keyID: Uint8Array): KeyRow | undefined {
    return this.ctx.storage.sql
      .exec<KeyRow>(
        `SELECT public_key_spki, sign_count, status, minute_bucket,
                minute_requests, utc_day, day_photos
           FROM app_attest_keys WHERE key_hash = ?`,
        exactBuffer(keyID),
      )
      .toArray()[0];
  }

  private challengeRow(
    keyID: Uint8Array,
    purpose: AppAttestPurpose,
    challengeHash: Uint8Array,
  ): ChallengeRow | undefined {
    return this.ctx.storage.sql
      .exec<ChallengeRow>(
        `SELECT expires_at_ms
           FROM app_attest_challenges
          WHERE key_hash = ? AND purpose = ? AND challenge_hash = ?`,
        exactBuffer(keyID),
        purpose,
        exactBuffer(challengeHash),
      )
      .toArray()[0];
  }

  private challengeStatus(
    keyID: Uint8Array,
    purpose: AppAttestPurpose,
    challengeHash: Uint8Array,
    nowMs: number,
  ): AppAttestStateFailure | null {
    const stored = this.challengeRow(keyID, purpose, challengeHash);
    if (stored === undefined) {
      return stateFailure("challenge_used");
    }
    if (stored.expires_at_ms < nowMs) {
      return stateFailure("challenge_expired");
    }
    return null;
  }

  private async scheduleNextAlarm(): Promise<void> {
    const nextChallenge = this.ctx.storage.sql
      .exec<{ expires_at_ms: number | null }>(
        "SELECT MIN(expires_at_ms) AS expires_at_ms FROM app_attest_challenges",
      )
      .one().expires_at_ms;
    const oldestKey = this.ctx.storage.sql
      .exec<{ last_seen_at_ms: number | null }>(
        "SELECT MIN(last_seen_at_ms) AS last_seen_at_ms FROM app_attest_keys",
      )
      .one().last_seen_at_ms;
    const nextKeyExpiry = oldestKey === null ? null : oldestKey + KEY_RETENTION_MS;
    const candidates = [nextChallenge, nextKeyExpiry].filter(
      (value): value is number => value !== null,
    );
    const next = candidates.length === 0 ? null : Math.min(...candidates);
    if (next === null) {
      await this.ctx.storage.deleteAlarm();
      return;
    }
    await this.ctx.storage.setAlarm(Math.max(next, Date.now() + 1_000));
  }

  async issueChallenge(input: IssueChallengeInput): Promise<AppAttestChallengeResult> {
    if (
      input.keyID.byteLength !== CHALLENGE_BYTES ||
      (input.purpose !== "attestation" && input.purpose !== "assertion") ||
      !isValidNow(input.nowMs)
    ) {
      return stateFailure("server_misconfigured");
    }

    const challenge = crypto.getRandomValues(new Uint8Array(CHALLENGE_BYTES));
    const challengeHash = await sha256(challenge);
    const expiresAt = input.nowMs + CHALLENGE_TTL_MS;
    const result = this.ctx.storage.transactionSync<AppAttestChallengeResult>(() => {
      this.ctx.storage.sql.exec(
        "DELETE FROM app_attest_challenges WHERE expires_at_ms < ?",
        input.nowMs,
      );
      const existingKey = this.keyRow(input.keyID);
      if (input.purpose === "assertion" && existingKey?.status !== "active") {
        return stateFailure("key_not_registered");
      }
      if (input.purpose === "attestation" && existingKey !== undefined) {
        return stateFailure("key_already_registered");
      }

      this.ctx.storage.sql.exec(
        `INSERT INTO app_attest_challenges
           (key_hash, purpose, challenge_hash, issued_at_ms, expires_at_ms)
         VALUES (?, ?, ?, ?, ?)`,
        exactBuffer(input.keyID),
        input.purpose,
        exactBuffer(challengeHash),
        input.nowMs,
        expiresAt,
      );
      // Keep a small bounded set so overlapping URLSession requests cannot
      // invalidate one another while still preventing challenge-row abuse.
      this.ctx.storage.sql.exec(
        `DELETE FROM app_attest_challenges
          WHERE key_hash = ? AND purpose = ? AND challenge_hash NOT IN (
            SELECT challenge_hash
              FROM app_attest_challenges
             WHERE key_hash = ? AND purpose = ?
             ORDER BY issued_at_ms DESC, challenge_hash DESC
             LIMIT ?
          )`,
        exactBuffer(input.keyID),
        input.purpose,
        exactBuffer(input.keyID),
        input.purpose,
        MAX_OUTSTANDING_CHALLENGES_PER_PURPOSE,
      );
      return {
        ok: true,
        challenge: encodeBase64URL(challenge),
        expiresAt: new Date(expiresAt).toISOString(),
      };
    });

    if (result.ok) {
      await this.scheduleNextAlarm();
    }
    return result;
  }

  async registerKey(input: RegisterKeyInput): Promise<AppAttestOperationResult> {
    if (
      input.keyID.byteLength !== CHALLENGE_BYTES ||
      input.challenge.byteLength !== CHALLENGE_BYTES ||
      input.attestationObject.byteLength === 0 ||
      !isValidNow(input.nowMs) ||
      this.env.APP_ATTEST_APP_ID === undefined ||
      (this.env.APP_ATTEST_ENVIRONMENT !== "development" &&
        this.env.APP_ATTEST_ENVIRONMENT !== "production")
    ) {
      return stateFailure("server_misconfigured");
    }

    const challengeHash = await sha256(input.challenge);
    const existingKey = this.keyRow(input.keyID);
    if (existingKey?.status === "active") {
      // Registration is idempotent so a lost 204 response does not force the
      // app to generate another App Attest key.
      await this.scheduleNextAlarm();
      return { ok: true };
    }
    if (existingKey !== undefined) {
      return stateFailure("key_already_registered");
    }
    const preflightProblem = this.challengeStatus(input.keyID, "attestation", challengeHash, input.nowMs);
    if (preflightProblem !== null) {
      return preflightProblem;
    }

    let verified: Awaited<ReturnType<typeof verifyAttestation>>;
    try {
      const clientDataHash = await sha256(createAttestationClientData(input.challenge));
      verified = await verifyAttestation({
        keyId: input.keyId,
        attestationObject: input.attestationObject,
        clientDataHash,
        appID: this.env.APP_ATTEST_APP_ID,
        environment: this.env.APP_ATTEST_ENVIRONMENT,
        now: new Date(input.nowMs),
      });
    } catch (error) {
      if (error instanceof AppAttestVerificationError || error instanceof TypeError) {
        return stateFailure("invalid_attestation");
      }
      throw error;
    }

    if (
      !equalBytes(verified.keyHash, input.keyID) ||
      !verificationMetadataAllowed(
        this.env,
        verified.validationCategory,
        verified.bundleVersion,
      )
    ) {
      return stateFailure("invalid_attestation");
    }

    const result = this.ctx.storage.transactionSync<AppAttestOperationResult>(() => {
      const concurrentKey = this.keyRow(input.keyID);
      if (concurrentKey?.status === "active") {
        return { ok: true };
      }
      if (concurrentKey !== undefined) {
        return stateFailure("key_already_registered");
      }
      const problem = this.challengeStatus(input.keyID, "attestation", challengeHash, input.nowMs);
      if (problem !== null) {
        return problem;
      }

      this.ctx.storage.sql.exec(
        `DELETE FROM app_attest_challenges
          WHERE key_hash = ? AND purpose = 'attestation' AND challenge_hash = ?`,
        exactBuffer(input.keyID),
        exactBuffer(challengeHash),
      );
      this.ctx.storage.sql.exec(
        `INSERT INTO app_attest_keys
           (key_hash, public_key_spki, receipt, environment, aaguid, sign_count,
            status, last_validation_category, last_bundle_version, created_at_ms, last_seen_at_ms)
         VALUES (?, ?, ?, ?, ?, 0, 'active', ?, ?, ?, ?)`,
        exactBuffer(input.keyID),
        exactBuffer(verified.publicKeySpki),
        exactBuffer(verified.receipt),
        this.env.APP_ATTEST_ENVIRONMENT,
        exactBuffer(verified.aaguid),
        verified.validationCategory ?? null,
        verified.bundleVersion ?? null,
        input.nowMs,
        input.nowMs,
      );
      return { ok: true };
    });
    await this.scheduleNextAlarm();
    return result;
  }

  async authorizeAnalysis(input: AuthorizeAnalysisInput): Promise<AppAttestOperationResult> {
    if (
      input.keyID.byteLength !== CHALLENGE_BYTES ||
      input.challenge.byteLength !== CHALLENGE_BYTES ||
      input.bodyHash.byteLength !== 32 ||
      input.assertionObject.byteLength === 0 ||
      input.method !== "POST" ||
      input.path !== "/v1/analyze" ||
      !Number.isInteger(input.photoCount) ||
      input.photoCount < 1 ||
      input.photoCount > LIMITS.maxPhotos ||
      !isValidNow(input.nowMs) ||
      this.env.APP_ATTEST_APP_ID === undefined
    ) {
      return stateFailure("server_misconfigured");
    }

    const key = this.keyRow(input.keyID);
    if (key?.status !== "active") {
      return stateFailure("key_not_registered");
    }
    const challengeHash = await sha256(input.challenge);
    const preflightProblem = this.challengeStatus(input.keyID, "assertion", challengeHash, input.nowMs);
    if (preflightProblem !== null) {
      return preflightProblem;
    }

    let verified: Awaited<ReturnType<typeof verifyAssertion>>;
    try {
      const clientData = createAssertionClientData({
        method: input.method,
        path: input.path,
        challenge: input.challenge,
        bodyHash: input.bodyHash,
      });
      verified = await verifyAssertion({
        assertionObject: input.assertionObject,
        clientDataHash: await sha256(clientData),
        appID: this.env.APP_ATTEST_APP_ID,
        publicKeySpki: bytesFromBlob(key.public_key_spki),
      });
    } catch (error) {
      if (error instanceof AppAttestVerificationError || error instanceof TypeError) {
        return stateFailure("invalid_assertion");
      }
      throw error;
    }

    if (
      !verificationMetadataAllowed(
        this.env,
        verified.validationCategory,
        verified.bundleVersion,
      )
    ) {
      return stateFailure("invalid_assertion");
    }

    const result = this.ctx.storage.transactionSync<AppAttestOperationResult>(() => {
      const currentKey = this.keyRow(input.keyID);
      if (currentKey?.status !== "active") {
        return stateFailure("key_not_registered");
      }
      const problem = this.challengeStatus(input.keyID, "assertion", challengeHash, input.nowMs);
      if (problem !== null) {
        return problem;
      }

      this.ctx.storage.sql.exec(
        `DELETE FROM app_attest_challenges
          WHERE key_hash = ? AND purpose = 'assertion' AND challenge_hash = ?`,
        exactBuffer(input.keyID),
        exactBuffer(challengeHash),
      );
      if (!Number.isSafeInteger(verified.signCount) || verified.signCount <= currentKey.sign_count) {
        return stateFailure("counter_replay");
      }

      const minuteBucket = Math.floor(input.nowMs / 60_000);
      const utcDay = Math.floor(input.nowMs / 86_400_000);
      const minuteRequests = currentKey.minute_bucket === minuteBucket ? currentKey.minute_requests : 0;
      const dayPhotos = currentKey.utc_day === utcDay ? currentKey.day_photos : 0;
      const minuteLimited = minuteRequests >= MAX_REQUESTS_PER_MINUTE;
      const dayLimited = dayPhotos + input.photoCount > MAX_PHOTOS_PER_UTC_DAY;
      const allowed = !minuteLimited && !dayLimited;

      this.ctx.storage.sql.exec(
        `UPDATE app_attest_keys SET
           sign_count = ?,
           minute_bucket = ?,
           minute_requests = ?,
           utc_day = ?,
           day_photos = ?,
           last_validation_category = COALESCE(?, last_validation_category),
           last_bundle_version = COALESCE(?, last_bundle_version),
           last_seen_at_ms = ?
         WHERE key_hash = ?`,
        verified.signCount,
        minuteBucket,
        allowed ? minuteRequests + 1 : minuteRequests,
        utcDay,
        allowed ? dayPhotos + input.photoCount : dayPhotos,
        verified.validationCategory ?? null,
        verified.bundleVersion ?? null,
        input.nowMs,
        exactBuffer(input.keyID),
      );

      if (minuteLimited) {
        const retryAfter = Math.max(1, Math.ceil(((minuteBucket + 1) * 60_000 - input.nowMs) / 1_000));
        return stateFailure("rate_limited", retryAfter);
      }
      if (dayLimited) {
        const retryAfter = Math.max(1, Math.ceil(((utcDay + 1) * 86_400_000 - input.nowMs) / 1_000));
        return stateFailure("rate_limited", retryAfter);
      }
      return { ok: true };
    });
    await this.scheduleNextAlarm();
    return result;
  }

  async alarm(): Promise<void> {
    const now = Date.now();
    this.ctx.storage.transactionSync(() => {
      this.ctx.storage.sql.exec(
        "DELETE FROM app_attest_challenges WHERE expires_at_ms <= ?",
        now,
      );
      this.ctx.storage.sql.exec(
        "DELETE FROM app_attest_keys WHERE last_seen_at_ms <= ?",
        now - KEY_RETENTION_MS,
      );
    });
    await this.scheduleNextAlarm();
  }
}
