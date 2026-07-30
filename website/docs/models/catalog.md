---
sidebar_position: 1
title: The catalog
---

# The catalog

Every model that ships with the repo, sized for the 8 GiB floor.

## h1-nvidia (vLLM)

| Slug | Weights | Context | ~VRAM | Default? |
|---|---|---|---|---|
| `qwen2.5-coder-7b` | `Qwen/Qwen2.5-Coder-7B-Instruct-AWQ` | 16384 | 6 GiB | yes |
| `qwen3-4b-instruct` | `Qwen/Qwen3-4B-Instruct-2507` | 16384 | 5 GiB | no |

## h2-amd (llama.cpp, Vulkan)

| Slug | Weights | Context | ~VRAM | Default? |
|---|---|---|---|---|
| `qwen2.5-coder-7b` | `bartowski/Qwen2.5-Coder-7B-Instruct-GGUF` Q4_K_M | 16384 | 6 GiB | yes |
| `gemma-3-4b-it` | `bartowski/google_gemma-3-4b-it-GGUF` Q4_K_M | 8192 | 4 GiB | no |

## The parity alias

`qwen2.5-coder-7b` is served by both hosts, from the same base model, through
different engines and different quantizations. That is what makes the control
host configuration engine-agnostic, and `tests/parity.yml` fails the build if a
host stops honouring it.

The consequence is worth stating plainly: if your GPU cannot fit the 7B, the
installer will tell you the host will not serve the alias every other host
serves, and that anything pointed at it by model name needs reconfiguring. That
is a warning, not a failure — a smaller host is still useful — but it is not
silent.

## Why these and not something larger

The catalog is sized for the smallest card the repo supports. A 24 GiB or 48 GiB
machine gets a warning saying so:

> This host has 22 GiB spare after the recommendation. The default catalog is
> sized for the 8 GiB floor; add a larger model YAML to
> `hosts/h1-nvidia/vllm/models/` to use the rest.

The tier system exists for that: `pick_tier` chooses the largest tier your
budget supports **that the catalog actually stocks**. Choosing on budget alone
would hand a 48 GiB machine an empty tier and declare it unsupported — which was
a real bug, found by running the classifier against real hardware rather than
only against fixtures.

## Choosing a quantization

For a coding model behind an agent loop, the practical ordering is:

1. **Q6_K** if it fits. Tool-call adherence is noticeably better.
2. **Q4_K_M** as the default. Fits an 8 GiB budget with the KV cache.
3. **AWQ 4-bit** on vLLM, where it is the only way a 7B fits in 8 GiB at all.

Below Q4 the model starts improvising tool-call syntax the parser does not
recognise, and the failure looks like a broken agent rather than a quality
regression. See [h2-amd](../hosts/h2-amd#quantization-and-tool-calling-interact).
