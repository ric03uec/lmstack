# lmstack — Implementation Plan

Status: **approved, not yet implemented**. Living document; folded into the docs
site as `reference/roadmap` once the site exists.

## 1. Goal

Anyone with a GPU box — a DGX Spark, a gaming desktop, or just an AMD laptop —
should get a working OpenAI-compatible local endpoint and a code editor pointed
at it, without reading Ansible.

The stack is extracted and genericised from a running production setup
(`ric03uec/system`, hosts `inx` and `ibex`). It is a port of something proven,
not a greenfield design.

## 2. Non-negotiable constraints

| Constraint | Rationale |
|---|---|
| **8 GB VRAM floor** | The default catalog must come up on a modest card. A stranger's first `make up` succeeding is the whole first impression. |
| **Skill-first UX** | The documented entry point is "install the skill, ask it for a starting point". Raw `ansible-playbook` is the advanced path. |
| **Engines never listen off-localhost** | Only the LiteLLM gateway is reachable. Enforced by tests, not convention. |
| **No secrets in `.stacklog/`** | Enforced by a redaction pass with its own test, not by good intentions. |
| **Self-contained per-host playbooks** | Mirrors the source repo. No shared roles. A shared validator prevents drift. |
| **Alias parity across engines** | `qwen2.5-coder-7b` means the same thing on h1 and h2, so control-host config is engine-agnostic. |

## 3. Explicitly out of scope

- **Switch scripts.** The source repo's `vllm-switch` / `llamacpp-switch` (~740
  lines of bash each) are installed but unused — verified: zero invocations in
  shell history on `inx`, and that host's own docs call both subcommands broken
  and recommend re-running Ansible. Model-set changes go through
  `make up` with an edited `active_models` list. This also removes the
  second-renderer-that-must-match-the-Jinja-template problem.
- **Tailscale management.** Documented, not automated. `tailscale up` plus a
  `litellm_bind_address` override is the entire remote-access story.
- **Grafana / Prometheus deployment.** LiteLLM already exposes `/ui`, `/health`,
  and `/metrics`. We document a scrape config and stop there.

## 4. Repository structure

```
lmstack/
├── README.md                  # skill-first quickstart
├── PLAN.md                    # this file
├── AGENTS.md                  # conventions for agents working in this repo
├── Makefile
│
├── inventory/
│   ├── hosts.ini.example
│   └── hosts.ini              # gitignored; the user's real hosts
│
├── hosts/
│   ├── h1-nvidia/             # NVIDIA GPU → vLLM
│   │   ├── AGENTS.md
│   │   ├── ansible/
│   │   │   ├── vars.yml
│   │   │   ├── 00-bootstrap.yml
│   │   │   ├── 10-stack.yml
│   │   │   ├── 20-verify.yml
│   │   │   └── site.yml
│   │   └── vllm/
│   │       ├── docker-compose.yml.j2
│   │       ├── litellm/config.yaml.j2
│   │       ├── env/stack.env.example
│   │       ├── models/*.yml
│   │       └── chat-templates/*.jinja
│   ├── h2-amd/                # AMD iGPU/dGPU incl. localhost → llama.cpp Vulkan
│   │   ├── AGENTS.md
│   │   ├── ansible/{vars,00-bootstrap,10-stack,20-verify,site}.yml
│   │   └── llamacpp/{docker-compose.yml.j2,litellm/,env/,models/,chat-templates/}
│   └── h3-template/           # copy-me skeleton
│
├── skills/lmstack/            # THE primary interface
│   ├── SKILL.md
│   ├── references/
│   │   ├── hardware-probe.md
│   │   ├── model-catalog.md
│   │   ├── troubleshooting.md
│   │   └── stacklog-schema.md
│   └── scripts/
│       ├── probe-host.sh
│       └── stacklog.sh
│
├── pi-config/                 # control host
│   ├── sync.sh
│   ├── settings.json
│   ├── npm/package.json
│   ├── extensions/{lmstack-h1.ts,lmstack-h2.ts,.env.example}
│   └── bin/lmstack-ask
│
├── website/                   # Docusaurus
│   ├── docusaurus.config.ts
│   ├── sidebars.ts
│   └── docs/…
│
├── tests/
│   ├── lint.sh
│   ├── validate_models.py
│   ├── render_test.sh
│   ├── redaction_test.sh
│   ├── probe_classify_test.sh
│   └── golden/
│
└── .stacklog/
    └── .gitkeep
```

