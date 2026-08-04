# lmstack — put your GPU to use

Your GPU is idle right now. lmstack turns it into a coding endpoint your editor
talks to like any other provider — no cloud tokens, no rate limits, no data
leaving the box.

Bring a DGX Spark, a gaming desktop, or the AMD laptop you already own. The
default catalog comes up on **8 GB of VRAM**. If you have more, the skill
notices and offers you more.

## Quickstart

You need four things on the control host — the machine you write code on:

- **Claude Code** — lmstack ships as a plugin, and that is the only supported
  way to install it
- **Ansible** — `uv tool install ansible-core`
- **tmux** — your package manager (`apt install tmux`, `brew install tmux`, etc.)
- **A GPU host** — this machine, or one you can SSH to

Inside Claude Code:

```
/plugin marketplace add ric03uec/lmstack
/plugin install lmstack@lmstack
```

That gives you four commands:

| Command | What it does |
|---|---|
| `/lmstack:analyze [target]` | Probes the hardware — locally or over SSH — and says what fits |
| `/lmstack:install [target]` | Brings the stack up. Every generated file lands in `~/.lmstack/`, never in a repo |
| `/lmstack:harvest <source>` | Reads a backlog and works out which items the local stack can attempt |
| `/lmstack:exec <key>` | Runs one of them and ends with a pull request for you to review |

Start with `/lmstack:analyze`. It reads the GPU, does the VRAM arithmetic, and
tells you which models fit before anything is installed. Pass an SSH target
instead of nothing to point it at a remote box.

`/lmstack:install` then shows you every file it wants to write and hands you any
sudo commands to run yourself — it never runs them for you.

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
