---
sidebar_position: 2
title: Claude Code
---

# Claude Code

Claude Code drives Anthropic models and cannot be pointed at an
OpenAI-compatible endpoint. It can run a command, though, so the bridge is a
command rather than a provider.

```bash
cp pi-config/bin/lmstack-ask ~/bin/     # or put pi-config/bin on PATH
```

```bash
lmstack-ask "summarise the error handling here" < internal/parse.go
lmstack-ask -P lmstack-h1 "write a table test for Parse"
echo "$LOGS" | lmstack-ask "which of these are the same root cause?"
```

Claude Code will use it the same way you would — as a Bash command whose output
it reads.

## What it does

Runs `pi --print --no-session` against an lmstack provider and prints the
answer. Defaults chosen for being called by another agent rather than by a
human:

| Default | Why |
|---|---|
| `--no-tools` | A 7B model handed shell and edit tools inside someone else's session is a liability. `-t` opts in. |
| `--no-session` | One-shot calls should not leave session files behind. |
| model `qwen2.5-coder-7b` | The alias both hosts serve, so the same command works wherever it lands. |

Piped stdin is appended to the prompt rather than replacing it, so you can say
what to do with the text you are piping in.

## Host selection

With no `-P` and no `LMSTACK_PROVIDER`, it asks which LiteLLM answers —
loopback first — and prints the choice to stderr:

```
lmstack-ask: using lmstack-h2 (http://127.0.0.1:4000/v1)
```

That line is not noise. A silent fallback to a different host looks like a model
that got worse for no reason. Pin one with `-P lmstack-h1` or by exporting
`LMSTACK_PROVIDER`.

It reads host URLs from the same `~/.pi/agent/extensions/.env` the pi extensions
use, so there is one place to change an address.

## When this is worth doing

It is a real delegation: the local model does the work, Claude Code reads the
result, and it costs nothing.

That trade is good for bulk mechanical work over large amounts of text —
summarising logs, first-pass triage, describing unfamiliar code. It is bad for
anything where checking the 7B's answer would take longer than doing the task
directly. Delegation that has to be verified line by line is not delegation.
