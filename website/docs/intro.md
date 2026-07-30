---
slug: /
sidebar_position: 1
title: Introduction
---

# lmstack

A local LLM stack for development: models served on hardware you own, behind one
OpenAI-compatible endpoint, wired into your editor.

```
  ┌──────────────────────┐          ┌──────────────────────────┐
  │  control host        │          │  GPU host                │
  │  pi / Claude Code /  │  HTTP    │                          │
  │  opencode            ├─────────▶│  LiteLLM  :4000          │
  │                      │  OpenAI  │     │                    │
  └──────────────────────┘   API    │     ├─▶ engine  :8001 *  │
                                    │     ├─▶ engine  :8002 *  │
                                    │     └─▶ postgres      *  │
                                    │                          │
                                    │  * = 127.0.0.1 only      │
                                    └──────────────────────────┘
```

Only the gateway is reachable off-box. The engines bind loopback, and
`tests/render_test.sh` fails the build if a template ever stops doing that.

## What it is for

Running a coding model on your own GPU, and having your editor treat it like any
other provider. Two host roles ship working:

| Host role | Hardware | Engine | Why |
|---|---|---|---|
| [`h1-nvidia`](hosts/h1-nvidia) | NVIDIA + CUDA | vLLM | Throughput, and the most mature tool-call parsing. |
| [`h2-amd`](hosts/h2-amd) | AMD iGPU, APU, or dGPU — including the laptop you are reading this on | llama.cpp (Vulkan) | Vulkan runs on the AMD hardware you already have. ROCm supports a narrow list of cards. |

Both expose the alias `qwen2.5-coder-7b`. Moving a workload from a DGX to a
laptop is a `--provider` change and nothing else.

## The floor is 8 GiB

The default catalog is sized so that the first `make up` succeeds on an 8 GiB
card. That constraint drove real decisions — AWQ 4-bit rather than FP16 weights
on NVIDIA, Q4_K_M rather than Q8 on AMD — and they are documented where they
were made, in each model's YAML.

On unified-memory AMD APUs the useful figure is the GTT budget, not the BIOS
VRAM carve-out. A laptop reporting "2 GiB of VRAM" usually has around 30 GiB
available. [The probe](skill#phase-2--probe) works this out rather than asking
you.

## What this is not

It is not a production serving platform. There is no autoscaling, no multi-node
scheduling, no authentication beyond a single LiteLLM master key, and no
attempt at high availability. It is a development stack: one box, a couple of
models, an endpoint that stays up.

It also will not run on CPU. Inference without a GPU is slow enough to look
broken, so the installer refuses rather than giving you something you would
blame on the repo.

## Where to go next

- [Quickstart](quickstart) — from a clone to an answering endpoint.
- [The skill](skill) — the interactive installer, and what it will and will not do.
- [Troubleshooting](operations/troubleshooting) — when the endpoint does not answer.