## 5. Model YAML contract

One schema, one `engine:` discriminator, one validator shared by both hosts.

**Common core:**
```yaml
slug: qwen2.5-coder-7b        # must equal filename stem AND be the LiteLLM alias
engine: vllm                   # vllm | llamacpp
image: ...
port: 8001                     # unique per host; bound 127.0.0.1 only
vram_estimate_gib: 6
tier: 8g                       # 8g | 24g | 48g — drives catalog selection
mandatory: false
virtual_models:
  - name: Qwen2.5-Coder-7B-Instruct
    chat_template_kwargs: {}
notes: |
  Why this quant, what breaks, the sizing arithmetic.
```

`engine: vllm` adds `hf_model`, `gpu_memory_utilization`, `max_model_len`,
`max_num_seqs`, `dtype`, `extra_args[]`, optional `chat_template_file`.

`engine: llamacpp` adds `hf_repo`, `hf_file`, `context`, `n_gpu_layers`,
`parallel_slots`, `extra_args[]`.

### Default catalog (tier 8g)

At 8 GB the default active set is **one model**. Two 7Bs do not fit; the docs say
so and the budget check enforces it.

| Host | Model | Form | ctx | ~VRAM |
|---|---|---|---|---|
| h1-nvidia | `Qwen/Qwen2.5-Coder-7B-Instruct-AWQ` | AWQ 4-bit | 16384 | ~6.0 GiB |
| h2-amd | `bartowski/Qwen2.5-Coder-7B-Instruct-GGUF` `Q4_K_M` | GGUF | 16384 | ~6.2 GiB |

