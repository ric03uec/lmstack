---
sidebar_position: 4
title: The change log
---

# `.stacklog`

Every action the skill takes against a host appends one JSON line to
`.stacklog/YYYY-MM.jsonl`. It exists to answer one question later: *what changed
on this host, when, and did it work?*

Six months after you set a machine up, the reason it is slow is usually
something you did to it. Shell history does not survive, and Ansible output
scrolls away. This does not.

## It stays on your machine

```
.stacklog/
├── .gitkeep        # tracked
└── 2026-07.jsonl   # gitignored
```

Only `.gitkeep` is in the repository. The log files are gitignored, so cloning
this repo gives you an empty directory and pushing never carries yours.

Hosts are identified by **inventory alias** — `h1-nvidia`, not `192.168.1.17`
and not `spark.your-tailnet.ts.net`. The writer rejects any `--host` containing
a dot, so an address cannot get in by habit.

## Reading it

```bash
make stacklog
```

```
2026-07-28T14:02:11Z  h2-amd  OK      probe.hardware
2026-07-28T14:02:44Z  h2-amd  OK      bootstrap.docker_install
2026-07-28T14:11:03Z  h2-amd  FAILED  stack.up
2026-07-28T14:19:37Z  h2-amd  OK      stack.up
```

For anything more specific, it is JSONL, so use `jq`:

```bash
# everything from one install session
jq -c 'select(.run_id == "20260728T140211Z-a3f9c201")' .stacklog/*.jsonl

# every failure, ever, with the kind
jq -c 'select(.status == "failed") | {ts, host, action, error}' .stacklog/*.jsonl

# is bring-up getting slower?
jq -r 'select(.action == "stack.up" and .status == "ok")
       | [.ts, .host, .duration_ms] | @tsv' .stacklog/*.jsonl
```

The `error.kind` values are the same ones in the
[troubleshooting tables](troubleshooting), which is what makes a past occurrence
greppable — you can find out whether you have hit this before, and what you did
about it.

## Writing to it

Through the writer, always:

```bash
skills/lmstack/scripts/stacklog.sh \
  --host h2-amd \
  --event apply \
  --action stack.up \
  --status ok \
  --duration-ms 41230 \
  --models qwen2.5-coder-7b
```

Never by appending to the file yourself. The redaction pass lives in the writer,
so a hand-written line is an unredacted line. Full field list in
[the schema reference](../reference/stacklog-schema).

Set `LMSTACK_RUN_ID` once at the start of a session and every line from it
correlates:

```bash
export LMSTACK_RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$RANDOM"
```

## What is deliberately not in it

No prompts. No completions. No env file contents, no single value from one. No
IP addresses, hostnames, or MAC addresses. No keys of any kind.

Two independent redaction passes run over every assembled event — one on key
names, one on value shapes — and `tests/redaction_test.sh` feeds real secret
formats through the writer and asserts none survive. But treat that as a
backstop for mistakes, not as permission to log freely. The filter catches the
shapes it knows about.

## Logging failures

A log containing only successes cannot answer the question the file exists for.
The one line you will actually want in six months is the one recording that
something broke:

```bash
skills/lmstack/scripts/stacklog.sh --host h1-nvidia --event error \
  --action stack.up --status failed \
  --error-kind engine_timeout \
  --error-msg "vllm-qwen2.5-coder-7b did not answer /v1/models within 40m"
```

Then stop. The skill does not retry past a failure it has recorded.

## If you do not want it

Delete the files. Nothing reads them but you:

```bash
rm .stacklog/*.jsonl
```

The skill will start a new one on its next run. There is no setting to disable
it, because a log you can delete at any time is a smaller problem than a log
that silently was not being kept.
