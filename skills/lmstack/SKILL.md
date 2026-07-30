---
name: lmstack
description: Interactive installer for lmstack — a local LLM stack served behind one OpenAI-compatible endpoint. Use when the user wants to set up, extend, or debug local model serving on a GPU host (NVIDIA/vLLM or AMD/llama.cpp), asks for "a starting point" with lmstack, or wants their editor pointed at a self-hosted model.
---

# lmstack

You are installing a local LLM inference stack on a GPU host and pointing the
user's editor at it. The repository is at `{{LMSTACK_REPO}}`.

Export that path first and use it for everything. This installed copy of the
skill does **not** sit inside the repository, so a relative path resolves against
the agent's skill directory and finds nothing:

```bash
export LMSTACK_REPO={{LMSTACK_REPO}}
cd "$LMSTACK_REPO"
```

If that directory does not exist the repository was moved or renamed. Tell the
user to re-run `make skill-install` from its new location; do not go looking for
it.

Work through the phases in order. Each one ends with a decision the user makes,
not one you make for them.

## Ground rules

These are not style preferences. Breaking one damages something the user cares
about more than the install succeeding.

1. **Never run git.** Not `add`, not `commit`, not `checkout`, not `stash`. You
   write files; the user decides what becomes a commit. If the working tree is
   dirty, say so and continue — it is not your tree to clean.
2. **Never read, echo, or write secret values.** You tell the user to fill
   `stack.env` on the host and you verify the shape of the result by running the
   playbook, which checks for non-empty without printing. If you ever find
   yourself about to `cat` an env file, stop.
3. **Show a diff before writing.** Any change to `inventory/hosts.ini` or a
   host's `vars.yml` gets shown as a diff and confirmed first.
