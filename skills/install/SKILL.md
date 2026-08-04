---
name: install
description: Install the lmstack inference stack on a GPU host and point the user's editor at it. Brings up llama.cpp or vLLM behind a LiteLLM endpoint via Ansible, generates the host configuration under ~/.lmstack/, and wires pi. Use after /lmstack:analyze has said the hardware is supported, or when the user asks to set up, extend, or repair local model serving.
---

# install

Bring up the stack on a host that `/lmstack:analyze` has already cleared, and
end with the user's editor talking to it.

Each phase ends with a decision the user makes, not one you make for them.

## Ground rules

These are not style preferences. Breaking one damages something the user cares
about more than the install succeeding.

1. **Never run git inside the user's repository.** Not `add`, not `commit`, not
   `checkout`, not `stash`. If the working tree is dirty, say so and continue —
   it is not your tree to clean.
2. **Nothing you write lands in the repository.** All generated configuration
   goes under `~/.lmstack/<role>/`. A user who installs lmstack should be able
   to run `git status` in the clone afterwards and see nothing.
3. **Never read, echo, or write secret values.** You tell the user what to fill
   in and the playbook checks the result for non-empty without printing it. If
   you are about to `cat` an env file, stop.
4. **Show a diff before writing.** Any change to a host's `hosts.ini` or
   `vars.yml` is shown as a diff and confirmed first.
5. **Do not invent model configuration.** Recommendations come from
   `lmstack-classify` reading the catalog. To add something outside the catalog,
   add a model YAML — the contract is in the repo-root `AGENTS.md`.
6. **Stop on an unsupported host.** Explain what would change the verdict. Never
   fall back to CPU inference; it is slow enough to look broken and the user
   will blame the project rather than the hardware.
