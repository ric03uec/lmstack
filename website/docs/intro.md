---
slug: /
sidebar_position: 1
title: Introduction
---

# lmstack

A local LLM stack for development: models served on hardware you own, behind one
OpenAI-compatible endpoint, wired into your editor.

```
              control host — where you write code
┌─────────────────────────────────────────────────────────────┐
│  pi   ·   Claude Code   ·   opencode                        │
│  pi-config/ — one provider entry per host, and the same     │
│  model alias on both, so switching is a flag not a rewrite  │
└──────────────────────────────┬──────────────────────────────┘
                               │  OpenAI-compatible + master key
               ┌───────────────┴───────────────┐
               │                               │
┌──────────────▼──────────────┐ ┌──────────────▼──────────────┐
│ h1-nvidia — NVIDIA + CUDA   │ │ h2-amd — AMD, or localhost  │
├─────────────────────────────┤ ├─────────────────────────────┤
│  LiteLLM             :4000  │ │  LiteLLM             :4000  │
│    routing · keys · usage   │ │    routing · keys · usage   │
│       │                     │ │       │                     │
│  ┌────▼──────────────────┐  │ │  ┌────▼──────────────────┐  │
│  │ vLLM           :8001  │  │ │  │ llama.cpp      :8001  │  │
│  │ qwen2.5-coder-7b      │  │ │  │ qwen2.5-coder-7b      │  │
│  │ CUDA · AWQ 4-bit      │  │ │  │ Vulkan · GGUF Q4_K_M  │  │
│  └───────────────────────┘  │ │  └───────────────────────┘  │
│                             │ │                             │
│  Postgres — no ports at all │ │  Postgres — no ports at all │
└─────────────────────────────┘ └─────────────────────────────┘
```

Read it in three layers.

**The boundary.** Only `:4000` leaves either box. Engines bind `127.0.0.1` and
Postgres publishes nothing at all, so the gateway is the only thing an attacker
on your LAN can reach — and `tests/render_test.sh` fails the build if a template
ever stops doing that. Putting the host on Tailscale rather than opening a
firewall port is [the recommended way in](operations/tailscale).

**The gateway.** LiteLLM holds the routing table, the master key, and the usage
UI. It is what makes two very different engines look like one OpenAI-compatible
provider, and it is why the control host needs no per-engine knowledge.

**The engines.** One container per active model, numbered from `:8001`. Adding a
model to `active_models` adds a container; the VRAM budget check is what stops
you adding one that will not fit.

The two hosts are not a cluster. Nothing balances between them and they do not
know about each other — they are two independent boxes your editor can point at,
which is why moving a workload between them is a `--provider` change.

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

Paste this at your coding agent and it will take it from there:

> install the lmstack skill from https://ric03uec.github.io/lmstack/install

- [Install the skill](install) — that page, including how to do it by hand.
- [The skill](skill) — what the installer does at each phase, and what it refuses to do.
- [Quickstart](quickstart) — the same work done explicitly, without an agent.
- [Troubleshooting](operations/troubleshooting) — when the endpoint does not answer.
