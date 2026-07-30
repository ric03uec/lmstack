---
sidebar_position: 3
title: Troubleshooting
---

# Troubleshooting

Failure modes in rough order of how often they happen. The `kind` column is what
gets recorded in [`.stacklog`](stacklog), so a past occurrence is greppable.

## Bootstrap

| Symptom | `kind` | Cause and fix |
|---|---|---|
| `sudo: a password is required` | `sudo_required` | Local connections cannot prompt through `make`. Run the playbook directly with `-K`. |
| `nvidia-smi: command not found` | `driver_missing` | The NVIDIA driver is not installed. Bootstrap deliberately does not install it — guessing at a kernel/driver pairing breaks machines. Install it, reboot, re-run. |
| `/dev/dri/renderD128 does not exist` | `render_node_missing` | The amdgpu module did not load. `dmesg \| grep amdgpu`. On a very new APU the running kernel may predate support for the silicon. |
| `vulkaninfo reports no physical device` | `vulkan_no_device` | `mesa-vulkan-drivers` does not match the kernel's amdgpu, or the ICD is missing. Check `ls /usr/share/vulkan/icd.d/`. |
| apt cannot find `docker-ce` | `apt_repo_unsupported` | The Docker apt repo has no suite for this OS version. Non-Debian-family hosts are not supported by bootstrap. |
| `nvidia` absent from `docker info` runtimes after bootstrap | `runtime_not_registered` | `nvidia-ctk runtime configure` ran but Docker was not restarted. Re-run bootstrap; the handler is idempotent. |

## Stack bring-up

| Symptom | `kind` | Cause and fix |
|---|---|---|
| `stack.env has a blank LITELLM_MASTER_KEY` | `secret_unfilled` | Expected on a first run. The playbook dropped the template; fill it and re-run. Not a bug. |
| `Active models need N GiB but the budget is M` | `over_budget` | `active_models` does not fit `vram_budget_gib`. Drop a model, or raise the budget if the card really is larger. |
| `permission denied while trying to connect to the Docker daemon` | `docker_group` | You were added to the `docker` group but have not logged out and back in. Group membership is established at login. |
| Health gate times out on the gateway | `gateway_timeout` | LiteLLM is crash-looping. `docker logs litellm`. Usually a malformed `config.yaml` or an unreachable Postgres. |
| Health gate times out on an engine | `engine_timeout` | Almost always still loading weights on a first run — the gate allows 40 minutes for vLLM. If it genuinely hangs, read the engine's logs. |
| `CUDA out of memory` in an engine log | `oom` | `vram_estimate_gib` is optimistic, or `gpu_memory_utilization` is too high. Lower `max_model_len` first; it is the cheapest lever. |
| GGUF download fails repeatedly | `weights_download` | A gated repo without `HF_TOKEN`, or the CDN dropping a long transfer. The playbook retries three times. |
| `Not connected to DB!` in the LiteLLM UI | `db_password` | `LITELLM_DB_PASSWORD` is blank, or was changed after the volume was created. Changing it needs the volume removed. |

## Verification

| Symptom | `kind` | Cause and fix |
|---|---|---|
| Fewer aliases served than expected | `alias_collision` | Two model files declare the same `virtual_models` name and LiteLLM silently keeps one. `make validate` catches this before deploy. |
| Prose instead of `tool_calls` | `tool_parser` | The big one. Check the parser flag, then raise the quantization — see [the catalog](../models/catalog#choosing-a-quantization). |
| Long prompts fail | `context_overflow` | `max_model_len` / `context` is larger than what the engine actually allocated, usually because it was reduced to fit memory. |
| No 401/403 without a key | `auth_not_enforced` | `master_key` is not reaching LiteLLM. Check `stack.env` is in the container's `env_file` and the value is non-empty. |
| Everything passes but inference is glacial | `cpu_fallback` | The GPU is not being used. On AMD, `docker logs <engine> \| grep -i vulkan` should show `Found 1 Vulkan devices`. On NVIDIA the container is missing the nvidia runtime. |

## Diagnosis commands

Read-only, safe at any point:

```bash
docker compose -f ~/.lmstack/docker-compose.yml ps
docker logs --tail 100 litellm
docker logs --tail 100 <engine-container>
curl -s localhost:4000/health/liveliness
curl -s localhost:8001/health          # llama.cpp
curl -s localhost:8001/v1/models       # vLLM
```

## What not to do

**Do not remove the Postgres volume to fix a startup problem.** It holds the
LiteLLM spend history and any keys created through the UI. Read the logs first.

**Do not edit files in `~/.lmstack/`.** They are rendered from templates and the
next `make up` overwrites them. Edit the template in the repo.

**Do not disable the health gate to get past a timeout.** It is the only thing
standing between you and a stack that looks up but serves nothing.

**Do not fall back to CPU inference.** A 7B model on CPU is slow enough that you
will conclude the whole thing is broken.
