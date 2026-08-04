---
sidebar_position: 1
title: pi
---

# pi

The control host is where you write code. It needs no GPU — only the address of
a host that has one, and a key.

## Install pi first

```bash
curl -fsSL https://pi.dev/install.sh | sh
```

The Windows and package-manager variants are on [pi.dev](https://pi.dev/). pi
is a prereq, not a recommendation: `make pi-install` writes into
`~/.pi/agent/` and needs that directory structure to exist.

## Point it at lmstack

```bash
make pi-install
$EDITOR ~/.pi/agent/extensions/.env    # host URL + LiteLLM key
pi --list-models | grep lmstack
```

```
lmstack-h1  qwen2.5-coder-7b  16.4K  4.1K  no  no
lmstack-h2  qwen2.5-coder-7b  16.4K  4.1K  no  no
```

## It merges, it does not replace

If you already use pi, you already have a `packages` list. `make pi-install`
adds three entries to it and leaves everything else alone, including settings
this repo knows nothing about. `make pi-dump` is symmetric: it captures back
only the entries the repo owns, so your personal configuration does not end up
in a public repository.

The script this was ported from copied `settings.json` but not the extensions it
names. A fresh machine then got a pi that started cleanly with no providers
registered and nothing useful in the logs. That is test T4.1.

## Configuration

`~/.pi/agent/extensions/.env`, created mode 0600 on first install and never
touched again — not by a re-install, not by `dump`.

```ini
LMSTACK_H1_URL=http://100.64.0.2:4000/v1
LMSTACK_H1_KEY=sk-...
LMSTACK_H2_URL=http://127.0.0.1:4000/v1
LMSTACK_H2_KEY=sk-...
```

Read the key from the host rather than from your notes:

```bash
ssh h1-nvidia 'grep ^LITELLM_MASTER_KEY ~/.lmstack/stack.env | cut -d= -f2'
```

`LMSTACK_H2_URL` defaults to loopback, which is right when h2-amd is this
machine. `LMSTACK_H1_URL` defaults to `http://h1-nvidia:4000/v1`, which assumes
an `~/.ssh/config` alias or a [Tailscale](../operations/tailscale) name.

An unconfigured provider still registers and then fails to connect. That is
deliberate: a clear connection error beats a provider that quietly vanishes from
`--list-models`.

## The status line

The installed layout shows provider, model, branch, context, tokens, and time.
It omits cost, because local inference has none and `$0.00` on every turn is
noise. Context is first among the numbers for a reason — a 16k window is the
binding constraint when you serve your own model.

## Advertised models must be real

Each extension lists the models its provider serves, and `make validate` (T0.10)
fails if any of those ids is not a LiteLLM alias some host actually exposes.

That check is the reason to edit `pi-config/extensions/` rather than
`~/.pi/agent/extensions/` directly. Hand-edits to the installed copy are lost on
the next sync, and they skip the check.

## Switching hosts

Both providers serve `qwen2.5-coder-7b`. Moving from the laptop to the DGX is a
provider change and nothing else — no prompt changes, no model name changes, no
per-host branching in whatever you have built on top.

## What lmstack turns off in pi

The `settings.json` this repo ships is intentionally lean — a fresh pi loaded
with lmstack should start in the fewest tokens of context possible, so the
local model has room for your work rather than for pi's own scaffolding.

| Setting | Value | Why |
|---|---|---|
| `defaultProvider` | `lmstack-h2` | Pre-selects the lmstack provider so the picker never appears at startup. Change to `lmstack-h1` if that is your primary. |
| `defaultModel` | `qwen2.5-coder-7b` | Same. Skips the model prompt. |
| `enableInstallTelemetry` | `false` | No install/update ping to `pi.dev`. |
| `quietStartup` | `true` | Hides the startup header. |
| `warnings.anthropicExtraUsage` | `false` | Not relevant when there is no Anthropic provider registered. |

pi's cloud providers (Anthropic, OpenAI, Codex, GitHub Copilot, etc.) do not
load unless you `/login` to them or set their API-key env vars, so lmstack does
not need to disable them explicitly — they simply do not appear. If you want a
pi that speaks only to lmstack, don't `/login` and don't export those keys.

Merge semantics still apply. If your existing `settings.json` already sets any
of these, `make pi-install` leaves your value in place — same rule as with
`packages`. Delete the key from your settings if you want the lmstack default
back.
