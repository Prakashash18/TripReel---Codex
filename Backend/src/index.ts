import { handleRequest, type Env } from "./handler.ts";

export { AppAttestShard } from "./app-attest-state.ts";
export { handleRequest } from "./handler.ts";
export type { Env } from "./handler.ts";

export default {
  fetch(request: Request, env: Env): Promise<Response> {
    return handleRequest(request, env);
  },
};
