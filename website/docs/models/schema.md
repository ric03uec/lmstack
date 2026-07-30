---
sidebar_position: 3
title: Model YAML schema
---

# Model YAML schema

`hosts/<host>/<engine>/models/<slug>.yml` is the contract. One file drives the
compose service, the LiteLLM routing table, and the VRAM budget check. There is
no second place to register a model.

`make validate` enforces everything below, offline, before Ansible connects to
anything.

## Common fields

| Field | Type | Meaning |
|---|---|---|
| `slug` | string | Must equal the filename stem. It is also the primary LiteLLM alias. |
| `engine` | `vllm` \| `llamacpp` | Selects which extra fields are required, and must match the host's engine. |
| `image` | string | Container image for the engine process. |
| `port` | int | Host-side port. Unique within a host, and rendered as `127.0.0.1:<port>:<internal>`. |
| `vram_estimate_gib` | int | What this model occupies. Summed across `active_models` and checked against `vram_budget_gib`. |
| `tier` | `8g` \| `24g` \| `48g` | The card size this entry is sized for. A model may not exceed its tier's ceiling. |
| `mandatory` | bool | Whether the recommender fits this one before anything else. |
| `virtual_models` | list | Extra LiteLLM aliases. Globally unique per host. |
| `extra_args` | list | Passed to the engine verbatim, one list item per argv element. |
| `notes` | string | Why. See below. |

## vLLM-only

| Field | Meaning |
|---|---|
| `hf_model` | The HuggingFace repo id vLLM loads. |
| `max_model_len` | Context length. |
| `gpu_memory_utilization` | Fraction of *total* card memory, weights included. |
| `max_num_seqs` | Concurrent sequences. |
| `dtype` | `auto`, `bfloat16`, … |

## llama.cpp-only

| Field | Meaning |
|---|---|
| `hf_repo` | The GGUF repository. |
| `hf_file` | The exact GGUF filename to download. |
| `context` | Context length, passed as `-c`. |
| `n_gpu_layers` | Layers to offload. `999` means all; llama.cpp clamps to the real count. |
| `parallel_slots` | Concurrent slots, passed as `-np`. |

## Rules the validator enforces

- `slug` equals the filename stem.
- Ports are unique within a host, and never collide with the gateway port.
- `sum(vram_estimate_gib)` over `active_models` fits `vram_budget_gib`.
- No model exceeds its declared tier's ceiling.
- Aliases are unique per host. **LiteLLM silently shadows a duplicate
  `model_name` rather than erroring**, so a collision would otherwise cost you
  an afternoon.
- Every slug in `active_models` names a file that exists.
- `chat_template_file`, if set, points at a file that exists.
- The host serves every alias in `required_common_aliases`.
- Anything a pi extension advertises is an alias some host actually serves.

## `extra_args` is a list of argv elements, not a command line

```yaml
extra_args:
  - --flash-attn
  - "on"          # its own element, not "--flash-attn on"
```

The template renders one YAML item per argument. Writing `--flash-attn on` as a
single string passes it as one argv element, which the engine rejects.

## The `notes` block is not decoration

Every model file carries prose explaining the quantization choice, the sizing
arithmetic, and what breaks. That is why these are YAML-with-prose rather than
rows in a table:

> Q4_K_M (~4.7 GiB weights) plus ~1.3 GiB of KV cache at 16384 context fits
> inside an 8 GiB budget with a little headroom. On unified-memory APUs the
> relevant limit is the GTT allocation, not a dedicated VRAM pool […]
>
> Quantization and tool calling interact. The source deployment this was ported
> from found Q4_K_M improvising tool-call wrappers that llama.cpp's chat parser
> does not recognise […] Q6_K restored adherence.

Six months later, that paragraph is the difference between a ten-minute fix and
rediscovering the problem from scratch.
