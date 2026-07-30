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
| 6 | `h3-template` and CI running the offline suite on PRs | CI green | next |

Phase 0 built the validator *before* the playbooks, so `h1-nvidia` and
`h2-amd` were written against an already-enforced schema. That ordering is what
keeps two intentionally duplicated playbook trees from silently diverging —
there are no shared Ansible roles here, on purpose, and the validator plus the
golden render files are what hold the line instead.

## What Phase 6 changes for you

Today, [adding a host](../hosts/adding-a-host) means copying `hosts/h2-amd` and
editing it. That works, and the validator catches most of what you can get
wrong, but you inherit AMD-specific decisions you then have to notice and
remove.

`hosts/h3-template/` will be a host that is deliberately incomplete: the
directory structure, the three playbooks, and the model schema, with the
engine-specific parts marked rather than filled in. The validator will skip it
by name so an unfilled template does not fail `make test`.

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
| T6 | Skill: probe classification, install path binding, logging discipline | T6.1–T6.3 offline |

`make test` is T0, T1, T4.1, T4.6, and T6.1–T6.3 — everything that can be proven
without hardware. The rest are a manual checklist in `PLAN.md`, because a test
that needs a GPU and forty minutes is not a test anyone runs.
