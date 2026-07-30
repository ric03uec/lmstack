# lmstack

A local LLM stack you can actually develop against: a GPU host serving models
behind one OpenAI-compatible endpoint, and a code editor already pointed at it.

Bring a DGX Spark, a gaming desktop, or the AMD laptop you already own. The
default catalog is sized to come up on **8 GB of VRAM**.

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

Only `:4000` leaves either box. The engines and Postgres bind loopback, and a
test fails the build if a template ever stops doing that. A second active model
is a second engine container, on `:8002`.

## Quickstart

You are already sitting in Claude Code, opencode, or pi. Type this:

> install the lmstack skill from https://ric03uec.github.io/lmstack/install

That page is written for your agent to read, not for you. It tells it what to
fetch and where to put it. Then:

> use the lmstack skill to give me a starting point

The skill asks which host to target, probes its hardware, picks a model that
fits the VRAM it found, shows you every file it wants to write, and runs the
playbooks. **Nothing to clone first** — it does that itself, once you say where.

Working on lmstack rather than using it? Clone it and run `make skill-install`,
which points the installed skill at your clone instead of fetching its own.
[Install the skill](https://ric03uec.github.io/lmstack/install) covers both.

## What runs where

| Host role | Hardware | Engine | Why |
|---|---|---|---|
| `h1-nvidia` | NVIDIA + CUDA | vLLM | Throughput and mature tool-call parsing. |
| `h2-amd` | AMD iGPU / APU / dGPU, including localhost | llama.cpp (Vulkan) | Vulkan works on the AMD hardware you already have; ROCm supports a narrow list of cards. |

Both expose the alias `qwen2.5-coder-7b`. Your editor configuration does not
change when you move between them — enforced by `tests/parity.yml`.

Models are data. `hosts/<host>/<engine>/models/<slug>.yml` is the single source
for the compose file, the LiteLLM routing table, and the VRAM budget check.
Adding a model means adding one YAML file.

## Verifying without a GPU

The whole static suite runs on any machine:

```bash
make test
```

It validates every model YAML against the schema, proves the validator rejects
known-bad configuration, checks alias parity across engines, and feeds real
secret shapes through the `.stacklog` writer to confirm none survive.

This is what CI runs on every pull request, so a change that breaks it fails
before review rather than during a bring-up.

## Documentation

Full docs at **https://ric03uec.github.io/lmstack** — host setup, the model
schema, editor bridges, and a troubleshooting table keyed to the same `kind`
values the change log records.

```bash
make docs          # localhost:3000, hot reload
make docs-build    # static build; fails on a broken link
```

## Privacy

`.stacklog/` records what changed on your hosts, for your own later analysis.
It is gitignored, never leaves your machine, identifies hosts by inventory alias
rather than by address, and passes every value through a redaction filter that
has its own test. Prompts and completions are never recorded.

## License

Apache 2.0. See [LICENSE](LICENSE).
