---
sidebar_position: 4
title: Quickstart
---

# Quickstart

This is the explicit path: every step the skill would take, done by hand. It is
worth reading even if you use the skill, because it is what the skill runs.

If you would rather not, [install the skill](install) and ask it for a starting
point.

## Before you start

- A GPU host: NVIDIA with a working driver, or AMD with `amdgpu` loaded. At
  least 8 GiB of usable GPU memory.
- SSH access to it, or it is the machine you are sitting at.
- On the control host: `git`, `make`, `jq`, `python3`, `tmux`, **pi**, and **Ansible**.

```bash
curl -fsSL https://pi.dev/install.sh | sh    # pi
uv tool install ansible-core                  # Ansible
# tmux via your package manager: apt install tmux / brew install tmux / etc.
```

pi is the editor lmstack wires at the end. You do not need Docker on the GPU
host — bootstrap installs it there.

## Set up the control host

```bash
git clone https://github.com/ric03uec/lmstack && cd lmstack
make deps                                   # Ansible collections
cp inventory/hosts.ini.example inventory/hosts.ini
$EDITOR inventory/hosts.ini                 # ansible_host, ansible_user
```

Pick the host role that matches your hardware and set its models:

```bash
$EDITOR hosts/h2-amd/ansible/vars.yml       # active_models, vram_budget_gib
make validate                               # catches the mistakes offline
```

Then bring it up:

```bash
make bootstrap HOST=h2-amd     # Docker, GPU runtime, firewall — needs sudo
make up        HOST=h2-amd     # render, pull, start, health-gate
make verify    HOST=h2-amd     # conformance suite against the endpoint
```

If sudo on the target needs a password — normal for a local connection —
`make bootstrap` cannot supply it. Run the playbook directly:

```bash
ansible-playbook -i inventory/hosts.ini hosts/h2-amd/ansible/00-bootstrap.yml -K
```

### Secrets

The first `make up` drops `~/.lmstack/env/stack.env` from the example and stops.
Fill it in on the host, then run `make up` again. It is never overwritten
afterwards.

| Variable | Needed on | Generate with |
|---|---|---|
| `LITELLM_MASTER_KEY` | both | `printf 'sk-%s\n' "$(openssl rand -hex 24)"` |
| `LITELLM_DB_PASSWORD` | both | `openssl rand -hex 24` |
| `HF_TOKEN` | `h1-nvidia`; optional on `h2-amd` | [huggingface.co/settings/tokens](https://huggingface.co/settings/tokens) |

`h2-amd` only needs `HF_TOKEN` for gated repositories. The default GGUF
quantizations are in ungated community repos.

### Expect the first run to be slow

`make up` downloads model weights — several GiB. That is not a hang. Subsequent
runs skip the download.

## Confirm it works

```bash
curl -s http://<host>:4000/health/liveliness

curl -s http://<host>:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen2.5-coder-7b","messages":[{"role":"user","content":"reply with ok"}]}'
```

## Point your editor at it

```bash
make pi-install
$EDITOR ~/.pi/agent/extensions/.env    # host URL + LiteLLM key
pi --list-models | grep lmstack
```

`make pi-install` merges into your existing pi configuration rather than
replacing it. For Claude Code and opencode, see [Control host](control-host/pi).

## Verifying without a GPU

The whole static suite runs anywhere, including in CI:

```bash
make test
```

It validates every model YAML, proves the validator rejects known-bad
configuration, renders every template and asserts the loopback binding, checks
alias parity across the two engines, and feeds real secret shapes through the
`.stacklog` writer to confirm none survive.
