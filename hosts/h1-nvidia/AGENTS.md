# h1-nvidia

NVIDIA GPU host. vLLM serves the models; LiteLLM fronts them.

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
make deps                       # once: ansible collections, on your machine
make bootstrap HOST=h1-nvidia   # once: docker, nvidia toolkit, firewall
make up        HOST=h1-nvidia   # render, pull, start, health-gate
make verify    HOST=h1-nvidia   # endpoint conformance
```

`make site HOST=h1-nvidia` runs all three. Everything is re-runnable.

## Assumptions

- The NVIDIA **driver** is already installed. Bootstrap checks `nvidia-smi` and
  stops if it is missing rather than guessing at your kernel.
- The install root is `~/.lmstack` on the target. Nothing lands in `/etc` or
  `/var/lib`, and there is no systemd unit — containers come back after a reboot
  because of `restart: unless-stopped`.
- Root is used for exactly two things: installing packages during bootstrap, and
  the one UFW rule. `10-stack.yml` and `20-verify.yml` need none.

## Files

| Path | What it is |
|---|---|
| `ansible/vars.yml` | The knobs. `active_models` and `vram_budget_gib` are the two you will touch. |
| `ansible/00-bootstrap.yml` | Docker, NVIDIA container toolkit, runtime registration, firewall. |
| `ansible/10-stack.yml` | Validate, render, start, wait. |
| `ansible/20-verify.yml` | T3.2–T3.7 against the live endpoint. |
| `vllm/models/*.yml` | One file per model. The contract is in the repo-root `AGENTS.md`. |
| `vllm/docker-compose.yml.j2` | Rendered to the install root. Never edit the rendered copy. |
| `vllm/litellm/config.yaml.j2` | The routing table. |
| `vllm/env/stack.env.example` | Copied to the host once and never overwritten. |

## Changing which models run

Edit `active_models` in `ansible/vars.yml`, then `make up HOST=h1-nvidia`. There
is no switch script; re-running the playbook is the switch. `make validate`
refuses an over-budget set before Ansible connects to anything.

## Things that will bite you

**Tool calls arriving as prose.** If an agent loop gets plain text where it
expected `tool_calls`, the model's `extra_args` is missing a `--tool-call-parser`
that matches its chat template. This is the most common failure here and is why
`20-verify.yml` tests it explicitly (T3.4).

**Sizing at 8 GiB.** `gpu_memory_utilization` is a fraction of *total* card
memory, and weights come out of that same allowance. The arithmetic for the
default model is written out in `vllm/models/qwen2.5-coder-7b.yml`. Raising
`max_model_len` on a small card causes preemption, not an error message.

**`image: latest` is not reproducible.** Once the host works, pin the digest:

```bash
docker inspect vllm/vllm-openai:latest --format '{{index .RepoDigests 0}}'
```

**LiteLLM caches its routing table at startup.** `config.yaml` is bind-mounted,
so compose sees no change to the service and will not recycle the container.
`10-stack.yml` restarts it when the rendered file changes; if you edit the file
on the host by hand, restart it yourself.
