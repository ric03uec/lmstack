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
  // See lmstack-h1.ts: no key means no host of this kind is configured, and a
  // blank key registered anyway surfaces as "No API key for provider" the
  // first time anything touches it. Skip registration instead.
  const apiKey = setting("LMSTACK_H2_KEY", "");
  if (!apiKey) return;

  pi.registerProvider("lmstack-h2", {
    name: "lmstack h2-amd (llama.cpp Vulkan)",
    baseUrl: setting("LMSTACK_H2_URL", "http://127.0.0.1:4000/v1"),
    apiKey,
    api: "openai-completions",
    models: [
      {
        id: "hermes-3-llama-3.1-8b",
        name: "Hermes 3 Llama 3.1 8B Q4_K_M (h2-amd, llama.cpp)",
        reasoning: false,
        input: ["text"],
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
        // Hermes was picked for h2-amd specifically because it obeys the
        // <tool_call>…</tool_call> tag priming that llama.cpp's chat parser
        // extracts. Qwen 2.5 Coder wraps calls in ```json fences that the
        // parser refuses to unwrap; see docs/tool-calling-on-h2-amd.md.
        // Alias parity with h1-nvidia is deliberately broken here — h1
        // serves qwen2.5-coder-7b under vLLM, which handles tool calling
        // through xgrammar and doesn't need the same trick.
        contextWindow: 32768,
        maxTokens: 4096,
      },
    ],
  });
}
