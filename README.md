# lmstack

A local LLM stack you can actually develop against: a GPU host serving models
behind one OpenAI-compatible endpoint, and a code editor already pointed at it.

Bring a DGX Spark, a gaming desktop, or the AMD laptop you already own. The
default catalog is sized to come up on **8 GB of VRAM**.

```
        control host                          GPU host
  ┌──────────────────────┐            ┌──────────────────────────┐
  │ pi / Claude Code /   │            │  LiteLLM  :4000          │
  │ opencode             │ ─────────► │    ├─ engine    :8001 *  │
  │ pi-config/           │  OpenAI    │    └─ engine    :8002 *  │
  └──────────────────────┘   API      │  * = 127.0.0.1 only      │
                                      └──────────────────────────┘
```

Only the gateway is reachable off-box. The engines bind loopback, and a test
enforces it rather than a comment promising it.

## Quickstart

```bash
git clone https://github.com/ric03uec/lmstack && cd lmstack
make skill-install       # installs the lmstack skill for your agent
```

Then ask your agent:

> use the lmstack skill to give me a starting point

The skill asks which host to target, probes its hardware, picks a model that
fits the VRAM it found, shows you every file it wants to write, and runs the
playbooks. It is the supported path. `make up HOST=...` is the same thing
without the conversation.

Both are still being built — see [Status](#status). `make test` works today.

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
- [ ] Phase 2 — `h2-amd` playbooks
- [ ] Phase 3 — the skill
- [ ] Phase 4 — `pi-config` and agent bridges
- [ ] Phase 5 — documentation site
- [ ] Phase 6 — host template and CI

## License

Apache 2.0. See [LICENSE](LICENSE).
