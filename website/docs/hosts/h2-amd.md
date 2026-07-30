---
sidebar_position: 2
title: h2-amd
---

# h2-amd

An AMD GPU host — discrete card, integrated GPU, or APU. Usually this is the
laptop you are already working on. llama.cpp with the Vulkan backend serves the
models; LiteLLM fronts them, exactly as on [h1-nvidia](h1-nvidia).

```
                    :4000  LiteLLM  <- the only externally reachable port
                              |
                  compose network (http://llama-<slug>:8080)
                              |
              127.0.0.1:8001  llama-qwen2.5-coder-7b
                              |
                        postgres (no published ports)
```

Container and volume names are identical to h1-nvidia's. That is deliberate: the
same restart task, the same verify playbook, and the same debugging commands
work on both.

## Running it

```bash
make deps
make bootstrap HOST=h2-amd
make up        HOST=h2-amd
make verify    HOST=h2-amd
```

On a local connection sudo usually needs a password, and `make` cannot supply
one. Run bootstrap directly:

```bash
ansible-playbook -i inventory/hosts.ini hosts/h2-amd/ansible/00-bootstrap.yml -K
```

## Why Vulkan and not ROCm

ROCm supports a narrow list of discrete AMD cards. The Vulkan backend works on
iGPUs, APUs, and consumer dGPUs alike. For a repo whose promise is "works on the
AMD machine you already have", portability beats peak throughput.

## Unified memory: read GTT, not VRAM

An APU reports a token VRAM carve-out — often 512 MiB or 2 GiB — and maps the
rest of the budget through GTT. Reading the VRAM figure alone declares most AMD
laptops unable to run a 7B model, which is wrong by an order of magnitude.

```bash
cat /sys/class/drm/card*/device/mem_info_vram_total   # the carve-out
cat /sys/class/drm/card*/device/mem_info_gtt_total    # the real budget
```

`classify.py` takes the larger of the two and says which it used. Set
`vram_budget_gib` in `ansible/vars.yml` from its `usable_gib` output, not from
the BIOS figure.

## The render node

Containers reach the GPU through a DRM render node, set as `render_node` in
`ansible/vars.yml`:

```yaml
render_node: /dev/dri/renderD128
```

`renderD128` is the first GPU. A machine with both an iGPU and a discrete card
also has `renderD129`, and which is which is not guaranteed across boots on some
kernels. Resolve it before assuming:

```bash
ls -l /dev/dri/by-path
```

Access also needs the container to be in the host's `render` group. Docker sets
container groups itself rather than inheriting them, so the compose file passes
the numeric GID — the playbook reads it from the host with `getent` rather than
hardcoding a number that differs between distributions.

## Quantization and tool calling interact

The deployment this was ported from found Q4_K_M improvising tool-call wrappers
— `<xml>` tags, ` ```json ` fences — that llama.cpp's chat parser does not
recognise, dumping the call into `message.content` instead of `tool_calls`.
Q6_K restored adherence.

So if T3.4 fails, the diagnosis order is:

1. Is `--jinja` in the model's `extra_args`? Without it llama.cpp does not use
   the GGUF's embedded chat template, which is what carries the ChatML
   `<tools>`/`<tool_call>` plumbing.
2. Raise the quantization: Q4_K_M → Q6_K.
3. Only then look at the template.

## Things that will bite you

**Silent CPU fallback.** If Vulkan cannot see the device, llama.cpp runs on the
CPU and answers correctly, just very slowly. Nothing errors. Check:

```bash
docker logs llama-qwen2.5-coder-7b 2>&1 | grep -i vulkan
# want: ggml_vulkan: Found 1 Vulkan devices
```

**`server-vulkan` is a moving tag.** Pin it once the host works.

**Health is `/health`, not `/v1/models`.** llama-server answers `/v1/models`
while the model is still loading, so gating on it races the weights. The
playbook waits on `/health`.

**LiteLLM caches its routing table at startup.** Same as on h1-nvidia: the
playbook restarts it when the rendered config changes.
