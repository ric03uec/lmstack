---
sidebar_position: 1
title: Make targets
---

# Make targets

`make help` prints this list from the Makefile itself, so it cannot drift. This
page adds the part a one-line description cannot carry: when you would reach for
each one, and what it will not do for you.

Host targets need `HOST=`:

```bash
make up HOST=h1-nvidia
```

Omitting it prints the available hosts rather than guessing.

## Tests

None of these need a host, a GPU, or a network.

| Target | What it proves |
|---|---|
| `make test` | Everything below, in order. This is what CI runs. |
| `make validate` | Every model YAML matches the schema, aliases do not collide, active models fit the VRAM budget, and each pi extension advertises only aliases a host actually serves. |
| `make validator-test` | The validator *rejects* known-bad configuration. Without this, a validator that returned success unconditionally would look healthy. |
| `make redaction-test` | Real secret shapes fed through the `.stacklog` writer do not survive. |
| `make render-test` | Every host's templates render, and the rendered compose file still binds engines to `127.0.0.1`. |
| `make template-test` | `hosts/*-template` still instantiates into a host the validator accepts, and has not drifted from the host it was cut from. |
| `make classify-test` | Every hardware probe fixture produces the expected verdict. |
| `make skill-install-test` | The skill install binds an absolute repo path. |
| `make pi-config-test` | The pi sync copies extensions, merges rather than overwrites, and round-trips. |
| `make lint` | yamllint, shellcheck, ansible-lint at the production profile, playbook syntax, and a scan for secrets committed by accident. |

Run `make test` before you push. It takes seconds and catches the class of
mistake that otherwise surfaces forty minutes into a bring-up.

## Skill

| Target | Notes |
|---|---|
| `make skill-install` | Installs into every agent directory found. `AGENT=claude\|opencode\|pi` restricts it to one. |
| `make skill-list` | Shows where the install *would* write, without writing. Run this first if you are unsure what directories exist. |

The install writes this clone's absolute path into the skill. Moving or renaming
the directory means re-running it.

## Control host

| Target | Notes |
|---|---|
| `make pi-install` | Merges the lmstack providers into `~/.pi/agent`, preserving packages and settings you already have. |
| `make pi-dump` | Captures changes you made in `~/.pi/agent` back into `pi-config/`, restricted to the entries lmstack owns. |

`pi-dump` will not pull your private packages into the repo. It only looks at
the three entries lmstack installed.

## Host lifecycle

| Target | Notes |
|---|---|
| `make deps` | Installs the Ansible collections the playbooks need. Once per control host. |
| `make bootstrap HOST=` | Docker, GPU runtime, firewall. Does **not** install the NVIDIA driver — guessing at a kernel/driver pairing breaks machines. |
| `make up HOST=` | Renders templates, pulls images, starts the stack, and waits on the health gate. Runs `validate` first. |
| `make verify HOST=` | Endpoint conformance: the aliases are served, auth is enforced, and tool calls come back as `tool_calls` rather than prose. |
| `make site HOST=` | `bootstrap` + `up` + `verify` in one run. |
| `make check HOST=` | Dry-runs the whole thing with `--check --diff`. Safe on a live host. |

`up` restarts LiteLLM when the rendered config changes, because a bind-mounted
`config.yaml` does not change the service definition and compose would otherwise
leave the container alone with a stale routing table.

The health gate allows 40 minutes for vLLM on a first run — that is weight
download and load, not a hang. Do not disable it to get past a timeout; it is
the only thing standing between you and a stack that looks up but serves
nothing.

## Observability

| Target | Notes |
|---|---|
| `make stacklog` | Pretty-prints the local change log. See [`.stacklog`](../operations/stacklog). |

## Documentation

| Target | Notes |
|---|---|
| `make docs` | Runs the Docusaurus dev server on `localhost:3000` with hot reload. |
| `make docs-build` | Builds the static site and fails on any broken internal link. |

`docs-build` is what the Pages workflow runs. `onBrokenLinks` is set to `throw`,
so a renamed page that something still points at fails the build rather than
shipping a 404.
