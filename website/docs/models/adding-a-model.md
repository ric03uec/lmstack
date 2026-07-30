---
sidebar_position: 2
title: Adding a model
---

# Adding a model

One YAML file, one line in `active_models`, and — if you want your editor to see
it — one entry in the pi extension. `make validate` tells you which of the three
you forgot.

## 1. Write the model file

`hosts/<host>/<engine>/models/<slug>.yml`. The filename stem must equal `slug`.
Copy the closest existing entry rather than starting from the
[schema](schema) — the existing files carry the sizing arithmetic in their
`notes`, and yours should too.

```yaml
---
slug: qwen3-8b
engine: llamacpp
hf_repo: bartowski/Qwen_Qwen3-8B-GGUF
hf_file: Qwen_Qwen3-8B-Q6_K.gguf
image: ghcr.io/ggml-org/llama.cpp:server-vulkan
port: 8003
context: 16384
n_gpu_layers: 999
parallel_slots: 1
extra_args:
  - --jinja
vram_estimate_gib: 8
tier: 24g
mandatory: false
virtual_models:
  - name: qwen3-8b
notes: |
  Why this quantization, what the VRAM figure is made of, and what breaks.
```

Pick the port by looking at what the host already uses. `make validate` catches
a collision, but only after you have written the file.

## 2. Estimate the VRAM honestly

`vram_estimate_gib` is what the budget check believes. Getting it wrong does not
produce a validation error — it produces an out-of-memory error on the host.

**llama.cpp**: GGUF file size on disk, plus the KV cache. The cache is roughly
`context × layers × 2 × kv_heads × head_dim × 2 bytes`; for a 7B at 16k that
lands near 1.3 GiB. Round up.

**vLLM**: `gpu_memory_utilization` is a fraction of the *whole card*, and weights
are inside that allowance, not on top of it. Set `vram_estimate_gib` to what you
expect the process to occupy in total.

Leave headroom. The classifier already reserves 1 GiB for the display server and
runtime allocations, but a card that reports exactly 8 GiB does not have 8 GiB.

## 3. Activate it

```yaml
# hosts/h2-amd/ansible/vars.yml
active_models:
  - qwen2.5-coder-7b
  - qwen3-8b
```

A slug not in `active_models` is inert: no container, no LiteLLM route, no
download. That is how the catalog can carry entries most hosts never run.

## 4. Advertise it to your editor

If you want it in pi, add it to `pi-config/extensions/lmstack-h2.ts` with `id`
set to the LiteLLM alias and `contextWindow` set to what the YAML declares. This
is not optional bookkeeping — `make validate` (T0.10) fails if an extension
advertises a model no host serves, and the reverse mistake, deploying a model
your editor never offers, is the one you notice a week later.

## 5. Validate, render, deploy

```bash
make validate                     # schema, ports, budget, aliases, tiers
BLESS=1 tests/render_test.sh      # re-bless the golden files
git diff tests/golden/            # read this before committing it
make test
make up HOST=h2-amd
```

`BLESS=1` records whatever the templates currently produce, including a mistake.
Reading the golden diff is the step that catches template bugs — it is how the
Jinja whitespace bug that silently dropped LiteLLM aliases was found.

## 6. Check it actually serves tool calls

A new model is not working just because it answers.

```bash
make verify HOST=h2-amd
```

T3.4 sends a request with a tool definition and asserts the response populates
`tool_calls` rather than describing the call in prose. A model that fails it
will break every agent loop pointed at it, in a way that looks like the agent's
fault.
