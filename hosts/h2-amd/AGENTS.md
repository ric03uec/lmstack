# h2-amd

AMD GPU host. llama.cpp over Vulkan serves the models; LiteLLM fronts them.
Works on an iGPU, an APU, or a discrete Radeon — including the machine you are
sitting at, which is what `ansible_connection=local` in the inventory means.

```
                    :4000  LiteLLM  <- the only externally reachable port
                              |
                  compose network (http://llama-<slug>:8080)
                              |
              127.0.0.1:8001  llama-qwen2.5-coder-7b
                              |
                        postgres (no published ports)
```

## Running it

```bash
make deps                    # once: ansible collections, on your machine
make bootstrap HOST=h2-amd   # once: docker, vulkan, firewall  (needs -K, see below)
make up        HOST=h2-amd   # download GGUFs, render, start, health-gate
make verify    HOST=h2-amd   # endpoint conformance
```

`make site HOST=h2-amd` runs all three. Everything is re-runnable.

Bootstrap installs packages, so on a local connection sudo wants a password
that `make` cannot supply:

```bash
ansible-playbook -i inventory/hosts.ini hosts/h2-amd/ansible/00-bootstrap.yml -K
```

`up` and `verify` need no privileges at all.

## Assumptions

- The **amdgpu kernel driver** is already loaded, i.e. `/dev/dri/renderD128`
  exists. Bootstrap checks for it and stops rather than guessing at your kernel.
- Vulkan rather than ROCm. ROCm supports a narrow list of discrete cards; the
  Vulkan backend runs on iGPUs, APUs and consumer dGPUs alike. Peak throughput
  on a supported card would be higher; portability is the trade we made.
- The install root is `~/.lmstack` on the target. Nothing lands in `/etc` or
  `/var/lib`, and there is no systemd unit — containers come back after a reboot
  because of `restart: unless-stopped`. An existing ollama or LM Studio is never
  touched.
- Root is used for exactly two things: installing packages during bootstrap, and
  the one UFW rule.

## Files

| Path | What it is |
|---|---|
| `ansible/vars.yml` | The knobs. `active_models`, `vram_budget_gib` and `render_node`. |
| `ansible/00-bootstrap.yml` | Docker, the Vulkan stack, firewall, `vulkaninfo` gate. |
| `ansible/10-stack.yml` | Validate, detect the render GID, download GGUFs, render, start, wait. |
| `ansible/20-verify.yml` | T3.2–T3.7 against the live endpoint. |
| `llamacpp/models/*.yml` | One file per model. The contract is in the repo-root `AGENTS.md`. |
| `llamacpp/docker-compose.yml.j2` | Rendered to the install root. Never edit the rendered copy. |
| `llamacpp/litellm/config.yaml.j2` | The routing table. |
| `llamacpp/env/stack.env.example` | Copied to the host once and never overwritten. |

## Changing which models run

Edit `active_models` in `ansible/vars.yml`, then `make up HOST=h2-amd`. There is
no switch script; re-running the playbook is the switch. `make validate` refuses
an over-budget set before Ansible connects to anything.

Weights land in `~/.lmstack/models-gguf/` and are never deleted, so switching
back to a model you have already run costs nothing.

## Things that will bite you

**A silent fall back to CPU.** If Vulkan cannot see the GPU the server still
starts and still answers — at a few tokens a second. Bootstrap asserts on
`vulkaninfo --summary` for this reason. To confirm after the fact:

```bash
docker logs llama-qwen2.5-coder-7b 2>&1 | grep -i vulkan
```

You want a `ggml_vulkan: Found 1 Vulkan devices` line naming your GPU. `using
CPU backend` means the ICD did not load inside the container.

**Tool calls arriving as prose.** `--jinja` makes llama.cpp use the GGUF's
embedded chat template, which for Qwen2.5 carries the full `<tool_call>`
plumbing. If `20-verify.yml` T3.4 still fails, the cause is usually the
quantization rather than the template: Q4_K_M has been observed inventing
wrappers the parser does not recognise, and Q6_K restored adherence. Raise the
quant before editing templates.

**Sizing on unified memory.** On an APU there is no dedicated VRAM pool — the
GPU allocates from system RAM through GTT, and the real ceiling is usually well
above whatever the BIOS reports as "VRAM". `vram_budget_gib: 8` is the
conservative default, not a hardware limit. Check what you actually have:

```bash
cat /sys/class/drm/card*/device/mem_info_gtt_total
```

**Two GPUs, one render node.** A laptop with both an iGPU and a discrete Radeon
exposes `renderD128` and `renderD129`, and which is which is not fixed across
boots on some kernels. Set `render_node` in `vars.yml` after checking
`ls -l /dev/dri/by-path`.

**`image: server-vulkan` is a moving tag.** Once the host works, pin the digest:

```bash
docker inspect ghcr.io/ggml-org/llama.cpp:server-vulkan --format '{{index .RepoDigests 0}}'
```

**LiteLLM caches its routing table at startup.** `config.yaml` is bind-mounted,
so compose sees no change to the service and will not recycle the container.
`10-stack.yml` restarts it when the rendered file changes; if you edit the file
on the host by hand, restart it yourself.
