---
sidebar_position: 2
title: Install
---

# Install

lmstack ships as a Claude Code plugin. That is the only supported way to install
it — there is no curl-pipe-sh, no clone step, and nothing to build.

```
/plugin marketplace add ric03uec/lmstack
/plugin install lmstack@lmstack
```

The first command registers this repository as a marketplace; the second installs
the plugin from it. Restart is not required — the commands appear immediately.

## Prerequisites

Two of these are needed before the stack can come up. The plugin checks and tells
you which is missing rather than failing partway through a bring-up.

| Tool | Check | Install with |
|---|---|---|
| **Ansible** | `command -v ansible-playbook` | `uv tool install ansible-core` |
| **tmux** | `command -v tmux` | Your package manager (`apt install tmux`, `brew install tmux`) |
| `git`, `python3`, `jq` | `command -v` each | Usually present already |

Ansible is the one usually missing. Install it with `uv tool install
ansible-core`, not pipx and not the system package manager — the distribution
packages lag far enough behind that the playbooks fail on collection versions.

**pi** is optional and only needed for `/lmstack:exec`, which runs a local model
in a live editor session. Install it with `curl -fsSL https://pi.dev/install.sh |
sh`. The other three commands do not need it.

## What you get

| Command | What it does |
|---|---|
| `/lmstack:analyze [target]` | Probes the hardware — locally or over SSH — and reports what fits, before anything is installed |
| `/lmstack:install [target]` | Brings the stack up behind one OpenAI-compatible endpoint |
| `/lmstack:harvest <source>` | Reads a backlog and classifies which items the local stack can attempt |
| `/lmstack:exec <key>` | Runs one of them and ends with a pull request |

Start with `/lmstack:analyze`. It reads the GPU, does the VRAM arithmetic, and
tells you which models fit. Nothing is written and nothing is installed, so it is
safe to run against a machine you have not decided about yet.

Pass an SSH target to point either command at a remote box:

```
/lmstack:analyze devashish@h1-nvidia
```

## Where things get written

Everything generated lands under `~/.lmstack/`, keyed by host role:

```
~/.lmstack/
├── <role>/
│   ├── vars.yml          host variables the playbooks read
│   ├── stacklog/         append-only change log
│   └── tasks/            the harvested task queue
├── ledger.jsonl          one line per completed exec run
└── runs/                 per-run briefs, transcripts, judge findings
```

Nothing is written into a repository — not the lmstack clone, not yours. The one
exception is `/lmstack:exec`, which creates a git worktree and a branch it made
itself, and never touches your checked-out branch, index, or stash.

Secrets are never read back. When the install needs a value from an env file it
prints the command for you to run, and the change log redacts anything that looks
like a key before it is written.

## Working on lmstack itself

Clone it and run `make plugin-dev`, which starts Claude Code with the working
tree loaded as the plugin. Edits to a skill take effect in the next session with
nothing to reinstall — skills resolve their own location at runtime through
`${CLAUDE_PLUGIN_ROOT}`, so there is no path to bind and nothing to re-template.

Run `make test` before you push. It needs no host, no GPU, and no network.

## Uninstalling

```
/plugin uninstall lmstack@lmstack
```

That leaves `~/.lmstack/` and anything running on the GPU hosts alone. A stack is
stopped on the host it runs on:

```bash
docker compose -f ~/.lmstack/docker-compose.yml down
```
