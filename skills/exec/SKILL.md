---
name: exec
description: Run one harvested task on the local model stack. Creates a Forge — a tmux session with a live pi session writing code against the local GPU and a Claude Code session reviewing it — works in a git worktree, and ends with the judge opening a pull request. Use to execute a task that /lmstack:harvest queued, to check on a run in progress, or with --sweep to reconcile finished runs. Also handles worktree and session cleanup.
---

# exec

Run **one** harvested task on the local stack and end with a pull request the
user can review.

You are the orchestrator. You do not write code, you do not review code, and you
never call the model endpoint yourself. You create the Forge, hand it the brief,
watch, relay, and record. Everything else happens inside two live terminals that
the user can attach to and take over at any moment.

Modes:

| Invocation | What it does |
|---|---|
| `/lmstack:exec <key>` | run one task |
| `/lmstack:exec` | show the queue and the state of any live Forge |
| `/lmstack:exec --sweep` | reconcile finished runs; clean up |

## Ground rules

1. **You never write the code and you never review it.** If you find yourself
   editing a file in the worktree, the run has already failed — stop and say so.
   The point of the exercise is that the local GPU does the work.
2. **One Forge at a time.** Two forges sharing a repository produce interleaved
   rebases and confusing PRs. Refuse to start a second while one is live.
3. **Never both agents at once.** They share one worktree. Send to `lm-judge`
   only when `lm-exec` is idle, and the reverse. Concurrent edit-and-review in
   one working directory produces a review of a half-written tree.