4. **Log every phase** to `.stacklog/` via `skills/lmstack/scripts/stacklog.sh`. One line per
   action, including the ones that fail. See [Logging](#logging).
5. **Do not invent model configuration.** Recommendations come from
   `scripts/classify.py` reading the catalog. If the user wants something not in
   the catalog, add a model YAML — the contract is in the repo-root `AGENTS.md`.
6. **Stop on an unsupported host.** Explain why and what would change the
   verdict. Do not fall back to CPU inference; it is slow enough to look broken
   and the user will blame the repo.

## Phase 1 — Target

Ask which host to set up. Accept:

- `localhost` / "this machine" → the local connection path
- an SSH target (`user@host`, or a `~/.ssh/config` alias)

Ask nothing else yet. Hardware questions are answered by probing, not by asking
the user to recall their VRAM.

```bash
"$LMSTACK_REPO/skills/lmstack/scripts/stacklog.sh" --host "$ALIAS" --event decision --action target.selected --status ok
```

The alias is not known until Phase 3, so log this one under `pending` and use
the real alias from Phase 3 onward.

## Phase 2 — Probe

```bash
# local
bash "$LMSTACK_REPO/skills/lmstack/scripts/probe-host.sh"

# remote — the script is self-contained, so piping it over stdin avoids
# needing anything installed on the target first
ssh "$TARGET" 'bash -s' < "$LMSTACK_REPO/skills/lmstack/scripts/probe-host.sh"
```

Read-only, needs no privileges, and works on a host with no docker, no jq and
no python. Save the output; you need it for the next phase.

If SSH fails, that is the finding — report the exact error. Do not retry with
different options or suggest disabling host key checking.

## Phase 3 — Classify

```bash
python3 "$LMSTACK_REPO/skills/lmstack/scripts/classify.py" --probe /tmp/probe.json
```

This is a pure function of the probe and the catalog. Do not second-guess its
arithmetic; if it looks wrong, the fix is a code change with a test, not a
one-off override in conversation.

Present to the user:

- the host role it chose (`h1-nvidia` or `h2-amd`) and why
- **the arithmetic, in full** — the `arithmetic` array exists so the user can
  check the sizing rather than trust it
- every `warnings` entry
- the recommended model list

If `supported` is `false`, relay `reason` and `remedy`, log an `error` event,
and stop.

Ask the user to confirm or change the model list before continuing.

```bash
"$LMSTACK_REPO/skills/lmstack/scripts/stacklog.sh" --host "$ALIAS" --event probe --action host.classified --status ok \
  --hw '{"gpu":"...","vram_gib":N}' --models "slug-a,slug-b"
```

`--hw` takes the GPU model and memory only. The probe also contains the kernel
version and the OS build; those are fine. It does not contain a serial number,
and you should not add one.

## Phase 4 — Write configuration

Two files, both shown as a diff first.

**`inventory/hosts.ini`** — create it from `inventory/hosts.ini.example` if it
does not exist. Set `ansible_host` for a remote target, or leave
`ansible_connection=local` for the local one. Set `ansible_user`.

**`hosts/<role>/ansible/vars.yml`** — set `active_models` to the confirmed list.
Set `vram_budget_gib` to the probe's usable figure. On an AMD APU that is the
GTT budget, not the VRAM carve-out; `classify.py` has already worked this out,
so use `usable_gib` from its output.

Then validate before touching the host:

```bash
make validate
```

A failure here is a configuration error you introduced. Fix it and re-run; do
not proceed to Ansible with a failing validator.

```bash
"$LMSTACK_REPO/skills/lmstack/scripts/stacklog.sh" --host "$ALIAS" --event plan --action config.written --status ok \
  --detail '{"files":["inventory/hosts.ini","hosts/h2-amd/ansible/vars.yml"]}'
```

## Phase 5 — Secrets

The playbook drops `stack.env` from the example on its first run and never
overwrites it. So the sequence is: run `make up` once, let it stop at the secret
check, have the user fill the file, run again.

Tell the user exactly what to fill and how to generate it:

| Variable | Required on | Generate with |
|---|---|---|
| `LITELLM_MASTER_KEY` | both | `printf 'sk-%s\n' "$(openssl rand -hex 24)"` |
| `LITELLM_DB_PASSWORD` | both | `openssl rand -hex 24` |
| `HF_TOKEN` | h1-nvidia; optional on h2-amd | https://huggingface.co/settings/tokens |

The file is at `~/.lmstack/env/stack.env` on the target, mode 0600.

You do not read this file. You do not ask the user to paste its contents. If the
user pastes a key into the conversation anyway, tell them to rotate it.

## Phase 6 — Run

```bash
make bootstrap HOST=<role>   # once per host
make up        HOST=<role>
make verify    HOST=<role>
```

`bootstrap` installs packages, so it needs sudo. If the probe reported
`"sudo": "password"` — which is normal on a local connection — it must be run
with `-K` and `make` cannot supply that:

```bash
ansible-playbook -i inventory/hosts.ini hosts/<role>/ansible/00-bootstrap.yml -K
```

Hand that command to the user to run rather than trying to feed a password.

Expect `make up` to take a long time on a first run: it downloads model weights.
That is not a hang.

Interpret failures against `references/troubleshooting.md` before reporting
them. Log each stage:

```bash
"$LMSTACK_REPO/skills/lmstack/scripts/stacklog.sh" --host "$ALIAS" --event apply --action stack.up --status ok \
  --duration-ms "$MS" --models "slug-a"
```

On failure, `--status failed --error-kind <kind> --error-msg "<one line>"` with
a `kind` from the troubleshooting reference, and **stop**. Do not continue to
verification against a stack that did not come up.

## Phase 7 — Wire the control host

Point the user's editor at the new endpoint.

```bash
make pi-install          # merges into ~/.pi/agent; it does not replace it
```

Then the user fills `~/.pi/agent/extensions/.env` with the host URL and the
LiteLLM key. Same rule as Phase 5: you do not read that file and you do not
ask them to paste it.

Confirm with a real request, not by reading a config file back:

```bash
pi --list-models | grep lmstack
pi -p --provider lmstack-h2 --model qwen2.5-coder-7b "reply with the word ok"
```

If the user works in Claude Code or opencode rather than pi, see
`pi-config/bridges/README.md` — opencode talks to LiteLLM directly, Claude Code
goes through `bin/lmstack-ask`.

If the host serves a model the extension does not advertise, `make validate`
fails with T0.10. Fix it by editing `pi-config/extensions/`, not by editing the
installed copy under `~/.pi/agent/` — that gets overwritten on the next sync.

## Logging

Every phase writes one line through `skills/lmstack/scripts/stacklog.sh`, which redacts before
it writes. Read `references/stacklog-schema.md` for the field list.

The rules that matter:

- `--host` is the **inventory alias**, never an IP or hostname. The writer
  rejects anything with a dot in it.
- Never pass prompt text, completion text, or env file contents in `--detail`.
  Redaction is a backstop for mistakes, not a licence to log freely.
- Log failures too. A log that only contains successes is useless for the
  "what changed on this host and when did it break" question the file exists to
  answer.

## References

| File | Read it when |
|---|---|
| `references/hardware-probe.md` | Interpreting probe output, or it reported something odd |
| `references/model-catalog.md` | The user wants a model that is not in the catalog |
| `references/troubleshooting.md` | Any playbook or verification failure |
| `references/stacklog-schema.md` | Writing a `.stacklog` line |

Repo-root `AGENTS.md` holds the invariants that apply to the whole repository,
including the model YAML contract.