Both expose the alias `qwen2.5-coder-7b`, so `pi-config` is identical either way.
Larger tiers (including the 27B FP8 config running on the source repo's DGX) ship
as non-default catalog entries.

## 6. The skill — interactive installer

This is the product surface. Everything else is implementation detail.

**Install:**
```bash
git clone https://github.com/ric03uec/lmstack && cd lmstack
make skill-install     # → ~/.claude/skills/, ~/.config/opencode/skills/, or ~/.agents/skills/
```
`skill-install` templates the absolute repo path into the installed copy, so the
skill can find the playbooks. That path binding is a test case.

**Then:** *"use the lmstack skill to set me a starting point"*

**Flow the skill drives:**

1. **Ask for the target host** — an SSH-able address, or `localhost`.
2. **Probe** — `scripts/probe-host.sh` returns JSON: GPU vendor/model, VRAM,
   driver, OS, kernel, docker present, container runtime, `/dev/dri` nodes.
3. **Classify** — NVIDIA + CUDA → `h1-nvidia`; AMD + render node → `h2-amd`;
   anything else → explain why it's unsupported and stop.
4. **Recommend** a catalog entry matching detected VRAM, and show the arithmetic.
5. **Write config** — `inventory/hosts.ini` and the host's `vars.yml`, shown as a
   diff for confirmation before writing.
6. **Secrets** — walk the user through `stack.env` on the host. The skill never
   reads or echoes the values.
7. **Run** bootstrap → stack → verify, interpreting failures against
   `references/troubleshooting.md`.
8. **Wire the control host** — `pi-config` sync, then confirm with
   `pi --list-models`.
9. **Log every step** to `.stacklog/`.

## 7. `.stacklog/` — change log for later analysis

Append-only JSONL, one file per month: `.stacklog/YYYY-MM.jsonl`.

```json
{
  "ts": "2026-07-29T19:42:11Z",
  "run_id": "01J9X…",
  "host": "h1-nvidia",
  "actor": "skill",
  "event": "apply",
  "action": "bootstrap.docker_install",
  "status": "ok",
  "duration_ms": 41230,
  "hw": {"gpu": "NVIDIA RTX 4070", "vram_gib": 12, "driver": "580.65"},
  "models": ["qwen2.5-coder-7b"],
  "detail": {"packages": ["docker-ce", "nvidia-container-toolkit"]}
}
```

`event` ∈ `probe | plan | apply | verify | decision | error`.

**Redaction — enforced in `scripts/stacklog.sh`, tested in `tests/redaction_test.sh`:**

- Key-name denylist: anything matching `token|key|secret|password|passwd|auth|bearer`.
- Value-pattern denylist: `sk-…`, `hf_…`, PEM blocks, `Authorization:` headers.
- Never logged at all: env-file contents, prompt text, completion text, SSH keys.
- Host identity is the **inventory alias** (`h1-nvidia`), never an IP or hostname.
  A salted hash is available if cross-run correlation is needed.
- Smoke tests log pass/fail and latency only.

The test feeds known secrets through the writer and asserts none appear in output.

## 8. Documentation — Docusaurus

`website/`, Docusaurus 3 + TypeScript config, published to GitHub Pages by Actions
on push to `main`, `baseUrl: '/lmstack/'`.

```
docs/
├── intro.md                       # what this is, the diagram
├── quickstart.md                  # skill-first, 5 minutes
├── skill.md                       # what the skill does, what it asks, what it writes
├── hosts/{h1-nvidia,h2-amd,adding-a-host}.md
├── models/{catalog,adding-a-model,schema}.md
├── control-host/{pi,claude-code,opencode}.md
├── operations/{monitoring,tailscale,troubleshooting,stacklog}.md
└── reference/{make-targets,stacklog-schema,roadmap}.md
```

Per-host `AGENTS.md` stays agent-facing and separate; the site is human-facing.

## 9. Test plan

### T0 — static, no host, runs in CI

| # | Test |
|---|---|
| T0.1 | yamllint + ansible-lint + `--syntax-check` |
| T0.2 | shellcheck on `skills/*/scripts/`, `pi-config/`, `tests/` |
| T0.3 | model schema validation per `engine:` |
| T0.4 | `slug` equals filename stem |
| T0.5 | port uniqueness within a host's active set |
| T0.6 | `sum(vram_estimate_gib) <= host budget` |
| T0.7 | every `chat_template_file` exists |
| T0.8 | virtual-model alias uniqueness (LiteLLM silently shadows dupes) |
| T0.9 | every slug in `active_models` has a YAML |
| T0.10 | pi extension model IDs ⊆ YAML aliases; `contextWindow` matches |
| T0.11 | **alias parity**: h1 and h2 tier-8g defaults expose the same alias |
| T0.12 | **stacklog redaction**: known secrets in → absent from output |
| T0.13 | tier-8g default active set fits in 8 GiB |

### T1 — render, no GPU

| # | Test |
|---|---|
| T1.1 | rendered compose passes `docker compose config -q` |
| T1.2 | golden-file diff for the fixture model set |
| T1.3 | every engine port string starts `127.0.0.1:` |
| T1.4 | postgres publishes no ports |
| T1.5 | rendered LiteLLM config is valid YAML with the expected alias count (guards the Jinja whitespace regression the source repo hit) |

### T2 — bootstrap, host required, no GPU

| # | Test |
|---|---|
| T2.1 | `00-bootstrap.yml` twice → second run `changed=0` |
| T2.2 | h1: `docker info` lists the `nvidia` runtime |
| T2.3 | h2: `/dev/dri/renderD128` exists; render GID detected |
| T2.4 | invoking user runs `docker ps` without sudo |

### T3 — bring-up, GPU required

| # | Test | Guards |
|---|---|---|
| T3.1 | `site.yml` completes, health gates pass | baseline |
| T3.2 | `/v1/models` returns exactly the expected aliases | shadowing |
| T3.3 | non-empty completion per alias | baseline |
| T3.4 | request with `tools:` returns `tool_calls`, not prose | the #1 real-world failure in the source repo |
| T3.5 | streaming SSE yields deltas and `[DONE]` | agents stream |
| T3.6 | prompt at ~90% of `max_model_len` does not 400 | context misconfig |
| T3.7 | missing/wrong bearer → 401 | auth is actually on |
| T3.8 | from a second machine: `:4000` reachable, `:80xx` refused | exposure invariant, live |
| T3.9 | `docker compose restart` → self-heals | `restart: unless-stopped` |
| T3.10 | reboot → stack returns with no Ansible | persistence claim |

### T4 — control host

| # | Test |
|---|---|
| T4.1 | `sync.sh install` on a clean `~/.pi/agent` leaves extensions present (the source repo's sync script does not copy them) |
| T4.2 | `pi --list-models` shows the registered providers |
| T4.3 | `pi -p --provider lmstack-h1 …` returns a completion |
| T4.4 | a reasoning model works (confirms `drop_params: true` absorbs `reasoning_effort`) |
| T4.5 | `bin/lmstack-ask` invoked from Claude Code returns output |
| T4.6 | `sync.sh dump` → `install` round-trips clean |

### T5 — negative / guardrail

| # | Test | Expected |
|---|---|---|
| T5.1 | blank `HF_TOKEN` | fails before any download, message says what to do |
| T5.2 | blank `LITELLM_MASTER_KEY` / `_DB_PASSWORD` | fails with a generator command in the message |
| T5.3 | unknown slug in `active_models` | assert fails, **zero containers touched** |
| T5.4 | duplicate ports | caught at T0.5, never reaches a host |
| T5.5 | over-budget VRAM | refuses, shows the arithmetic |
| T5.6 | re-run over an existing `stack.env` with real secrets | not overwritten |
| T5.7 | engine unreachable from LiteLLM | health gate names the engine, not a bare timeout |

### T6 — skill

| # | Test |
|---|---|
| T6.1 | fixture probe JSON → correct host classification (nvidia / amd / unsupported) |
| T6.2 | 6 GB probe → recommends tier-8g single model, not a pair |
| T6.3 | `make skill-install` binds the correct absolute repo path |
| T6.4 | every skill step emits exactly one `.stacklog` line, schema-valid |
| T6.5 | skill run on a host that fails bootstrap logs `event=error` with a `kind`, and stops |

## 10. Execution phases

Committed directly to `main`, one phase per commit series.

| Phase | Content | Gate |
|---|---|---|
| **0** | Scaffold, Makefile, inventory, model contract, `.stacklog` writer + redaction, `tests/` T0+T1 | T0, T1 green on fixtures |
| **1** | `h1-nvidia` bootstrap + stack + verify + tier-8g catalog | T2, T3, T5 on an NVIDIA host |
| **2** | `h2-amd` (localhost / Vulkan) | T2, T3, T5 on ibex |
| **3** | `skills/lmstack` interactive installer | T6 |
| **4** | `pi-config` + `bin/lmstack-ask` + Claude Code / opencode bridges | T4 |
| **5** | Docusaurus site + GitHub Pages workflow | site builds, links resolve |
| **6** | `h3-template`, CI running T0+T1 on PRs | CI green |

Phase 0 builds the validator *before* the playbooks, so h1 and h2 are written
against an already-enforced schema. That is what keeps two intentionally
duplicated playbooks from silently diverging.

## 11. Prerequisites for development

```bash
uv tool install ansible-lint
uv tool install yamllint
sudo apt install shellcheck        # not a Python package
```

`.gitignore` currently covers Python only; Phase 0 adds `node_modules/`,
`.docusaurus/`, `website/build/`, `inventory/hosts.ini`, and `**/env/stack.env`.
Note the existing `lib/` rule is a Python artifact rule and must not be allowed
to swallow anything under `website/`.

## 12. Open items

- Whether `.stacklog/` should be committed (shared history, needs the redaction
  guarantee to be airtight) or gitignored (local-only analysis). Currently
  planned as **committed**, since "a log of changes over time for later analysis"
  implies durability across clones.
- Whether the skill should offer to `git commit` the config it writes.
