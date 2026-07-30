---
sidebar_position: 1
title: Monitoring
---

# Monitoring

LiteLLM is the gateway and it is also the observability. There is no Prometheus
stack, no Grafana, and no exporter to keep running — one box serving a couple of
models does not need one, and the maintenance cost is real.

## The UI

```
http://<host>:4000/ui
```

Log in with `LITELLM_MASTER_KEY`. It shows request logs, latency, token counts,
and spend per key — spend being zero here, but the request accounting is the
useful part.

This is backed by the Postgres container, which is why it exists. Without it the
gateway still routes, but you lose the history.

## Health

```bash
curl -s http://<host>:4000/health/liveliness      # gateway process
curl -s http://<host>:4000/v1/models              # what it will route
```

`/v1/models` is the honest answer to "what is actually being served" — it
reflects the routing table LiteLLM loaded, not what the config file says. If a
model you added is missing from it, LiteLLM did not reload; see below.

Per engine, on the host:

```bash
curl -s localhost:8001/health        # llama.cpp — only 200 once weights load
curl -s localhost:8001/v1/models     # vLLM
```

llama.cpp's `/v1/models` answers while the model is still loading, which is why
the playbook gates on `/health` instead. Use the same distinction when checking
by hand.

## LiteLLM caches its routing table at startup

`config.yaml` is bind-mounted, so changing it does not change the service
definition, and `docker compose up` will not recycle the container. `make up`
restarts LiteLLM when the rendered config changes. If you edited the file on the
host directly — which you should not — restart it yourself:

```bash
docker restart litellm
```

A model that is deployed but missing from `/v1/models` is nearly always this.

## Prompts are not logged

`litellm_store_prompts` is `false` in both hosts' `vars.yml`, so the spend logs
record metadata and token counts but not content. Turning it on means your
prompts and completions land in a Postgres volume on the GPU host. That may be
what you want for evaluation work; know that you are choosing it.

## Container state

```bash
docker compose -f ~/.lmstack/docker-compose.yml ps
docker stats --no-stream
```

Everything runs with `restart: unless-stopped`, so the stack survives a reboot
without a systemd unit. A container in a restart loop shows up in `ps` as
repeatedly young — check its logs rather than restarting it again.

## GPU utilisation

```bash
nvidia-smi                                  # NVIDIA
watch -n1 'cat /sys/class/drm/card*/device/mem_info_vram_used'   # AMD
radeontop                                   # AMD, if installed
```

On AMD, confirm the engine is on the GPU at all rather than silently on the CPU:

```bash
docker logs <engine> 2>&1 | grep -i 'ggml_vulkan'
```

## What to watch

For a development stack, three things:

- **Context pressure.** A 16k window fills faster than expected in an agent
  loop. The pi status line shows it live.
- **Engine restarts.** A container that keeps coming back is usually out of
  memory, not a transient fault.
- **Latency drift after adding a model.** Two models sharing a card means two
  sets of weights and two KV caches. `make validate` checks the weights fit; it
  does not check that you will like the throughput.
