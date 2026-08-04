# lmstack — put your GPU to use

Your GPU is idle right now. lmstack turns it into a coding endpoint your editor
talks to like any other provider — no cloud tokens, no rate limits, no data
leaving the box.

Bring a DGX Spark, a gaming desktop, or the AMD laptop you already own. The
default catalog comes up on **8 GB of VRAM**. If you have more, the skill
notices and offers you more.

## Quickstart

You need four things on the control host — the machine you write code on:

- **pi** — `curl -fsSL https://pi.dev/install.sh | sh`
- **Ansible** — `uv tool install ansible-core`
- **tmux** — your package manager (`apt install tmux`, `brew install tmux`, etc.)
- **A GPU host** — this machine, or one you can SSH to

Then, inside pi (or Claude Code, or opencode), paste this:

> install the lmstack skill from https://ric03uec.github.io/lmstack/install

That URL is written for your agent to read, not for you. It tells it what to
fetch and where to put it. Then:

> use the lmstack skill to give me a starting point

The skill probes the target's hardware, picks a model that fits, shows you
every file it wants to write, hands you any sudo commands it needs, and runs
the playbooks. **Nothing to clone first** — it does that itself, once you say
where.

Point it at a remote box by giving it an SSH target instead of `localhost`.
Working on lmstack rather than using it? Clone it and run `make skill-install`,
which points the skill at your clone instead of fetching its own copy.

## What actually gets built

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
is a second engine container on `:8002`.

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
