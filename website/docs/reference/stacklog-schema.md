---
sidebar_position: 2
title: .stacklog schema
---

# `.stacklog` schema

One JSON object per line, appended to `.stacklog/YYYY-MM.jsonl`. For what the
log is *for* and how to read it, see [the operations page](../operations/stacklog).

## A line

```json
{
  "ts": "2026-07-28T14:19:37Z",
  "run_id": "20260728T140211Z-a3f9c201",
  "host": "h2-amd",
  "actor": "skill",
  "event": "apply",
  "action": "stack.up",
  "status": "ok",
  "duration_ms": 41230,
  "hw": { "gpu": "Radeon 860M", "vram_gib": 8 },
  "models": ["qwen2.5-coder-7b"],
  "detail": { "engine": "llamacpp" },
  "error": null
}
```

Every key is always present. Absent values are `null` or `[]`, never omitted, so
a `jq` filter does not have to guard for a missing field.

## Fields

| Field | Type | Required | Notes |
|---|---|---|---|
| `ts` | string | auto | UTC, `%Y-%m-%dT%H:%M:%SZ`. |
| `run_id` | string | auto | Shared across one install session. Set `LMSTACK_RUN_ID` once so every line correlates; otherwise each line gets its own. |
| `host` | string | **yes** | The inventory alias. The writer rejects anything containing a dot, so an IP or FQDN cannot get in. |
| `actor` | string | no | Defaults to `skill`. |
| `event` | enum | **yes** | See below. |
| `action` | string | **yes** | Dotted, stable, machine-groupable. |
| `status` | enum | **yes** | `ok` \| `failed` \| `skipped`. |
| `duration_ms` | number \| null | no | Worth setting for anything that takes real time; it is how you notice a host getting slower. |
| `hw` | object \| null | no | GPU model and memory. Not serials. |
| `models` | string[] | no | Passed as a comma-separated `--models`, stored as an array. |
| `detail` | object | no | Any JSON object. Keep it small and factual. |
| `error` | object \| null | no | `{kind, msg}`. |

### `event`

| Value | Means |
|---|---|
| `probe` | Read something about the host. Changed nothing. |
| `plan` | Decided what to do. Changed nothing. |
| `apply` | Changed the host. |
| `verify` | Checked the result of a change. |
| `decision` | The user chose between options the skill offered. |
| `error` | Something failed and the run is stopping. |

The `probe`/`plan`/`apply` split is what makes the log auditable: you can read
back exactly which lines touched the machine.

### `action`

Dotted namespaces, stable over time so grouping across months works:

```
probe.hardware            bootstrap.docker_install
probe.gpu                 bootstrap.gpu_runtime
plan.model_selection      stack.render
decision.model            stack.up
verify.aliases            verify.tool_calls
```

Inventing a new action is fine. Renaming an existing one silently breaks every
historical comparison, so do not.

### `error`

```json
"error": { "kind": "engine_timeout", "msg": "did not answer /v1/models within 40m" }
```

`kind` comes from the [troubleshooting tables](../operations/troubleshooting) —
that shared vocabulary is what makes a past occurrence findable. `msg` is one
line, factual, no stack traces.

## Redaction

Two independent passes run over the fully assembled event, so a value is caught
whether the key name or the value shape gives it away.

**1. Key-name denylist.** Any key matching this pattern, case-insensitive, at any
nesting depth, has its value replaced with `[REDACTED]`:

```
token|key|secret|password|passwd|auth|bearer|credential
```

**2. Value-shape denylist.** Any string matching one of these is replaced
wherever it appears, whatever the key is called:

| Shape | Catches |
|---|---|
| `sk-…` | OpenAI-style keys, including LiteLLM virtual keys |
| `hf_…` | Hugging Face tokens |
| `ghp_…` | GitHub personal access tokens |
| `AKIA…` | AWS access key ids |
| `-----BEGIN … PRIVATE KEY-----` | PEM private keys |
| `Bearer <token>` | Authorization headers copied out of a curl command |

Because redaction runs on the assembled event, it also covers anything passed
through `--detail` without thinking.

`tests/redaction_test.sh` feeds each of these shapes through the writer and
asserts none survive. If you add a field that could carry a new secret shape,
add a case there in the same commit.

## What never goes in

The filter is a backstop for mistakes, not a licence. Do not pass:

- prompt text or completion text, in any form, ever
- env file contents, or any single value from one
- SSH keys, private keys, or certificates
- IP addresses, hostnames, or MAC addresses
- anything you would not want in a file you later paste into an issue

## Validation

The writer rejects, with a non-zero exit and no line written:

- a missing `--host`, `--event`, `--action`, or `--status`
- an `--event` or `--status` outside its enum
- a `--host` that looks like an IP or contains a dot
- a `--detail` or `--hw` that is not valid JSON

It prints the path it wrote to on success, which is the only thing it writes to
stdout.