4. **Multi-line text goes in through the paste buffer.** `lmstack-forge paste`,
   never `send-keys "$(cat …)"`. See [Delivering the brief](#step-4--the-brief).
5. **Never touch `main`, never merge.** The judge rebases, pushes a branch and
   opens a PR. The merge is the user's, always.
6. **Sanitize anything that came from the forge before it reaches a terminal.**
   Issue text and judge findings both quote attacker-influenceable content.
7. **Do not escalate mid-run.** If an agent asks a question, answer it from
   repository conventions and count it as an intervention. Bring the user in
   only when the run is over or genuinely stuck.

## Step 1 — Accept or refuse the task

```bash
lmstack-task get --host "$ROLE" --key "$KEY"
```

Refuse, with the reason, if:

| Condition | Why |
|---|---|
| no record | it was never harvested — run `/lmstack:harvest` first |
| `tier` is `park` | harvest judged the scope too large; it needs a human split |
| `tier` is `TRAP` | following it literally causes harm. Never dispatch. Show `verdict_reason` |
| `tier` is `T2` | decompose into a numbered task chain first, then dispatch that |
| `status` is not `queued` | another run owns it, or it is already done |
| another forge is live | one at a time — `lmstack-forge status` |

A `TRAP` refusal is not a formality. Show the recorded reason and stop; do not
offer to run it anyway.

**Re-check staleness.** The record's `staleness` is context, not a cache — `HEAD`
has moved since harvest. If the work now looks already done, say so and stop
rather than dispatching a no-op.

## Step 2 — Worktree

```bash
KEY="ric03uec__lmstack#42"
SLUG="${KEY//[#.]/-}"                    # ric03uec__lmstack-42
WT="$HOME/.lmstack/worktrees/$SLUG"
RUN="$HOME/.lmstack/runs/$SLUG"

cd "$REPO_PATH"
git worktree add "$WT" -b "lmstack/$SLUG" main
```

This is the one place a skill runs a mutating git command, and it is confined to
a worktree and a branch it created itself. It never touches the user's checked-out
branch, their index, or their stash.

If the user's repository has no `main` — check, do not assume — use its default
branch from `gh repo view --json defaultBranchRef`.

## Step 3 — Launch the Forge

Ask the host which model it serves rather than hardcoding one. Hosts do not
share an alias — one serves a Qwen coder, another serves Hermes for its tool
calling — so a fixed `--model` is wrong on one of them and fails as a LiteLLM
`400` that reads like a broken stack.

**Pick the largest host that answers, not the nearest one.** Loopback-first is
right for `lmstack-ask`, where the cost of a weak answer is one bad paragraph.
It is wrong here: a Forge runs unattended for an hour and the exec agent has
edit and bash. Measured on this loop, an 8B at 33k context could not complete a
two-file docs edit across three attempts — it narrated tool calls it never made,
then confabulated tasks the brief did not contain. The same brief on a 27B at
262k landed both edits and a correct commit message on the first try, using 10%
of its window. Set `PROVIDER` to the biggest stack that is reachable.

```bash
PROVIDER="vllm-inx"
MODEL="$(lmstack-ask -P "$PROVIDER" --print-model)"
PROVIDER_EXT="$HOME/.pi/agent/extensions/$PROVIDER.ts"

lmstack-forge create --key "$KEY" --worktree "$WT" --run-dir "$RUN" \
  --exec-cmd  "pi --provider $PROVIDER --model $MODEL --no-context-files --no-extensions -e $PROVIDER_EXT --tools read,edit,write,bash,grep,ls --append-system-prompt $WT/AGENTS.md" \
  --judge-cmd "claude --dangerously-skip-permissions"
```

**`-e $PROVIDER_EXT` is load-bearing.** The provider *is* a pi extension, so
`--no-extensions` alone removes the thing you are trying to talk to and pi exits
with `Unknown provider`. Re-add it by path; `-e` still works under
`--no-extensions`.

Two windows, `lm-exec` and `lm-judge`, both live and attachable. The user can
`tmux attach -t lmstack-<slug>` and type into either at any point; that is a
feature of the design, not a debugging escape hatch.

**`--no-context-files` with an explicit `--append-system-prompt` is deliberate.**
pi's default discovery walks up from the working directory and collects the
*user's* global `~/.claude/CLAUDE.md` and `~/.agents/` rules — their personal
working style, their employer's conventions, instructions for unrelated projects.
None of that describes the repository being worked on, and on a 7B every token
spent on it is a token not spent on the task. Load what the repository declares
about itself; load nothing else.

**`--no-extensions` and the `--tools` allowlist are not tidiness.** The user's
installed pi extensions each register tool schemas, and those schemas go into
every request. Measured on h2-amd: with extensions discovered, the first turn
sent **17,529 prompt tokens** against a 33k window — 53% of the context gone
before the model read the brief, and 16k of that was tool schema. Hermes 3 8B
under that load stopped emitting `<tool_call>` tags and instead *narrated* tool
use, printing a plausible `$ touch <file>` and reporting success while the
worktree stayed empty. Nothing failed loudly; the run simply produced no diff.

Load only the tools the work needs. If a task genuinely needs an extension,
name it with `-e <path>` rather than re-enabling discovery.

**Trust model for the judge.** It runs with `--dangerously-skip-permissions`, so
it rebases, pushes and opens PRs unattended. That is acceptable only because the
worktree is local, the branch is disposable, and the PR still needs the user's
merge. It is *not* a statement that the judge's inputs are trusted — both
model-authored code and issue text reach it. Two consequences: never widen the
judge's reach to `main`, and never let it merge.

Then claim the task:

```bash
lmstack-task set --host "$ROLE" --key "$KEY" --status running
```

## Step 4 — The brief

Write `$RUN/brief.md`, then deliver it as **one** message:

```bash
lmstack-forge paste --key "$KEY" --window lm-exec --file "$RUN/brief.md"
```

`lmstack-forge paste` uses `load-buffer` + `paste-buffer`. Never assemble this
yourself with `send-keys "$(cat …)"`: `send-keys` converts every embedded newline
into a Return, so the brief submits line by line and the model starts working on
a fragment before it has read the scope fence.

The brief:

```markdown
Work on <issue url> in this worktree.

## Scope fence
Touch ONLY: <explicit file list>
Do NOT touch: <explicit exclusions, including anything the staleness check found already done>

## Tasks
1. <one concrete change, naming the file it lands in>
2. ...

## Pattern to follow
<path to the in-repo precedent> — mirror its structure.

## Rules
- Commit locally. Do NOT push. Do NOT open a PR.
- Do NOT run `gh` at all. Not close, not comment, not label, not edit.
- Do not add features, refactors, or abstractions beyond the tasks above.
- If a task turns out to be already done, stop and say so — do not invent work.
- When finished, run: echo done > <the run dir>/done
```

**Name `gh` explicitly, and do not settle for "do not open a PR".** A model that
has been told not to push reads closing the issue as a different, helpful act. On
the first run of this loop against a 27B, the exec agent finished its commit and
went straight to `gh issue close`, which succeeded — the issue was closed on the
user's real repository before anything had been reviewed. `bash` is in the tool
allowlist because the tasks need it, and `gh` is authenticated on the control
host, so the only thing standing between the exec agent and the user's forge is
this line of the brief.

**Fence hard.** Every prior failure of this loop came from the model going wide,
not from it being unable to make the change. A brief that says "find where X is
handled" has already lost: search radius is where these models degrade fastest.

**Expand `$RUN` when you write the brief.** The sentinel goes in the run
directory, not the worktree: an untracked `.lmstack-done` in the repository
would trip the judge's own scope fence, and nothing this skill generates is
allowed to land in the user's tree.

The sentinel is a **liveness hint only, never proof of correctness.** The
documented failure mode of small models is claiming completion on unfinished
work. Correctness is the judge's call, always.

## Step 5 — Watch

```bash
lmstack-forge idle --key "$KEY" --window lm-exec
```

Exits 0 when the window has been byte-identical across two captures ~90 seconds
apart. Interactive windows give no exit code, so this inference is all there is.

**Expect this to be slow.** A 7B working through a multi-file change runs for
minutes to hours. That is the design — the work happens in the background on
hardware that was otherwise idle. Do not poll faster to feel busy, and do not
conclude a run has hung because it has been quiet for ten minutes.

If the window is idle but the tail shows the agent **asking a question**, answer
it from repository conventions and send the answer with `lmstack-forge type`.
Count it as an intervention. Do not bring the user in mid-run.

## Step 6 — Judge rounds

When `lm-exec` is idle, and only then:

```bash
lmstack-forge type --key "$KEY" --window lm-judge \
  --line "Read ${CLAUDE_PLUGIN_ROOT}/skills/exec/judge.md and follow it for $KEY, round 1. The brief is at $RUN/brief.md. Write your findings to $RUN/judge-1.md."
```

Wait for `lm-judge` to go idle, then read `$RUN/judge-<n>.md`.

| Verdict | Do this |
|---|---|
| `SATISFIED` | go to [Step 7](#step-7--the-pr) |
| `REVISE` | relay the findings into the **live** `lm-exec` session and loop |
| `STUCK` | go to Step 7 anyway, flagged |

Relaying a revision:

```bash
lmstack-sanitize < "$RUN/judge-1.md" > "$RUN/judge-1.clean.md"
lmstack-forge paste --key "$KEY" --window lm-exec --file "$RUN/judge-1.clean.md"
```

Sanitize first. The judge reads issue text, and anything it quotes verbatim would
otherwise ride straight into the exec window's terminal.

**Relay into the live session. Do not restate the brief.** The pi session still
holds full context from Step 4; repeating it wastes the context window that the
remaining work needs.

**Ceiling: three rounds.** If round 3 still fails, the PR opens anyway, flagged
stuck, with each unresolved item called out. Never block a run waiting for the
user — a Forge that sits forever holding a worktree is worse than an honest PR
that says what is unfinished.

## Step 7 — The PR

The **judge** opens it. The model that wrote the code is the wrong one to certify
it; that is exactly the failure this two-window split exists to prevent.

```bash
WALL="$(lmstack-ledger --wall-only --started-file "$RUN/started")"

lmstack-forge type --key "$KEY" --window lm-judge \
  --line "Open the PR for $KEY. Rebase on origin/main first. Wall time $WALL, judge rounds <n>, human interventions <n>. Include a Callouts section. Do not create any labels."
```

**Rebase before opening.** Long-lived branches drift and silently regress content
someone else changed. If the repository has a PR template, use it verbatim.

Then record the outcome:

```bash
lmstack-task set --host "$ROLE" --key "$KEY" --status in-review --pr "<url>"

lmstack-ledger --key "$KEY" --host "$ROLE" --tier T1 --shape doc-mirror-sync \
  --judge-rounds 2 --interventions 0 --outcome pr-opened --pr 43 \
  --started-file "$RUN/started"
```

Count judge rounds and interventions **honestly**. An under-reported round count
makes a run look cheaper than it was, which defeats the only purpose the ledger
has. `--outcome pr-opened-stuck` when the ceiling was hit.

Leave the session and worktree up. Reviewers ask for changes, and the live pi
session still holds the context needed to make them.

## `--sweep` — reconcile

Nothing polls for merges. The sweep is what returns tasks to a clean state. For
every task in `running` or `in-review`:

```bash
lmstack-task list --host "$ROLE" --status running
lmstack-task list --host "$ROLE" --status in-review
lmstack-forge status
```

| Observed | Action |
|---|---|
| `in-review`, PR merged | mark `merged`; kill session; remove worktree and branch |
| `in-review`, PR closed unmerged | mark `failed`; record why; clean up |
| `in-review`, PR still open | leave alone |
| `running`, session live | leave alone; report the current round |
| `running`, **no** live session | stale claim from a crashed run — return to `queued` |

That last row is the one that matters. Without it, a closed terminal strands a
task as permanently in progress and every later harvest silently skips it.

```bash
lmstack-forge kill --key "$KEY"
git -C "$REPO_PATH" worktree remove "$WT"          # --force if dirty
git -C "$REPO_PATH" branch -D "lmstack/$SLUG"      # only after a merge
```

Deleting a branch is destructive and the sweep does it unattended, so do it
**only** on the merged path, where the commits are already in `main`. On any
other outcome, leave the branch and say where it is.

## References

| File | Read it when |
|---|---|
| `${CLAUDE_PLUGIN_ROOT}/skills/exec/judge.md` | The judge's standing contract; you point it here rather than restating it |
| `${CLAUDE_PLUGIN_ROOT}/references/troubleshooting.md` | The stack is not answering |
| `${CLAUDE_PLUGIN_ROOT}/references/stacklog-schema.md` | Writing a log line |