7. **Never run a sudo command yourself.** Print it, explain what it changes,
   wait for the user to run it and paste back the output. This is a trust
   boundary, not a permissions problem: the user must be able to see, on their
   own screen, what is about to touch their machine. The pattern is in
   [Phase 5](#phase-5--run).

## Phase 0 — Prerequisites

The playbooks live in this plugin, at `${CLAUDE_PLUGIN_ROOT}`. There is nothing
to clone and no path to resolve.

Check the control host has what the playbooks and the final wiring need:

```bash
for t in make python3 jq tmux ansible-playbook pi; do
  command -v "$t" >/dev/null || echo "missing: $t"
done
```

For each missing tool, hand the user the exact command. You do not run these
yourself — they need sudo or write to `$HOME`:

| Missing tool | Command to hand the user |
|---|---|
| `ansible-playbook` | `uv tool install ansible-core` (not pipx, not the system package manager) |
| `pi` | `curl -fsSL https://pi.dev/install.sh \| sh` |
| `tmux` | Their package manager: `apt install tmux`, `brew install tmux`, `dnf install tmux` |

pi is not optional. Phase 6 wires it at the endpoint the earlier phases build,
and a run that ends with no editor pointed at the stack has not delivered what
the user asked for. Do not skip it and do not substitute another editor without
asking.

Wait for the user to confirm each install, then fetch the collections the
playbooks import:

```bash
cd "${CLAUDE_PLUGIN_ROOT}" && make deps
```

Nothing here touches the GPU host. If any of it fails, stop and report it: a
missing tool on the control host is a two-minute fix, and finding out about it
halfway through a bring-up is not.

```bash
lmstack-log --host pending --event decision --action prereqs.ready --status ok
```

## Phase 1 — Confirm the target

You need a role and a connection. If `~/.lmstack/<role>/probe.json` exists from
a recent `/lmstack:analyze`, use it and say which host it describes.

If it does not, **run `/lmstack:analyze` first.** Do not install against a host
whose hardware you have not seen. Installing onto a machine that cannot serve
the model wastes a long download before failing.

## Phase 2 — Write the host configuration

Three files, under `~/.lmstack/<role>/`, each shown as a diff first.

**`hosts.ini`** — start from `${CLAUDE_PLUGIN_ROOT}/inventory/hosts.ini.example`.
Set `ansible_host` for a remote target, or keep `ansible_connection=local` for
the local one. Set `ansible_user`.

**`vars.yml`** — only the values that differ from the tracked defaults in
`${CLAUDE_PLUGIN_ROOT}/hosts/<role>/ansible/vars.yml`. This file is passed to
Ansible with `-e`, the highest-precedence source, so it overrides the defaults
without editing them. Set:

- `active_models` — the list the user confirmed
- `vram_budget_gib` — `usable_gib` from the classifier, not a figure you derived
- `render_node` — only if the probe found more than one, and only after asking
  which card. `ls -l /dev/dri/by-path` resolves it.

**`host.yml`** — what this role is, for later commands to read:

```yaml
role: h2-amd
connection: local        # or the SSH target
verdict: supported
active_models: [qwen2.5-coder-7b]
installed_at: "..."
```

Then validate before touching the host:

```bash
cd "${CLAUDE_PLUGIN_ROOT}" && make validate
```

`validate` layers your `~/.lmstack/<role>/vars.yml` over the tracked defaults,
exactly as Ansible will, so it checks the configuration that is about to deploy
rather than the one in the repository. A failure here is a configuration error
you introduced. Fix it and re-run; do not proceed to Ansible with a failing
validator.

```bash
lmstack-log --host "$ROLE" --event plan --action config.written --status ok \
  --detail '{"files":["hosts.ini","vars.yml","host.yml"]}'
```

## Phase 3 — Secrets

The playbook drops `stack.env` from the example on its first run and never
overwrites it. So the sequence is: run `make up` once, let it stop at the secret
check, have the user fill the file, run again.

Tell the user exactly what to fill and how to generate it:

| Variable | Required on | Generate with |
|---|---|---|
| `LITELLM_MASTER_KEY` | both | `printf 'sk-%s\n' "$(openssl rand -hex 24)"` |
| `LITELLM_DB_PASSWORD` | both | `openssl rand -hex 24` |
| `HF_TOKEN` | h1-nvidia; optional on h2-amd | https://huggingface.co/settings/tokens |

The file is at `~/.lmstack/stack.env` **on the target host**, mode 0600. On a
localhost install that is the same tree as the configuration above, which is
correct — one machine, one `~/.lmstack`.

You do not read this file. You do not ask the user to paste its contents. If the
user pastes a key into the conversation anyway, tell them to rotate it.

## Phase 4 — Bootstrap

```bash
cd "${CLAUDE_PLUGIN_ROOT}" && make bootstrap HOST=<role>   # once per host
```

**This one needs sudo, so you hand it over.** When the probe reported
`"sudo": "password"` — normal on a local connection — Ansible cannot pipe the
password in, so the command to give the user is:

```bash
cd <plugin-root> && ansible-playbook \
  -i ~/.lmstack/<role>/hosts.ini \
  -e @~/.lmstack/<role>/vars.yml \
  hosts/<role>/ansible/00-bootstrap.yml -l <role> -K
```

If it reported `"sudo": "passwordless"` — normal on a remote host with a
configured SSH user — `make bootstrap HOST=<role>` works directly. Still show it
first; still wait for confirmation.

The pattern for any sudo step:

1. Print the exact command, in a fenced block, ready to copy.
2. Explain in one sentence what it will change — packages installed, groups
   added, files written.
3. Wait for the user to run it and paste the result.
4. Read the pasted output to decide whether to continue. Do not assume it
   succeeded because they said "done".

## Phase 5 — Run

```bash
cd "${CLAUDE_PLUGIN_ROOT}"
make up     HOST=<role>
make verify HOST=<role>
```

Neither needs sudo — you can run these yourself.

Expect `make up` to take a long time on a first run: it downloads model weights.
That is not a hang. Say so before you start it, so the user does not interrupt
it at minute eight.

Interpret failures against `${CLAUDE_PLUGIN_ROOT}/references/troubleshooting.md`
before reporting them. Log each stage:

```bash
lmstack-log --host "$ROLE" --event apply --action stack.up --status ok \
  --duration-ms "$MS" --models "slug-a"
```

On failure, use `--status failed --error-kind <kind> --error-msg "<one line>"`
with a `kind` from the troubleshooting reference, and **stop**. Do not continue
to verification against a stack that did not come up.

## Phase 6 — Wire the control host

Point the user's editor at the new endpoint.

Re-verify pi is installed — a lot has happened since Phase 0, and this may be a
different session:

```bash
command -v pi >/dev/null || echo "pi missing"
```

If missing, hand over `curl -fsSL https://pi.dev/install.sh | sh` and wait. Do
not skip this phase. The whole point is to land at a working editor.

```bash
cd "${CLAUDE_PLUGIN_ROOT}" && make pi-install
```

That merges lmstack's providers, statusline, and lean defaults into
`~/.pi/agent/`. It never overwrites a value the user has already set. The lean
defaults exist so pi starts in as few tokens of context as possible, leaving the
window for the user's work rather than pi's own scaffolding.

The user then fills `~/.pi/agent/extensions/.env` with the host URL and the
LiteLLM key. Same rule as Phase 3: you do not read that file and you do not ask
them to paste it.

Confirm with a real request, not by reading a config file back:

```bash
pi --list-models | grep lmstack
pi -p --provider lmstack-h2 --model qwen2.5-coder-7b "reply with the word ok"
```

If the host serves a model the extension does not advertise, `make validate`
fails with T0.10. Fix it by editing `${CLAUDE_PLUGIN_ROOT}/pi-config/extensions/`,
not the installed copy under `~/.pi/agent/` — that gets overwritten on the next
sync.

Claude Code and opencode reach the stack differently; see
`${CLAUDE_PLUGIN_ROOT}/pi-config/bridges/README.md`. Confirm before taking that
path — the default is to wire pi, because pi is the one editor that stays inside
the local-only story from end to end.

Finish by telling the user what they now have and that `/lmstack:harvest` is
what turns it into work.

## Logging

Every phase writes one line through `lmstack-log`, which redacts before it
writes. Fields are in `${CLAUDE_PLUGIN_ROOT}/references/stacklog-schema.md`.

- `--host` is the **inventory alias**, never an IP or hostname. The writer
  rejects anything with a dot in it.
- Never pass prompt text, completion text, or env file contents in `--detail`.
  Redaction is a backstop for mistakes, not a licence to log freely.
- Log failures too. A log containing only successes cannot answer the question
  it exists for.

## References

| File | Read it when |
|---|---|
| `${CLAUDE_PLUGIN_ROOT}/references/troubleshooting.md` | Any playbook or verification failure |
| `${CLAUDE_PLUGIN_ROOT}/references/model-catalog.md` | The user wants a model that is not in the catalog |
| `${CLAUDE_PLUGIN_ROOT}/references/stacklog-schema.md` | Writing a log line |

Repo-root `AGENTS.md` holds the invariants that apply to the whole repository,
including the model YAML contract.
