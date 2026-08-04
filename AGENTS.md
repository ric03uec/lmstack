# AGENTS.md

Conventions for agents working in this repository. Human-facing documentation
lives in `README.md` and (from Phase 5) `website/`.

## What this repo is

An Ansible-driven local LLM stack: GPU hosts run an inference engine behind a
LiteLLM gateway, and a control host runs an editor pointed at that gateway. It
is a genericised port of a running setup (`ric03uec/system`, hosts `inx` and
`ibex`), not a greenfield design. When something looks odd, it is usually
because it was learned the hard way there — check the `notes:` block.

`PLAN.md` is the source of truth for scope, phases, and the test matrix.

## Invariants — do not break these without being asked

1. **Inference engines bind `127.0.0.1` only.** LiteLLM is the sole externally
   reachable service. Postgres publishes no ports at all. T1.3 and T1.4 enforce
   this on the rendered compose file; T3.8 enforces it on a live host.
2. **`.stacklog/` contains no sensitive content.** Every value goes through the
   redaction filter in `skills/lmstack/scripts/stacklog.sh`. Hosts are recorded
   by inventory alias, never by IP or FQDN. Prompt and completion text is never
   recorded at all. `tests/redaction_test.sh` is the guard — extend it when you
   extend the writer.
3. **Alias parity (goal).** A goal enforced by `tests/parity.yml` only for
   hosts listed there, so control-host configuration is engine-agnostic.
   That list is currently empty (h2-amd serves a different model than
   h1-nvidia; see the header comment for why).
4. **8 GB VRAM floor.** The default active set on every host must fit in 8 GiB.
   Larger configurations ship as non-default catalog entries.
5. **The skill never runs git.** It shows a diff, writes on confirmation, and
   leaves staging and committing to the user.
6. **Secrets never enter the repo.** Only `*.example` env files are tracked.
   `stack.env` is created on the host and never overwritten by a re-run.

## Deliberate duplication

Per-host playbooks are self-contained. There are no shared Ansible roles, and
`h1-nvidia` and `h2-amd` repeat structure on purpose — the same choice the
source repo made, so a host can be read top to bottom without chasing includes.

Drift is prevented by the shared validator (`tests/validate_models.py`), not by
abstraction. If you find yourself wanting a role, add a validator check instead.

## Model YAML is the contract

`hosts/<host>/<engine>/models/<slug>.yml` drives the compose file, the LiteLLM
routing table, and the VRAM budget check. Rules the validator enforces:

- `slug` equals the filename stem and is the primary LiteLLM alias
- `engine` is `vllm` or `llamacpp`, and selects which extra fields are required
- ports are unique within a host and rendered as `127.0.0.1:<port>:<internal>`
- `sum(vram_estimate_gib)` over `active_models` fits the host's `vram_budget_gib`
- virtual-model aliases are globally unique per host (LiteLLM silently shadows
  duplicates rather than erroring)

Every model file carries a `notes:` block explaining the quantisation choice,
the sizing arithmetic, and what breaks. That block is the point of the file
being YAML-with-prose rather than a table.

## Before you commit

```bash
make test
```

This runs the validator, the validator's own negative cases, the redaction
test, and the linters. It needs no host and no GPU. All of it must pass.

Linters are optional-by-design: a missing tool SKIPs rather than fails, so the
suite is runnable on a fresh clone. CI installs them, so a SKIP locally is not
a pass in CI.

## Commit and push

Committing directly to `main` is authorised for this repository. One phase per
commit series; conventional-commit subjects; no attribution trailers.
