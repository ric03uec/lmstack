---
sidebar_position: 3
title: The skill
---

# The skill

The interactive installer. It runs inside your agent — Claude Code, opencode, or
pi — and walks a host from bare GPU to answering endpoint.

```bash
make skill-install                 # every agent directory that exists
make skill-install AGENT=claude    # or force one: claude | opencode | pi
make skill-list                    # show where it would go, write nothing
```

Then: *use the lmstack skill to give me a starting point*.

## Why a skill and not a script

Everything the skill does, `make` can do. The difference is that the decisions
in the middle — is this hardware supported, which model fits, is that warning
worth stopping for — need judgement and context, and a script can only take a
flag. The parts that need arithmetic rather than judgement are not in the
prompt: they are in `classify.py`, which is a pure function of the probe and the
catalog, and is unit-tested against fixtures.

That split matters. The skill's judgement cannot be tested. Its arithmetic can,
and the arithmetic is the part that gets someone an out-of-memory error at 3am.

## What it will not do

These are enforced as rules in the skill prompt, not preferences.

**It never runs git.** Not `add`, not `commit`, not `checkout`, not `stash`. It
writes files; you decide what becomes a commit. A dirty working tree gets
mentioned and then left alone.

**It never reads or writes a secret value.** It tells you what to put in
`stack.env` and verifies the result by running the playbook, which checks for
non-empty without printing. If you paste a key into the conversation, it will
tell you to rotate it.

**It shows a diff before writing.** Every change to `inventory/hosts.ini` or a
host's `vars.yml` is shown and confirmed first.

**It stops on unsupported hardware.** No CPU fallback. It explains what would
change the verdict instead.

## The phases

### Phase 1 — target

Which host. `localhost`, or an SSH target, or a `~/.ssh/config` alias. It does
not ask about your hardware; that is what probing is for.

### Phase 2 — probe

```bash
ssh <target> 'bash -s' < skills/lmstack/scripts/probe-host.sh
```

Read-only, needs no privileges, and depends on nothing being installed — no
`jq`, no Python, no Docker. Piping it over stdin means nothing is copied to the
target and nothing is left behind.

It reports the GPU vendor, model, VRAM and GTT figures, DRM render nodes, the
Vulkan device, Docker's presence and registered runtimes, and whether sudo needs
a password. If SSH fails, that is the finding — it reports the error rather than
retrying with host key checking disabled.

### Phase 3 — classify

```bash
python3 skills/lmstack/scripts/classify.py --probe /tmp/probe.json
```

Turns the probe into a host role and a model list. It prints its arithmetic in
full, so you can check the sizing rather than trust it:

```
GTT budget 29 GiB (unified memory; the 2 GiB VRAM figure is a carve-out)
reserve 1 GiB for the display server and runtime context
model budget: 28 GiB -> tier 8g
qwen2.5-coder-7b needs 6 GiB -> fits, 22 GiB left
gemma-3-4b-it needs 4 GiB -> fits, 18 GiB left
total: 10 of 28 GiB
```

Warnings are shown, never swallowed. A host too small for the mandatory model
gets told explicitly that it will not serve the alias every other host serves,
and that anything pointed at it by model name will need reconfiguring.

### Phase 4 — write configuration

`inventory/hosts.ini` and the host's `vars.yml`, both as a diff first. Then
`make validate` before anything touches the host. A failure there is a
configuration error, and the skill fixes it rather than proceeding.

### Phase 5 — secrets

You fill `stack.env` on the host. The skill tells you what to generate and how,
and never sees the result.

### Phase 6 — run

`bootstrap`, `up`, `verify`. Failures are interpreted against the
[troubleshooting reference](operations/troubleshooting) before being reported,
and a failed bring-up stops the run — it will not verify against a stack that
did not start.

### Phase 7 — wire the control host

`make pi-install`, then a real request to confirm. Not a config file read back.

## What it records

Every phase writes one line to [`.stacklog/`](operations/stacklog): what host,
what action, whether it worked, how long it took. Failures too — a log
containing only successes cannot answer "what changed on this host and when did
it break", which is the entire reason the file exists.

The log is gitignored, never leaves your machine, identifies hosts by inventory
alias rather than address, and passes every value through two redaction filters
that have their own test.

## Its references

The skill loads these on demand rather than carrying them in every prompt:

| File | Read when |
|---|---|
| `references/hardware-probe.md` | Interpreting probe output |
| `references/model-catalog.md` | Adding a model that is not in the catalog |
| `references/troubleshooting.md` | Any playbook or verification failure |
| `references/stacklog-schema.md` | Writing a log line |
