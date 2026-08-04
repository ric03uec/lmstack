---
sidebar_position: 3
title: Roadmap
---

# Roadmap

Implementation is phased, one commit series per phase, each with a gate that has
to be green before the next one starts. `PLAN.md` in the repository holds the
full design and the test matrix the gates refer to.

| Phase | Content | Gate | |
|---|---|---|---|
| 0 | Model contract, validator, `.stacklog` writer + redaction, offline tests | T0, T1 green on fixtures | done |
| 1 | `h1-nvidia` bootstrap, stack, verify, 8 GB catalog | T2, T3, T5 on an NVIDIA host | done |
| 2 | `h2-amd` — localhost, Vulkan | T2, T3, T5 on an AMD host | done |
| 3 | `skills/lmstack` interactive installer | T6 | done |
| 4 | `pi-config`, `lmstack-ask`, Claude Code and opencode bridges | T4 | done |
| 5 | This site, and the Pages workflow that publishes it | site builds, links resolve | done |
| 6 | `h3-template` and CI running the offline suite on PRs | CI green | done |

All six phases are in. What follows is maintenance and whatever the next piece
of hardware demands.

Phase 0 built the validator *before* the playbooks, so `h1-nvidia` and
`h2-amd` were written against an already-enforced schema. That ordering is what
keeps two intentionally duplicated playbook trees from silently diverging —
there are no shared Ansible roles here, on purpose, and the validator plus the
golden render files are what hold the line instead.

## The template

`hosts/h3-template/` is a host that is deliberately incomplete: the directory
layout, the four playbooks, and the engine templates, with three `CHANGE_ME_`
placeholders and an empty `active_models`. `make validate` and the render suite
skip any directory under `hosts/` whose name ends in `-template`, so an unfilled
skeleton never fails `make test`.

That exemption is also how a template rots, so `tests/template_test.sh` copies
it into a scratch directory on every run, fills the placeholders, and validates
the result. It also asserts the template's `.j2` files match `h1-nvidia`'s apart
from comments — improving the real host's compose template without carrying the
change across turns the suite red. See
[adding a host](../hosts/adding-a-host).

## What is deliberately not planned

**A shared Ansible role library.** Two hosts is not enough duplication to
justify the indirection, and the failure mode of a shared role — a change made
for NVIDIA quietly altering the AMD path — is worse than the duplication. If a
fourth engine arrives this gets revisited.

**Prometheus and Grafana.** LiteLLM's UI is backed by Postgres and already
carries request logs, latency, and token counts. One box serving a couple of
models does not need an exporter to keep running. See
[monitoring](../operations/monitoring).

**Multi-user auth.** The gateway has one master key, and per-user keys created
through the LiteLLM UI. Anything beyond that is an identity system, and this
repo is not going to grow one. Put the host on a private network instead —
[remote access](../operations/tailscale).

**Automatic model downloads on a schedule.** Weights are large and CDNs drop
long transfers. Downloads happen when you add a model and ask for it, where you
are watching.

## Test tiers

The gates above refer to these. Only T0 and T1 run without hardware.

| Tier | Scope | Needs |
|---|---|---|
| T0 | Static: schema, lint, redaction, alias parity, editor/server consistency | nothing |
| T1 | Template rendering and the loopback-binding invariant | nothing |
| T2 | Bootstrap: Docker, GPU runtime, firewall | a host |
| T3 | Bring-up: health gates, aliases served | a host with a GPU |
| T4 | Control host: pi providers, sync, bridges | T4.1 and T4.6 offline; the rest need a running host |
| T5 | Negative: over-budget, missing secret, unauthenticated request | a host |
| T6 | Skill: probe classification, install path binding, logging discipline | T6.1–T6.2 offline |
| T7 | Template: layout parity, no drift from the reference host, instantiation | nothing |
| T8 | Plugin and marketplace manifests, skill name uniqueness, no build-time path placeholder | nothing |
| T9 | Sanitizer strips invisible and bidi codepoints, task store invariants | nothing |
| T10 | Forge drives tmux, ledger never fabricates a duration | nothing |
| T11 | Cleanup reclaims finished worktrees and branches, refuses to touch unmerged work or main | nothing |

`make test` is T0, T1, T4.1, T4.6, T6.1, T6.2, T7, T8, T9, T10, T11 — everything
that can be proven without hardware, and what CI runs on every pull request. The
rest are a manual checklist in `PLAN.md`, because a test that needs a GPU and
forty minutes is not a test anyone runs.
