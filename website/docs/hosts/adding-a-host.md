---
sidebar_position: 3
title: Adding a host
---

# Adding a host

Two different things get called this. Decide which one you are doing.

## Adding a machine to an existing role

If your new box is NVIDIA or AMD, it is an instance of a role that already
exists, not a new role. Add it to `inventory/hosts.ini` under the right group
and run the playbooks against it:

```ini
[h2-amd]
laptop    ansible_connection=local
workshop  ansible_host=192.168.1.42  ansible_user=me
```

The per-host `vars.yml` is shared by everything in the group, so two machines
with different GPU budgets need either the same model set or an inventory-level
override of `active_models` and `vram_budget_gib`.

## Adding a new role

A new role means a new *engine* — Intel Arc via SYCL, Apple Metal, something
else. That is a real port, not a copy. What follows is the shape of it.

### 1. Copy the closest existing host

`h2-amd` is the better starting point for anything that is not CUDA: it already
deals with device nodes, group IDs, and an engine that is not vLLM.

```bash
cp -r hosts/h2-amd hosts/h3-intel
```

### 2. Deliberately do not factor out the common parts

Every host directory is self-contained, with no shared Ansible roles. That is a
choice, and it is the opposite of what an Ansible tutorial will tell you.

The reasoning: the three hosts differ in the parts a role would want to
abstract — device access, runtime registration, health semantics — and agree on
the parts that do not need one. A shared role would grow a `when: engine ==`
ladder inside a week, and a change made for one host would silently alter
another.

Drift is prevented instead by a validator and golden-file rendering that both
apply to every host equally. Duplication you can read beats an abstraction you
have to hold in your head.

### 3. Teach `classify.py` about the vendor

```python
ROLES = {
    "nvidia": {"host": "h1-nvidia", "engine": "vllm"},
    "amd":    {"host": "h2-amd",    "engine": "llamacpp"},
}
```

The probe must be able to detect the vendor, and `classify.py` must map it to a
role. Until then, a machine with that GPU gets an "unsupported vendor" verdict
naming the file to change — which is the correct behaviour, not a bug.

### 4. Keep the invariants

These are asserted by tests, so breaking one fails the build rather than
producing a subtly wrong host:

- Engines publish on `127.0.0.1` only. Only LiteLLM is externally reachable.
- Postgres publishes no ports at all.
- LiteLLM reaches the engines over the compose network, by container name.
- The host serves `qwen2.5-coder-7b` — or whatever `required_common_aliases`
  lists — so control-host configuration does not change per host.
- Health gating waits on an endpoint that is only ready when the weights are
  loaded, not one that answers during startup.

### 5. Add a golden render

```bash
BLESS=1 tests/render_test.sh
```

Read the blessed output before committing it. `BLESS=1` records whatever the
templates currently produce, including a mistake.

### 6. Model YAMLs are per engine

`hosts/<host>/<engine>/models/*.yml`. The schema differs by engine — vLLM takes
`hf_model` and `max_model_len`, llama.cpp takes `hf_repo`, `hf_file`, and
`context` — and `validate_models.py` enforces the right one per `engine:` field.
See [the model schema](../models/schema).
