// pi extension: register an lmstack h1-nvidia host (vLLM behind LiteLLM) as the
// `lmstack-h1` provider.
//
// Configuration comes from ~/.pi/agent/extensions/.env — see .env.example.
// Nothing here is machine-specific, so this file is safe to commit; the .env
// beside it is not, and sync.sh never copies it in either direction.
//
// The advertised model ids must be LiteLLM aliases the host actually serves.
// `make validate` (T0.10) fails the build if they drift apart, so adding a
// model to hosts/h1-nvidia/ansible/vars.yml means adding it here too.

import * as fs from "node:fs";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// Duplicated in lmstack-h2.ts rather than shared. pi loads each entry in
// `packages` as a standalone extension, and a relative import between two of
// them is not part of that contract. Twenty lines twice beats a module that
// works until the loader changes.
function setting(name: string, fallback: string): string {
  const fromEnv = process.env[name];
  if (fromEnv) return fromEnv;
  try {
    const contents = fs.readFileSync(path.join(__dirname, ".env"), "utf8");
    for (const line of contents.split("\n")) {
      const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
      if (m && m[1] === name) return m[2].replace(/^["']|["']$/g, "");
    }
  } catch {
    // No .env yet. Fall through to the default.
  }
  return fallback;
}

export default function (pi: ExtensionAPI) {
  pi.registerProvider("lmstack-h1", {
    name: "lmstack h1-nvidia (vLLM)",
    // The default assumes an ~/.ssh/config or Tailscale name for the host.
    // Set LMSTACK_H1_URL if yours is reachable under a different name.
    baseUrl: setting("LMSTACK_H1_URL", "http://h1-nvidia:4000/v1"),
    apiKey: setting("LMSTACK_H1_KEY", ""),
    api: "openai-completions",
    models: [
      {
        id: "qwen2.5-coder-7b",
        name: "Qwen2.5 Coder 7B AWQ (h1-nvidia, vLLM)",
        reasoning: false,
        input: ["text"],
        // Local inference has no per-token price. Zeroes keep pi's cost
        // display truthful rather than inventing a cloud figure.
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
        // Matches max_model_len in the model YAML. Raising it here does not
        // raise it on the server; the request is truncated or rejected there.
        contextWindow: 16384,
        maxTokens: 4096,
      },
    ],
  });
}
