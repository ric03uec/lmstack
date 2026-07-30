---
sidebar_position: 1
title: h1-nvidia
---

# h1-nvidia

An NVIDIA GPU host. vLLM serves the models; LiteLLM fronts them.

```
                    :4000  LiteLLM  <- the only externally reachable port
                              |
                  compose network (http://vllm-<slug>:8000)
                              |
              127.0.0.1:8001  vllm-qwen2.5-coder-7b
                              |
                        postgres (no published ports)
```

## Running it

```bash
make deps                       # once: Ansible collections, on your machine
make bootstrap HOST=h1-nvidia   # once: Docker, NVIDIA toolkit, firewall
make up        HOST=h1-nvidia   # render, pull, start, health-gate
make verify    HOST=h1-nvidia   # endpoint conformance
```

`make site HOST=h1-nvidia` runs all three. Everything is re-runnable.

## Assumptions

- **The NVIDIA driver is already installed.** Bootstrap checks `nvidia-smi` and
  stops if it is missing, rather than guessing at your kernel. It installs
  Docker and the container toolkit on top of a working driver.
- The install root is `~/.lmstack` on the target. Nothing lands in `/etc` or
  `/var/lib`, and there is no systemd unit — containers come back after a reboot
  because of `restart: unless-stopped`.
- Root is used for two things: installing packages during bootstrap, and one UFW
  rule. Bringing the stack up and verifying it need no privileges at all.

## Why vLLM

Throughput, and tool-call parsing that works. vLLM ships parsers matched to
specific chat templates — `hermes` for the Qwen2.5 ChatML format — and gets the
`tool_calls` field populated correctly where a generic OpenAI shim would hand
you the call as prose in `message.content`.

## Sizing on a small card

`gpu_memory_utilization` is a fraction of *total* card memory, and the weights
come out of that same allowance. For the default model on 8 GiB:

- `gpu_memory_utilization: 0.90` allocates about 7.2 GiB
- AWQ 4-bit weights take about 4.7 GiB
- that leaves roughly 2.5 GiB of KV cache
- at 16384 context, that is about two concurrent full-length sequences, hence
  `max_num_seqs: 2`

AWQ rather than FP16 is not a preference. The FP16 weights are around 15 GiB and
will not fit in 8 GiB at any context length. vLLM auto-detects the AWQ config
from the repository, so no `--quantization` flag is needed; on Ampere and newer
it picks the `awq_marlin` kernel by itself.

Raising `max_model_len` on a small card causes preemption, not an error. Raise
the card before raising the context.

## Things that will bite you

**Tool calls arriving as prose.** If an agent loop gets plain text where it
expected `tool_calls`, the model's `extra_args` is missing a
`--tool-call-parser` matching its chat template. This is the most common failure
here, which is why `20-verify.yml` tests it explicitly (T3.4).

**`image: latest` is not reproducible.** Once the host works, pin the digest:

```bash
docker inspect vllm/vllm-openai:latest --format '{{index .RepoDigests 0}}'
```

**LiteLLM caches its routing table at startup.** `config.yaml` is bind-mounted,
so compose sees no change to the service and will not recycle the container.
`10-stack.yml` restarts it when the rendered file changes; if you edit the file
on the host by hand, restart it yourself.

## Changing which models run

Edit `active_models` in `hosts/h1-nvidia/ansible/vars.yml`, then
`make up HOST=h1-nvidia`. There is no switch script — re-running the playbook is
the switch. `make validate` refuses an over-budget set before Ansible connects
to anything.

See [Adding a model](../models/adding-a-model) for the full contract.
