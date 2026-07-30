// pi extension: register an lmstack h2-amd host (llama.cpp behind LiteLLM) as
// the `lmstack-h2` provider.
//
// h2-amd is usually the machine you are typing on, so the default base URL is
// loopback. Override it with LMSTACK_H2_URL for a second AMD box on the LAN.
//
// See lmstack-h1.ts for why the settings reader is duplicated rather than
// shared, and for the model-id / LiteLLM-alias contract that T0.10 enforces.

import * as fs from "node:fs";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

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
  pi.registerProvider("lmstack-h2", {
    name: "lmstack h2-amd (llama.cpp Vulkan)",
    baseUrl: setting("LMSTACK_H2_URL", "http://127.0.0.1:4000/v1"),
    apiKey: setting("LMSTACK_H2_KEY", ""),
    api: "openai-completions",
    models: [
      {
        id: "qwen2.5-coder-7b",
        name: "Qwen2.5 Coder 7B Q4_K_M (h2-amd, llama.cpp)",
        reasoning: false,
        input: ["text"],
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
        // Same alias and the same context as h1-nvidia serves. That parity is
        // the point: switching provider does not change how you prompt.
        contextWindow: 16384,
        maxTokens: 4096,
      },
    ],
  });
}
