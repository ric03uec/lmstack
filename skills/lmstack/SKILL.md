---
name: lmstack
description: Interactive installer for lmstack — a local LLM stack served behind one OpenAI-compatible endpoint. Use when the user wants to set up, extend, or debug local model serving on a GPU host (NVIDIA/vLLM or AMD/llama.cpp), asks for "a starting point" with lmstack, or wants their editor pointed at a self-hosted model.
---

# lmstack

You are installing a local LLM inference stack on a GPU host and pointing the
user's editor at it.

Work through the phases in order, starting at Phase 0. Each one ends with a
decision the user makes, not one you make for them.

## Ground rules

These are not style preferences. Breaking one damages something the user cares
about more than the install succeeding.

1. **Never run git inside the repository.** Not `add`, not `commit`, not
   `checkout`, not `stash`. You write files; the user decides what becomes a
   commit. If the working tree is dirty, say so and continue — it is not your
   tree to clean. The one exception is the first-time `git clone` in Phase 0,
   which creates a repository rather than changing one.
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
7. **Never run a sudo command yourself.** Print it, explain what it changes,
   wait for the user to run it and paste back the output. This is not a
   permissions issue — it is a trust one. The user must be able to see, on
   their own screen, what is about to touch their machine before it happens.
   The full pattern is in [Phase 6](#phase-6--run).

## Phase 0 — Find the repository

You are running from the agent's skill directory, not from inside the
repository, so a relative path finds nothing. The playbooks, the model catalog,
and the validator all live in the repository, and everything after this phase
needs `$LMSTACK_REPO` set.

Resolve it in this order — an explicit override, the path bound at install time,
then the default clone location:

```bash
bound='{{LMSTACK_REPO}}'
for candidate in "${LMSTACK_REPO:-}" "$bound" "$HOME/lmstack"; do
  if [ -n "$candidate" ] && [ -d "$candidate/hosts" ]; then
    export LMSTACK_REPO="$candidate"
    break
  fi
done
echo "${LMSTACK_REPO:-NOT FOUND}"
```

If that printed a path, use it and go to Phase 1.

If it printed `NOT FOUND`, the user installed the skill on its own, which is the
normal way in. Tell them you need a clone to work from, offer
`~/lmstack`, and take a different path if they want one:

```bash
export LMSTACK_REPO="$HOME/lmstack"
git clone https://github.com/ric03uec/lmstack "$LMSTACK_REPO"
```

This is the only git command in the skill. Do not run it without asking, and do
not clone over a directory that already has something in it.

Then check the control host has what the playbooks and the final wiring need:

```bash
cd "$LMSTACK_REPO"
for t in make python3 jq tmux ansible-playbook pi; do
  command -v "$t" >/dev/null || echo "missing: $t"
done
```

Three are usually the ones missing. For each, tell the user which and hand
them the exact command — you do not run these yourself, because they need
sudo or write to `$HOME`:

| Missing tool | Command to hand the user |
|---|---|
| `ansible-playbook` | `uv tool install ansible-core` (not pipx, not the system package manager) |
| `pi` | `curl -fsSL https://pi.dev/install.sh \| sh` |
| `tmux` | Their package manager: `apt install tmux`, `brew install tmux`, `dnf install tmux`, etc. |

pi is not optional. Phase 7 wires it at the endpoint the earlier phases build,
and a run that ends with no editor pointed at the stack is a run that failed
to deliver on what the user asked for. Do not skip it and do not substitute
another editor without asking.

Wait for the user to confirm each install completed, then continue. Once every
tool resolves, fetch the collections the playbooks import:

```bash
make deps
```

Nothing here touches the GPU host. If any of it fails, stop and report it: a
missing tool on the control host is a two-minute fix, and finding out about it
halfway through a bring-up is not.

```bash
"$LMSTACK_REPO/skills/lmstack/scripts/stacklog.sh" --host pending --event decision --action repo.ready --status ok
```

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

**Any command that needs sudo, you hand to the user.** You do not run it. This
is not about permissions — it is about the user being able to see, on their
own screen, exactly what is about to touch their machine before it happens.
Every sudo command is a small trust ask, and the answer is theirs to give.

The pattern for any sudo step:

1. Print the exact command, in a fenced block, ready to copy.
2. Explain in one sentence what it will change (packages installed, groups
   added, files written).
3. Wait for the user to run it and paste the result — the last few lines of
   output, or the summary line.
4. Read the pasted output to decide whether to continue. Do not assume it
   succeeded because they said "done".

`bootstrap` is the main one. When the probe reported `"sudo": "password"` —
normal on a local connection — `make bootstrap` cannot pipe the password in,
so the command to hand over is:

```bash
ansible-playbook -i inventory/hosts.ini hosts/<role>/ansible/00-bootstrap.yml -K
```

If it reported `"sudo": "passwordless"` — normal on a remote host with a
configured SSH user — `make bootstrap HOST=<role>` works directly. Still show
it to the user first; still wait for confirmation.

Expect `make up` to take a long time on a first run: it downloads model weights.
That is not a hang. It does not need sudo — you can run it.

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

First, re-verify pi is installed — a lot has happened since Phase 0 and it may
have been a different session:

```bash
command -v pi >/dev/null || echo "pi missing"
```

If missing, hand the user the install command and wait — do not skip this
phase. The whole point of the skill is to land at a working editor.

```bash
curl -fsSL https://pi.dev/install.sh | sh
```

Then install the lmstack pi configuration:

```bash
make pi-install
```

That merges lmstack's providers, statusline, and lean defaults into
`~/.pi/agent/`. It never overwrites a value the user has already set — same
rule as with an existing `packages` entry. The lean defaults it seeds
(`defaultProvider`, `quietStartup`, `enableInstallTelemetry: false`) exist so
pi starts in as few tokens of context as possible, leaving the 16k window for
the user's work rather than for pi's own scaffolding. See
`website/docs/control-host/pi.md` for the full list.

The user then fills `~/.pi/agent/extensions/.env` with the host URL and the
LiteLLM key. Same rule as Phase 5: you do not read that file and you do not
ask them to paste it.

Confirm with a real request, not by reading a config file back:

```bash
pi --list-models | grep lmstack
pi -p --provider lmstack-h2 --model qwen2.5-coder-7b "reply with the word ok"
```

If the user has explicitly said they work in Claude Code or opencode instead
of pi, see `pi-config/bridges/README.md` — opencode talks to LiteLLM directly,
Claude Code goes through `bin/lmstack-ask`. But confirm before taking that
path: the default is to wire pi, because pi is the one editor that stays
inside the local-only story from end to end.

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
