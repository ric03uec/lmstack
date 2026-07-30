---
sidebar_position: 2
title: Install the skill
---

# Install the skill

This page is addressed to a coding agent. If you are a person: type
*install the lmstack skill from https://ric03uec.github.io/lmstack/install*
in Claude Code, opencode, or pi, and your agent will do what follows.

---

## What you are installing

The lmstack skill: a directory containing `SKILL.md`, a `scripts/` folder, and a
`references/` folder. About 100 KB. Nothing compiles, nothing executes at
install time, and it adds no dependencies to the machine.

The source is the `skills/lmstack` directory of
[github.com/ric03uec/lmstack](https://github.com/ric03uec/lmstack). Take the
whole directory, not just `SKILL.md` — the skill reads the other files while it
works, and a copy missing them fails halfway through a host bring-up.

## Where it goes

Install into the skills directory of the agent you are running inside:

| If you are | Install into |
|---|---|
| Claude Code | `~/.claude/skills/lmstack` |
| opencode | `~/.config/opencode/skills/lmstack` |
| pi | `~/.agents/skills/lmstack` |

If more than one of those directories exists, that does not mean the user runs
more than one agent. Install into your own and say so. If you genuinely cannot
tell which you are, ask rather than installing into all three.

## How to get it

Do not clone the repository. The skill clones it later, at a location the user
chooses, and a clone made now would be in the wrong place and unused.

Fetch the repository archive at
`https://github.com/ric03uec/lmstack/archive/refs/heads/main.tar.gz` and extract
only the `lmstack-main/skills/lmstack` path from it into the directory above,
dropping the two leading path components so the result is `lmstack/` and not
`lmstack-main/skills/lmstack/`.

Use whatever tool you have. If `curl` and `tar` are both present, one pipeline
does it; if the environment blocks outbound network access, say so and stop
rather than trying alternative hosts or mirrors.

Extracting again over the top is how the skill is upgraded, so a directory that
already exists is not an error.

## Confirm it worked

The installed directory must contain `SKILL.md`, `scripts/probe-host.sh`,
`scripts/classify.py`, `scripts/stacklog.sh`, and a `references/` folder with
four markdown files.

If `SKILL.md` is missing, the extraction failed. Report the actual error. Do not
retry with different flags, and do not reconstruct the skill by hand from this
page — a hand-written `SKILL.md` will be missing the rules that stop it doing
damage on the user's machine.

## Then stop

Tell the user the skill is installed and that they can start it with:

> use the lmstack skill to give me a starting point

Do not begin the installation yourself unless they ask. The skill's first
question is where to clone the repository, and that is theirs to answer.

## What the skill does when it starts

Its Phase 0 looks for the lmstack repository in `$LMSTACK_REPO`, then at a path
bound at install time if it was installed from a clone, then at `~/lmstack`. If
none exist it asks where to clone and runs one `git clone`.

That is the only git command in the skill. It will not stage, commit, checkout,
or stash anything, in any repository, at any point.

It then checks the control host has `make`, `python3`, `jq`, and
`ansible-playbook`. The last is the one usually missing; it is installed with
`uv tool install ansible-core`, not pipx and not the system package manager.

[The skill](skill) describes the remaining phases and what it refuses to do.

## Installing from a clone instead

For someone changing lmstack rather than using it. Clone the repository and run
`make skill-install`, optionally with `AGENT=claude`, `AGENT=opencode`, or
`AGENT=pi` to restrict it to one. `make skill-list` prints where it would write
without writing anything.

That install substitutes the clone's absolute path into the copy it writes, so
Phase 0 resolves to that clone and the skill runs against local edits rather
than fetching its own copy. Moving or renaming the clone breaks the binding, and
the fix is to run the install again.

## Uninstalling

Delete the `lmstack` directory from the agent's skills directory. That leaves
the clone and anything running on the GPU hosts alone — a stack is stopped on
the host it runs on, with `docker compose -f ~/.lmstack/docker-compose.yml down`.
