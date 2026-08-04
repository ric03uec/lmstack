# lmstack v2 — the plugin

Status: **approved, not yet implemented.**

`PLAN.md` describes v1 — the Ansible stack and the single interactive installer
skill — and that work is shipped. This document supersedes the *product surface*
only. The playbooks, the model contract, the validator, and the render tests all
survive unchanged; they stop being the thing the user touches and become the
thing the plugin drives.

## 0. Prior art — read this first

`/lmstack:exec` is **not a new design**. It is a generalisation of
`../clawrium/.claude/skills/clawctl-lmwork/SKILL.md`, a 650-line skill that has
run this exact loop many times against a real backlog. Its ledger
(`../clawrium/.itx/lmwork-ledger.jsonl`) records the results, and those numbers
set the expectations in this document.

What the ledger actually says:

| Issue | Shape | Judge rounds | Wall | Interventions | Outcome |
|---|---|---|---|---|---|
| #418 | middleware-add | 1 | — | — | PR opened |
| #754 | symbol-extract | 3 | 558 min | 2 | PR opened |
| #122 | cli-flag-add | 1 | 31 min | 2 | **merged** |

Three things follow, and they are not negotiable design inputs — they are
measurements:

1. **Runs take between half an hour and most of a day.** This is a background
   process. It is not interactive-fast and is not meant to be.
2. **Human interventions are normal.** Two or three per run is the observed
   floor, not a failure. The loop is judged on whether it beats doing the issue
   by hand, not on being untouched.
3. **Judge rounds go to three.** A single-shot verdict is not what makes this
   work.

Everything in §7 that looks arbitrary is there because clawrium hit the failure
it prevents.

**What does not transfer.** clawrium runs a **27B** (`Qwen3.6-27B` on `inx`);
lmstack's floor is a **7B at 8 GB**. clawctl-lmwork's classification criteria are
calibrated to the larger model and will be too generous for a 7B. It also depends
on `atx` (a review tool lmstack does not have) and on a rich pre-existing GitHub
label vocabulary that a stranger's repository will not have. §6 and §7 say where
each of those is replaced.

## 1. What the product is

A user with an idle GPU installs one plugin and gets four commands:

| Command | Does |
|---|---|
| `/lmstack:analyze [target]` | Tells them whether their hardware can run a stack, and which one. |
| `/lmstack:install [target]` | Installs it, and records the host's configuration under `~/.lmstack/`. |
| `/lmstack:harvest <source>` | Reads a backlog and works out which items the stack could actually attempt. |
| `/lmstack:exec <key>` | Attempts one, on the local model, and opens a PR if it survives review. |

The through-line is the GPU doing work. Every design choice below is subordinate
to that: if a step burns cloud tokens where local tokens would do, it is wrong.

