import assert from "node:assert/strict";
import test from "node:test";

import { handleRequest } from "../src/handler.ts";

const ENV = {
  OPENAI_API_KEY: "sk-test-not-a-real-key-0000000000000000",
  TRIPREEL_AUTH_TOKEN: "test-token-that-is-long-enough-for-validation",
};

for (const path of ["generate", "status", "content"]) {
  test(`retires the legacy AI video ${path} route without calling a provider`, async () => {
    let upstreamCalled = false;
    const response = await handleRequest(
      new Request(`https://analysis.example/v1/video/${path}`, {
        method: "POST",
        headers: {
          authorization: `Bearer ${ENV.TRIPREEL_AUTH_TOKEN}`,
          "content-type": "application/json",
        },
        body: "{}",
      }),
      ENV,
      async () => {
        upstreamCalled = true;
        throw new Error("The retired route must not call an upstream provider");
      },
    );

    assert.equal(response.status, 410);
    assert.equal(upstreamCalled, false);
    assert.equal((await response.json()).error.code, "feature_retired");
  });
}
