# `.stacklog` schema

Append-only JSONL, one file per month: `.stacklog/YYYY-MM.jsonl`. It answers one
question: *what changed on this host, when, and did it work?*

The files are gitignored and stay on the machine that produced them. Only
`.gitkeep` is tracked.

## Writing a line

Always through the writer. Never by appending to the file yourself — the
redaction pass is in the writer.

```bash
skills/lmstack/scripts/stacklog.sh \
  --host h2-amd \
  --event apply \
  --action stack.up \
  --status ok \
  --duration-ms 41230 \
  --models qwen2.5-coder-7b \
  --detail '{"engine":"llamacpp"}'
```

## Fields

| Field | Required | Notes |
|---|---|---|
| `host` | yes | The **inventory alias**. The writer rejects anything containing a dot, so an IP or FQDN cannot get in by habit. |
| `event` | yes | `probe` \| `plan` \| `apply` \| `verify` \| `decision` \| `error` |
| `action` | yes | Dotted, stable, machine-groupable: `bootstrap.docker_install`, `stack.up`, `verify.tool_calls`. |
| `status` | yes | `ok` \| `failed` \| `skipped` |
| `run_id` | auto | Shared across one install session. Set `LMSTACK_RUN_ID` once so every line correlates. |
| `actor` | no | Defaults to `skill`. |
| `duration_ms` | no | Worth setting for anything that takes real time; it is how you spot a host getting slower. |
| `hw` | no | GPU model and memory. Not serials. |
| `models` | no | Comma-separated slugs. |
| `detail` | no | Any JSON object. Keep it small and factual. |
| `error` | no | `--error-kind` from `troubleshooting.md`, plus a one-line `--error-msg`. |

## What never goes in

Redaction is a backstop for mistakes, not permission to log freely. Do not pass:

- prompt text or completion text, in any form, ever
- env file contents, or any single value from one
- SSH keys, private keys, or certificates
- IP addresses, hostnames, or MAC addresses
- anything you would not want in a file you later paste into an issue

## How redaction works

Two independent passes over the assembled event, so a value is caught whether
the key name or the value shape gives it away:

1. **Key-name denylist** — any key matching
   `token|key|secret|password|passwd|auth|bearer|credential`, at any nesting
   depth, has its value replaced with `[REDACTED]`.
2. **Value-shape denylist** — any string matching `sk-…`, `hf_…`, `ghp_…`,
   `AKIA…`, a PEM header, or `Bearer <token>` is replaced wherever it appears,
   whatever the key is called.

`tests/redaction_test.sh` feeds real secret shapes through the writer and asserts
none survive. If you add a field that could carry a new secret shape, add a case
there.

## Reading the log

```bash
# what happened in the last run
jq -c 'select(.run_id == "…")' .stacklog/*.jsonl

# every failure, ever
jq -c 'select(.status == "failed") | {ts, host, action, error}' .stacklog/*.jsonl

# how long bring-up takes over time
jq -r 'select(.action == "stack.up" and .status == "ok")
       | [.ts, .host, .duration_ms] | @tsv' .stacklog/*.jsonl
```

## Logging failures

A log containing only successes cannot answer the question the file exists for.
When something fails, log it and then stop:

```bash
skills/lmstack/scripts/stacklog.sh --host h1-nvidia --event error \
  --action stack.up --status failed \
  --error-kind engine_timeout \
  --error-msg "vllm-qwen2.5-coder-7b did not answer /v1/models within 40m"
```