Claude Code is the only supported harness. Anything else — opencode, a bare
Makefile, raw `ansible-playbook` — is something a user can extract from the repo
themselves, not something this plugin supports. See [Backlog](#11-backlog).

## 2. Terminology

**Orchestrator** — the Claude Code session the user typed `/lmstack:exec` into.
It selects the task, builds the forge, types into both windows with
`tmux send-keys`, and watches them with `tmux capture-pane` on a slow poll.

It **never calls the local stack directly** — no `curl` to LiteLLM, no API calls.
It always drives a pi harness and types into it, exactly as a person would. That
is the entire point of going through tmux.

It also does **not** write source code, run tests, or review diffs. `lm-exec`
writes; `lm-judge` reviews. The one job the orchestrator keeps for itself is the
staleness check in §6, because delegating that produces confident wrong answers.

**Forge** — one tmux session, one task, **two windows** (not split panes):

- **`lm-exec`** — an interactive `pi` session on the *local* model. Does the work.
- **`lm-judge`** — an interactive `claude` session on the user's default model.
  Reviews, and opens the PR when satisfied.

Both windows must look and behave exactly as if the user had started them by
hand, because at any moment the user may attach and take over. A headless run
that produces the same artifact is not a substitute: it cannot be joined.

**Serialization rule.** Both windows share one worktree. **Never have both agents
active at once.** Send to `lm-judge` only after `lm-exec` is idle, and the
reverse. Concurrent edits and review in one working directory produce garbage
reviews.

## 3. Decisions

| Decision | Rationale |
|---|---|
| **One role, one host.** State keyed by role (`h2-amd`), not an alias. | There is never more than one machine per role. |
| **Plugin is the only supported entry point.** | Namespaced commands need a plugin; a second path doubles surface for no user. |
| **Skills, not commands, inside the plugin.** | `skills/<name>/SKILL.md` yields `/lmstack:<name>` and keeps per-command `references/`. |
| **Windows, not panes.** | Directly from clawctl-lmwork. Panes fight over width and scrollback; windows do not. |
| **The judge opens the PR.** | "The model that wrote the code is the wrong one to certify it" — the precise failure that closed clawrium PRs #883 and #879. |
| **Up to 3 judge rounds, then ship anyway.** | **Changed from the earlier "no retry" call.** The ledger shows round 3 being reached and still producing a merged PR. Exhausting the ceiling opens the PR flagged as stuck rather than blocking on the user. |
| **Slow is correct.** | Runs are 30 min to 9 h. Background work. Optimising throughput is explicitly out of scope for v2. |
| **Interventions are expected.** | 2–3 per run observed. The loop is measured against doing it by hand, not against being untouched. |
| **No spike needed.** | The mechanism is proven in clawrium. Phase 3 ports it; it does not prototype it. |
| **Task verdicts live in `~/.lmstack/`, not in GitHub labels.** | clawctl-lmwork persists verdicts as labels because clawrium already has that vocabulary. A stranger's repo does not, and the plugin must never create labels. |
| **Run artifacts stay outside the user's repo.** | clawrium commits `.itx/<N>/` into the PR. lmstack keeps briefs and transcripts in `~/.lmstack/runs/<key>/` — writing scaffolding into someone else's repository is intrusive. |

## 4. Plugin layout

The repository root *is* the plugin root.

```
lmstack/
├── .claude-plugin/
│   ├── plugin.json          # name: lmstack  → /lmstack:*
│   └── marketplace.json     # the repo is its own marketplace
│
├── skills/
│   ├── analyze/SKILL.md   + references/ scripts/
│   ├── install/SKILL.md   + references/ scripts/
│   ├── harvest/SKILL.md   + references/ scripts/
│   └── exec/SKILL.md      + references/ judge.md scripts/
│
├── bin/                     # on the Bash tool's PATH while enabled
│   ├── lmstack-ask         # moved from pi-config/bin/
│   └── lmstack-forge       # create / send / watch / sweep / tear down
│
├── hosts/  inventory/  pi-config/  tests/  Makefile   # v1, now internal
└── website/
```

`bin/` being on PATH **deletes the path-binding problem**. v1 substituted an
absolute repo path into the installed `SKILL.md` because the skill ran from
`~/.claude/skills/` and could not find the playbooks. A plugin knows its own
root. `skills/install.sh` and test T6.3 both go away — and `skills/install.sh`
must go regardless, since it collides with the new `skills/install/` directory.

`skills/exec/judge.md` is the judge's standing contract, mirroring
`clawctl-lmwork/judge.md`. The orchestrator points the judge at it by path rather
than restating it every round.

## 5. State layout

```
~/.lmstack/
├── stack.env                       # the one secrets file
├── h2-amd/
│   ├── host.yml                    # role, connection, verdict, active_models
│   ├── probe.json                  # last analyze result
│   ├── hosts.ini                   # generated Ansible inventory
│   ├── vars.yml                    # passed as -e @… , highest precedence
│   ├── stacklog/YYYY-MM.jsonl
│   └── tasks/<owner>__<repo>/<key>.json
├── runs/<key>/
│   ├── brief.md                    # what gets pasted into lm-exec
│   ├── judge-<round>.md            # each verdict
│   ├── started                     # UTC stamp, written at forge creation
│   ├── exec.log · judge.log        # live transcripts via tmux pipe-pane
│   └── session/                    # pi session dir, pinned here
├── worktrees/<key>/
└── ledger.jsonl                    # cross-run, cross-repo. see §8
```

The repository is never written to. v1 edited `inventory/hosts.ini` and the
tracked `hosts/<role>/ansible/vars.yml` in place; v2 generates both under
`~/.lmstack/<role>/` and passes them in. Ansible extra-vars take highest
precedence, so the tracked `vars.yml` remains the default.

`stack.env` moves to `~/.lmstack/stack.env` — flat, not `~/.lmstack/env/`. A file
and the per-role directories coexist in one parent; on a localhost install the
control host and target host share this tree, which is correct.

The `started` stamp is a **file**, not `tmux display-message -p
'#{session_created}'`. A session recreated mid-run resets its own creation clock
and would silently undercount the run.

### Task record

```json
{
  "key": "ric03uec__lmstack#42",
  "url": "https://github.com/ric03uec/lmstack/issues/42",
  "title": "...",
  "repo_path": "/home/user/workspace/lmstack",
  "host_role": "h2-amd",
  "tier": "T1",
  "complexity": "s",
  "shape": "doc-mirror-sync",
  "staleness": "DISPATCH",
  "verdict_reason": "single file named in the brief; in-repo precedent at …",
  "status": "queued",
  "harvested_at": "2026-08-03T…Z"
}
```

`tier` ∈ `T1 | T2 | park | TRAP`. `status` ∈ `queued | running | in-review |
merged | failed | cleaned`. Harvest owns `tier`; exec owns `status`.

## 6. `analyze`, `install`, `harvest`

### `/lmstack:analyze [target]`

Unchanged in substance from v1 Phases 1–3. `probe-host.sh` runs locally or over
SSH-on-stdin; `classify.py` turns the probe plus the catalog into a verdict with
its arithmetic shown. Writes only `~/.lmstack/<role>/probe.json`. Stops on an
unsupported host with a reason and a remedy. No CPU fallback.

### `/lmstack:install [target]`

v1 Phases 0 and 4–7, with configuration generated into `~/.lmstack/<role>/`
rather than edited into the repo. Every v1 ground rule survives: diff before
write, never run git, never read or echo a secret, hand every sudo command to the
user, log each phase, stop on an unsupported host. Ends by wiring pi.

### `/lmstack:harvest <source>`

Reads the **first 10 open items by default**. When handed a project URL, ask
whether the user means issues or PRs before spending `gh` calls on a guess.

**Sanitize first.** Issue titles and bodies are attacker-influenceable — anyone
can file an issue. Strip bidi and zero-width codepoints before echoing them into
a terminal, a brief, or a log, so a crafted title cannot reorder what the
orchestrator appears to have said. Write the codepoints as `\uXXXX` escapes,
never as literal characters: a filter containing the invisible characters it
strips is self-erasing. Do not use `tr -d` — these are multi-byte in UTF-8 and a
byte-range delete corrupts the text instead of cleaning it.

**Step 1 — staleness check. Never delegate this.** Backlogs contain issues that
are already fixed, point at orphaned modules, or whose literal instructions would
reintroduce a bug. A model asked "is this already fixed?" answers confidently and
wrongly, so the orchestrator checks against current `HEAD` itself: do the cited
files and symbols still exist; is the module still imported by anything; has the
behaviour shipped under another name; does the change contradict a documented
contract.

| Verdict | Action |
|---|---|
| `DISPATCH` | accurate as written → classify |
| `RESCOPE` | partly done — the brief fences off the completed parts → classify |
| `CLOSE-REC` | already delivered; record the evidence, dispatch nothing |
| `TRAP` | following it literally would cause harm; never dispatch |

**Step 2 — classify.** Four checks, inherited from clawctl-lmwork where they were
derived from 20 prior runs:

1. Does the issue carry a real definition of done, or can the orchestrator write one?
2. Can the orchestrator name **every** file to change in the brief? Search radius
   is where these models degrade fastest — they pattern-match well and explore badly.
3. Is there an in-repo precedent to copy, **by path**? Every merged clawrium PR
   was a pattern-match.
4. Does sign-off require a real host the model cannot reach?

All four favourable → **T1**, dispatch as-is. One to three weak → **T2**,
decompose into a numbered task chain first. Scope itself too large → **park**.

These thresholds are calibrated for a 27B. On a 7B they are optimistic, and the
ledger in §8 is how they get corrected. Until there is lmstack data, err toward
`park`.

Verdicts persist in the task record, so a re-run reads instead of re-scanning.
**Staleness does not persist** — `HEAD` moves between passes, so the staleness
check re-runs every time. Only classification is cached. A verdict is a cached
*judgment*, never a cached fact about the code.

**If nothing fits, say so plainly.** "No tasks in the first 10 items fit what this
stack can attempt" is a complete and honest answer. Do not pad it, do not lower
the bar to produce a result, and do not apologise for the hardware.

## 7. `/lmstack:exec <key> [--yolo]`

```
  /lmstack:exec ric03uec__lmstack#42
        │
        ▼
 ┌────────────────────────────────────────────────────────────────┐
 │ ORCHESTRATOR — your Claude Code session                         │
 │   1. task is T1 and `queued`, else refuse                       │
 │   2. take lock ──── one forge at a time                         │
 │   3. git worktree add ~/.lmstack/worktrees/<key>                │
 │   4. write brief.md · write `started` stamp                     │
 │   5. lmstack-forge create <key>                                 │
 │   6. paste-buffer the brief ──▶ lm-exec, then WATCH             │
 │                                                                 │
 │   never curls LiteLLM. never writes code. never reviews.        │
 │   talks to the windows only by typing into them.                │
 └───────────┬──────────────────────────────────┬─────────────────┘
             │ load-buffer + paste-buffer       │ capture-pane
             │ (never send-keys for multi-line) │ every ~90s
             ▼                                  ▲
 ┌───────────────────────────────────────────────────────────────┐
 │ FORGE — tmux session `lmstack-<key>`    two WINDOWS, both live │
 │                                                                │
 │  window: lm-exec              │  window: lm-judge              │
 │  ───────────────              │  ────────────────              │
 │  $ pi --provider lmstack-h2   │  $ claude --dangerously-       │
 │       --model qwen2.5-coder-7b│        skip-permissions        │
 │       --tools <allowlist>     │    (user's default model)      │
 │       --no-context-files      │                                │
 │       --append-system-prompt  │   ▌ idle at the prompt         │
 │           <wt>/AGENTS.md      │            ⋮                   │
 │       cwd = worktree          │            ⋮                   │
 │                               │            ⋮                   │
 │   ▌ interactive · attachable  │            ⋮                   │
 │   ▌ user may type any time    │            ⋮                   │
 │          │                    │            ⋮                   │
 │          ▼                    │            ⋮                   │
 │   LiteLLM :4000               │            ⋮                   │
 │          │                    │            ⋮                   │
 │          ▼                    │            ⋮                   │
 │   llama.cpp ──▶ GPU  ★        │            ⋮                   │
 │          │                    │            ⋮                   │
 │          ▼ commits LOCALLY    │            ⋮                   │
 │   (never pushes, never PRs)   │            ⋮                   │
 │          │                    │            ⋮                   │
 │   ┌──────┴───────┐            │            ⋮                   │
 │   │ IDLE?        │            │            ⋮                   │
 │   │ capture-pane │            │            ⋮                   │
 │   │ identical x2 │────────────┼──▶ orchestrator sends          │
 │   │ + prompt     │            │    "review round N"            │
 │   └──────────────┘            │            │                   │
 │   ▲                           │            ▼                   │
 │   │                           │      ▌ judge reviews diff      │
 │   │  REVISE (max 3 rounds)    │            │                   │
 │   │  relay findings into the  │      ┌─────┴─────┐             │
 │   └──the LIVE pi session ─────┼── REVISE     SATISFIED         │
 │      (context intact —        │                  │             │
 │       do NOT restate brief)   │                  ▼             │
 │                               │      rebase on origin/main     │
 │                               │      push · gh pr create       │
 │                               │                                │
 │  ceiling hit ──▶ PR opens anyway, flagged stuck. never block.  │
 │  tmux pipe-pane -o ──▶ exec.log · judge.log                    │
 └───────────────────────────────────┬────────────────────────────┘
                                     │
                                     ▼
                          PR ──▶ issue #42 · status `in-review`
                                     │
                          user merges (nothing polls)
                                     │
                     /lmstack:exec --sweep   ← reconciles
                     └──▶ worktree · branch · session removed
```

`★` is the acceptance test for the whole product. If the GPU is idle there,
nothing else in this document matters.

### Launching the windows

```bash
git worktree add "$WT" -b "lmstack/<key>" main

tmux new-session -d -s "$S" -n lm-exec -c "$WT"
tmux send-keys -t "$S:lm-exec" "pi --provider lmstack-h2 --model qwen2.5-coder-7b …" Enter

tmux new-window -t "$S" -n lm-judge -c "$WT"
tmux send-keys -t "$S:lm-judge" "claude --dangerously-skip-permissions" Enter
```

`--no-context-files` plus an explicit `--append-system-prompt` is deliberate.
pi's default discovery walks up and collects the *user's* global
`~/.claude/CLAUDE.md` and `~/.agents/` rules, which describe the user's working
style and have nothing to do with the repository being worked on. The rules that
belong in a small model's context are the ones the repository itself declares.
Load those; load nothing else.

**Trust model.** `lm-judge` runs with `--dangerously-skip-permissions`, so it
rebases, pushes, and opens PRs without confirmation. That is acceptable only
because the worktree is local, the branch is disposable, and the PR still needs
the user's merge. It is *not* a claim that the judge's inputs are trusted —
model-authored code and GitHub issue text both reach it. Two consequences: never
widen the judge's reach to `main`, and never let it merge.

### Delivering the brief

**Multi-line text goes in via the paste buffer, never `send-keys "$(cat …)"`.**
`send-keys` turns every embedded newline into a Return, which submits the brief
line by line — so the model starts work on a fragment before it has read the
scope fence.

```bash
tmux load-buffer -b lmstack "$RUN/brief.md"
tmux paste-buffer -b lmstack -t "$S:lm-exec"
tmux send-keys -t "$S:lm-exec" Enter
```

Single-line instructions may use `send-keys` directly.

The brief carries an explicit **scope fence** — the files that may be touched and
the files that may not. Every prior failure in clawrium came from the model going
wide, not from it being unable to make the change. It also states: commit
locally, never push, never open a PR, do not add work beyond the tasks listed,
and stop and say so if a task turns out to be already done.

### Idle detection

Interactive windows give no exit code. Poll:

```bash
tmux capture-pane -p -t "$S:lm-exec" | tail -30
```

Idle when the capture is **byte-identical across two consecutive polls** and the
tail shows an input prompt. **Poll every ~90 seconds** — tasks run for minutes to
hours, and faster polling is noise.

A `done` sentinel written by the model is a **liveness hint only, never proof of
correctness.** The documented failure mode of these models is claiming completion
when the work is unfinished — clawrium PRs #883 and #879 were closed for exactly
that. Correctness is the judge's call, always.

If a window is idle but the tail shows the agent asking a question, answer it
from repository conventions and send the answer. Do not escalate to the user
mid-run.

### Cleanup is a sweep, not a timer

Nothing polls for merges. `/lmstack:exec --sweep` reconciles every task in
`running` or `in-review`:

| Observed | Action |
|---|---|
| `in-review`, PR merged | mark `merged`; kill session; remove worktree and branch |
| `in-review`, PR closed unmerged | mark `failed`, record why |
| `in-review`, PR still open | leave alone |
| `running`, tmux session live | leave alone; report the current round |
| `running`, **no** live session | stale claim from a crashed run — return to `queued`, record that the run aborted |

That last row is the one that matters. Without it, a killed terminal strands a
task as permanently in-progress and every later harvest silently skips it.

Leave the worktree and session up while the PR is open — reviewers ask for
changes, and the live pi session still holds the full context.

## 8. The ledger

One line appended to `~/.lmstack/ledger.jsonl` per run. Cross-repo and cross-run,
so it lives above the per-role directories and never rides along in a PR.

```json
{"key":"ric03uec__lmstack#42","host_role":"h2-amd","tier":"T1",
 "shape":"doc-mirror-sync","judge_rounds":1,"outcome":"pr-opened","pr":43,
 "started":"…","ended":"…","wall_min":31,"interventions":2,"ts":"…"}
```

`interventions` counts the times a human had to unstick the run. With `wall_min`
it answers the only question that decides whether any of this is worth running:
**is it cheaper than doing the issue yourself?** A shape averaging 40 minutes at
zero interventions is a win; the same shape at three interventions is a human
doing the work with extra steps.

`shape` is the task archetype — `doc-mirror-sync`, `dead-code-delete`,
`guard-clause-widen`, `symbol-extract`, `cli-flag-add`, `test-coverage-add`.
After ~20 runs the ledger says which shapes clear on the first try, and the §6
classification thresholds get tuned from data instead of judgment. This is also
the substrate for per-stack evals (backlog B-3): the ledger *is* the eval result
set, gathered from real work rather than a synthetic suite.

Wall time in a PR is rounded to five minutes because a human reads it; the ledger
keeps the unrounded value so trends are not quantised. Compute elapsed time in
`python3`, not `date -u -d` — BSD `date` has no `-d`, so on macOS that silently
yields `~0m`. If the stamp is missing or the clock stepped backwards, write
`unknown` and `null`. A fabricated duration is worse than an absent one; nobody
audits a number that looks plausible.

## 9. What changes in the existing repository

| Area | Change |
|---|---|
| `skills/lmstack/` | Splits four ways. `stacklog.sh` and `classify.py` become shared. |
| `skills/install.sh` | Deleted. Plugin distribution replaces it; it also collides with `skills/install/`. |
| Test T6.3 (path binding) | Deleted — the mechanism no longer exists. |
| `pi-config/bin/lmstack-ask` | Moves to `bin/`. |
| `Makefile` | Host targets read inventory and vars from `~/.lmstack/<role>/`. Stays as the internal path. |
| `tests/validate_models.py` | Accepts an external vars file rather than assuming the tracked one. |
| Ansible `stack.env` path | `~/.lmstack/env/stack.env` → `~/.lmstack/stack.env`. |
| `.stacklog/` | Moves to `~/.lmstack/<role>/stacklog/`. Redaction rules and test unchanged. |
| `README.md`, `website/`, `PLAN.md` | Rewritten around four commands, once the commands exist. |

## 10. Phases and acceptance

| Phase | Content | Gate |
|---|---|---|
| **0** | Plugin scaffold, manifest, marketplace, four-way skill split, `bin/` migration, deletions | `claude plugin validate` passes; Scenario A |
| **1** | `~/.lmstack/<role>/` relocation across validator, Makefile, playbooks, stacklog | `make test` green; Scenario A4 |
| **2** | `harvest` — sanitize, staleness, classify, task store, idempotent re-run | Scenario B |
| **3** | `exec` — port clawctl-lmwork: forge, brief, idle detection, judge rounds, PR, sweep, ledger | Scenario C |
| **4** | Threshold recalibration from ledger data; docs rewrite | — |

### Preconditions

Test against **dummy issues opened on this repository** (`ric03uec/lmstack`) —
no separate test repo. Label them so they are obviously synthetic and close them
afterwards. Three, graded:

1. **Mechanical** — "the `tmux` prerequisite is listed in `README.md`,
   `website/docs/quickstart.md`, and `website/docs/intro.md` with three different
   wordings; make them identical." Named files, in-repo precedent, no logic.
2. **Scoped** — "`classify.py` `pick_tier()` falls back to the smallest stocked
   tier when the budget is below every ceiling; add a unit test covering that
   branch." One function, one test, existing suite proves it.
3. **Out of reach** — "add a third host role for Intel Arc GPUs with a matching
   engine and catalog." Present so harvest has something it should reject.

Plus: h2-amd installed and serving `qwen2.5-coder-7b`; `gh auth status` clean.

### Scenario A — analyze and install

| # | Step | Expected |
|---|---|---|
| A1 | `/lmstack:analyze` locally | Reports `h2-amd`, GTT-based arithmetic, recommends `qwen2.5-coder-7b` |
| A2 | `/lmstack:analyze <ssh-target>` | Same shape over SSH; nothing installed on the target |
| A3 | `/lmstack:analyze` on a GPU-less box | `supported: false` + reason + remedy + stop. No CPU fallback |
| A4 | `/lmstack:install` from an empty `~/.lmstack` | `~/.lmstack/h2-amd/{host.yml,hosts.ini,vars.yml}` created; repo `git status` **clean** |
| A5 | Any sudo step | Printed for the user, never executed by the agent |
| A6 | End of install | `pi --list-models \| grep lmstack` returns a model; a real completion succeeds |

### Scenario B — harvest

| # | Step | Expected |
|---|---|---|
| B1 | `/lmstack:harvest` on this repo's issues | Reads up to 10, writes a task record each |
| B2 | Tiers | #1 `T1`; #2 `T1` or `T2`; #3 `park` with a stated reason |
| B3 | An issue with a zero-width character in its title | Stripped before it reaches any log or brief |
| B4 | Project URL instead | Asks issues-or-PRs before doing anything |
| B5 | Re-run B1 | Classification cached; **staleness re-run**; no duplicates |
| B6 | Nothing fits | Says so plainly; does not lower the bar |
| B7 | Any GitHub label | **None created.** Verdicts live in `~/.lmstack/` only |

### Scenario C — exec, end to end

| # | Step | Expected |
|---|---|---|
| C1 | `/lmstack:exec <key-1>` | Shows task, branch, worktree, tool allowlist; waits (unless `--yolo`) |
| C2 | Confirm | Worktree created; session `lmstack-<key>` has **two windows**, `lm-exec` and `lm-judge` |
| C3 | `tmux attach` | Both are live interactive TUIs, indistinguishable from hand-started |
| C4 | Type into `lm-exec` mid-run | It responds. The user can correct, answer, or take over |
| C5 | During the run | GPU shows load; **no Anthropic traffic from the exec window** |
| C6 | The brief as delivered | Arrived as **one message**, not line-by-line. Scope fence intact |
| C7 | Orchestrator polling | ~90 s cadence; idle called only on two identical captures + a prompt |
| C8 | `lm-exec` finishes | Committed **locally**. No push, no PR from this window |
| C9 | Judge round 1 | Orchestrator sends the review request; judge writes `judge-1.md` |
| C10 | A `REVISE` verdict | Findings relayed into the **live** pi session; brief not restated; round increments |
| C11 | `SATISFIED` | **Judge** rebases on `origin/main`, pushes, opens the PR referencing the issue |
| C12 | 3 rounds exhausted | PR opens anyway, flagged stuck. Run never blocks on the user |
| C13 | Run issue #3 (out of reach) | Harvest already parked it; exec refuses to dispatch |
| C14 | Two `/lmstack:exec` at once | Second refuses. One forge at a time |
| C15 | Kill the terminal mid-run, then `--sweep` | Task returns to `queued`, marked aborted. Not stranded |
| C16 | Merge the PR, then `--sweep` | `merged`; worktree, branch, session removed |
| C17 | Throughout | One ledger line with `wall_min` and `interventions`; stacklog has no secrets |

C5 is the product thesis. C12 and C15 are the two rows that separate a demo from
something that survives a week of use.

## 11. Backlog

| # | Item | Why deferred |
|---|---|---|
| B-1 | **Compress the pi harness context.** System prompt plus tool schemas run ~17k tokens against a 32k window. Trimming is the largest available capability win. | Accepted as-is for v2; needs ledger data to target. |
| B-2 | **opencode support.** It has its own command and plugin mechanism but no `/namespace:command` analogue. | Claude Code is the only supported harness for v2. |
| B-3 | **Per-stack evals.** A graded task set per host role producing a capability profile. | The §8 ledger is the substrate; it needs runs before it can grade anything. |
| B-4 | **Concurrency above one forge.** clawrium caps at 2 in flight against a 27B on vLLM with `num_seq=3`. | v2 is strictly sequential. Revisit once single-forge runs are boring. |
| B-5 | **An `atx`-equivalent review gate.** clawrium runs a static review tool between the judge and the PR. | lmstack has no equivalent; the judge is the only gate in v2. |

## 12. Open risks

- **The thresholds are calibrated for a 27B, not a 7B.** §6's four checks come
  from clawrium's larger model. Expect them to be too generous. Until the ledger
  has lmstack rows, err toward `park` and accept a low dispatch rate.
- **`--tools` is the only sandbox.** The worktree isolates files, not the shell.
  Start the allowlist narrow — read, write, edit — and add `bash` only for tasks
  that must run tests.
- **`send-keys` and a typing user collide.** Both write to the same window. This
  is the accepted cost of an attachable session; the orchestrator should not type
  into a window that has changed under it without saying so.
- **A 9-hour run is a real outcome.** The ledger has one. A wall-clock ceiling
  per run, after which the forge is left up and the user told, is worth having
  before this is pointed at a real backlog.
