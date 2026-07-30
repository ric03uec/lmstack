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

Paste this at your coding agent — Claude Code, opencode, or pi:

> install the lmstack skill from https://ric03uec.github.io/lmstack/install

That page is written for the agent to read: it says where the skill goes and how
to fetch it. Then ask for a starting point:

> use the lmstack skill to give me a starting point

The skill asks which host to target, probes its hardware, picks a model that
fits the VRAM it found, shows you every file it wants to write, and runs the
playbooks. **You do not need to clone this repository first** — it does that
itself, after asking where to put it.

### Install the skill yourself

One command, no clone. Pick the directory your agent reads from:

```bash
DEST=~/.claude/skills   # opencode: ~/.config/opencode/skills · pi: ~/.agents/skills
mkdir -p "$DEST"
curl -fsSL https://github.com/ric03uec/lmstack/archive/refs/heads/main.tar.gz \
  | tar -xz -C "$DEST" --strip-components=2 lmstack-main/skills/lmstack
```

### Work from a clone instead

If you want to change lmstack rather than use it:

```bash
git clone https://github.com/ric03uec/lmstack && cd lmstack
make skill-install                 # every agent directory you have
make skill-install AGENT=claude    # or just one: claude | opencode | pi
```

This binds the clone's absolute path into the installed skill, so it works
against your edits rather than cloning a second copy. Moving or renaming the
clone means re-running it. `make up HOST=...` is the same work as the skill,
without the conversation.

Once a host is up, point your editor at it:

```bash
make pi-install          # merges into ~/.pi/agent, keeping what is already there
```

See [pi-config/README.md](pi-config/README.md) for the Claude Code and opencode
bridges.

## What runs where

| Host role | Hardware | Engine | Why |
|---|---|---|---|
| `h1-nvidia` | NVIDIA + CUDA | vLLM | Throughput and mature tool-call parsing. |
| `h2-amd` | AMD iGPU / APU / dGPU, including localhost | llama.cpp (Vulkan) | Vulkan works on the AMD hardware you already have; ROCm supports a narrow list of cards. |

Both expose the alias `qwen2.5-coder-7b`. Your editor configuration does not
change when you move between them — enforced by `tests/parity.yml`.

## Repository layout

```
hosts/<host>/           self-contained Ansible + engine templates + model YAML
hosts/h3-template/      skeleton to copy for a third box; filled in by a test
inventory/              hosts.ini.example -> your gitignored hosts.ini
skills/lmstack/         the interactive installer skill
pi-config/              control-host editor configuration
tests/                  offline validation; no GPU required
.stacklog/              local-only JSONL log of every change made to your hosts
```

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

## Status

Implementation is phased. [PLAN.md](PLAN.md) holds the full design and test
matrix.

- [x] Phase 0 — model contract, validator, `.stacklog` writer, offline tests
- [x] Phase 1 — `h1-nvidia` playbooks
- [x] Phase 2 — `h2-amd` playbooks
- [x] Phase 3 — the skill
- [x] Phase 4 — `pi-config` and agent bridges
- [x] Phase 5 — documentation site
- [x] Phase 6 — host template and CI

## License

Apache 2.0. See [LICENSE](LICENSE).
