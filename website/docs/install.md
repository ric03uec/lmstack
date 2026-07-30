---
sidebar_position: 2
title: Install the skill
---

# Install the skill

This page is written to be read by a coding agent. If you are a person, the
short version is: paste the line below at your agent and it will do the rest.

> install the lmstack skill from https://ric03uec.github.io/lmstack/install

You do not need to clone anything first. The skill clones the repository itself,
after asking you where to put it.

## Instructions for the agent

The lmstack skill is a directory — `SKILL.md` plus `scripts/` and
`references/`. Installing it means putting that directory where the agent looks
for skills. Nothing is compiled, nothing runs at install time.

### 1. Pick the directory

| Agent | Skills directory |
|---|---|
| Claude Code | `~/.claude/skills` |
| opencode | `~/.config/opencode/skills` |
| pi | `~/.agents/skills` |

Install into the one the user actually runs. If more than one exists, ask rather
than installing into all of them.

### 2. Fetch it

This pulls only the skill directory out of the repository tarball — no clone, no
`git` on the user's machine, about 100 KB:

```bash
DEST=~/.claude/skills          # from the table above
mkdir -p "$DEST"
curl -fsSL https://github.com/ric03uec/lmstack/archive/refs/heads/main.tar.gz \
  | tar -xz -C "$DEST" --strip-components=2 lmstack-main/skills/lmstack
```

Re-running it overwrites the previous copy, which is how you upgrade.

### 3. Check it landed

```bash
ls ~/.claude/skills/lmstack     # SKILL.md, references, scripts
```

Four files matter: `SKILL.md`, `scripts/probe-host.sh`, `scripts/classify.py`,
and `scripts/stacklog.sh`. If `SKILL.md` is missing, the extraction failed —
report the error rather than retrying with different flags.

### 4. Hand back to the user

Tell them to start with:

> use the lmstack skill to give me a starting point

Do not start the install yourself unless they ask. The skill's first phase asks
where to clone the repository, and that is their decision.

## What the skill does first

Its Phase 0 finds the repository, or clones it. The resolution order is:

1. `$LMSTACK_REPO`, if the user exported one.
2. A path bound at install time, if it was installed from a clone.
3. `~/lmstack`, the default.

If none of those exist it asks where to clone, then runs one `git clone`. That
is the only git command in the whole skill — it will not stage, commit, or
checkout anything, on any repository, ever.

After that it checks the control host has `make`, `python3`, `jq`, and
`ansible-playbook`. Install the last one with `uv tool install ansible-core`.

See [The skill](skill) for what happens in the remaining phases, and what it
will refuse to do.

## Installing from a clone instead

If you are working on lmstack rather than just using it, install from the clone
so that edits to `skills/lmstack/` take effect on the next run:

```bash
git clone https://github.com/ric03uec/lmstack && cd lmstack
make skill-install                 # every agent directory you have
make skill-install AGENT=claude    # or one of claude | opencode | pi
make skill-list                    # show where it would write, without writing
```

This substitutes the clone's absolute path into the installed `SKILL.md`, so
Phase 0 resolves to it without asking. Moving or renaming the clone means
running the install again.

## Uninstalling

```bash
rm -rf ~/.claude/skills/lmstack
```

That leaves the clone and anything running on your GPU hosts alone. There is no
`make down`: stop a stack on the host it runs on, with
`docker compose -f ~/.lmstack/docker-compose.yml down`.
