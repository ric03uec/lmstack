# Demo recording script — AI Tinkerers Seattle deck

Hand this file to an agent. It is the complete procedure for producing the two
real asciinema casts the deck needs:

| Output | Slide | Replaces |
| --- | --- | --- |
| `harvest.cast` | `Demo — harvest` | placeholder cast |
| `exec.cast` | `Demo — exec` | placeholder cast |

Both land in this directory (`website/static/decks/ai-tinkerers/`). The deck
picks them up by relative path with no code change.

Read the whole file before touching a terminal. There is a prep phase that must
happen **off camera**, and a class of mistake in it that cannot be fixed later
without re-recording.

---

## 0. Facts that override the deck

The deck currently shows command lines that do not exist. Do not reproduce them.

| Deck says | Reality |
| --- | --- |
| `lmstack harvest ~/src/clawrium` | `/lmstack:harvest ric03uec/clawrium` — a Claude Code slash command. There is no `lmstack` CLI. |
| `lmstack exec T1` | `/lmstack:exec ric03uec__clawrium#42` — slash command, and the argument is a task **key**, not `T1`. |
| `lmstack exec T7 --repo …` | `--repo` is not a flag. Exec reads `repo_path` off the task record. |
| task IDs `T1`, `T7` | `T1`/`T2`/`park`/`TRAP` are **tiers**, not identifiers. Keys are `<owner>__<repo>#<number>`, validated against `^([A-Za-z0-9][A-Za-z0-9._-]*)__([A-Za-z0-9][A-Za-z0-9._-]*)#(\d+)$`. |
| `PR #418 authored_by:local_qwen` | The implementation **forbids creating labels** (`skills/exec/judge.md`: "Never create a label."). The PR *body* names the local model instead. Do not show a label. |
| two tmux sessions, exec and judge | **One** session, `lmstack-<slug>`, with **two windows**, `lm-exec` and `lm-judge`. They share one worktree, so they are never run concurrently. |

`Ctrl+a s` lists **sessions**. It will show the orchestrator session next to the
forge session, which is worth one beat on camera. To show exec and judge you
need `Ctrl+a w` (window list) or `Ctrl+a 0` / `Ctrl+a 1`. Both are scripted
below.

---

## 1. Preconditions

Run every check. If one fails, stop and report — do not improvise a substitute.

```bash
# Control-host tools. All five must resolve.
for t in tmux git gh jq asciinema claude pi; do
  command -v "$t" >/dev/null || echo "MISSING: $t"
done

# The stack must be installed. Exactly one role is the easy case.
ls -1 ~/.lmstack/*/host.yml
ROLE="$(basename "$(dirname "$(ls -1 ~/.lmstack/*/host.yml | head -1)")")"
echo "ROLE=$ROLE"

# gh must be authenticated as the account that owns the demo repo.
gh auth status

# A large host must answer. Exec is documented to refuse rather than fall back
# to a small model, so verify before recording, not during.
lmstack-ask -P vllm-inx --print-model

# A local clone of the demo repo must exist. Harvest checks staleness against a
# working tree on disk, not against the API.
REPO_PATH="$HOME/workspace/ric03uec/clawrium"   # adjust to the real path
git -C "$REPO_PATH" rev-parse --show-toplevel

# No forge may be live. One at a time.
lmstack-forge status
```

Export a run id so every log line from this session correlates:

```bash
export LMSTACK_RUN_ID="demo-$(date -u +%Y%m%dT%H%M%SZ)"
```

### Terminal geometry — do this before recording

The deck player uses `fit: 'width'`, and the slide clips anything past 620 px
tall. Height follows the cast's row count. Record at:

```
100 columns x 24 rows
```

Verify with `tput cols; tput lines`. More than ~26 rows at 100 columns will be
clipped by `overflow: hidden` on `.demo-player`.

---

## 2. Phase 0 — prep, OFF CAMERA

### 2.1 Seed the backlog

Harvest reads real GitHub issues. For three tasks to land in **T1 — dispatch
now**, three issues must genuinely satisfy the T1 test: a single named file, an
in-repo precedent, and nothing to decide. Vague issues classify to `T2` or
`park`, and that is the classifier working correctly — you cannot force it.

Create them with `gh`, in the demo repo:

```bash
cd "$REPO_PATH"

gh issue create \
  --title "docs: <one concrete fix> in <exact/path/to/file.md>" \
  --body 'Change `<exact old string>` to `<exact new string>` in `<exact/path/to/file.md>`.

Only that file. Precedent: `<exact/path/to/sibling.md>` already does this.'
```

Each of the three must:

- name **exactly one** file path, and that path must exist;
- state the change as a before/after string, not an intention;
- cite one in-repo precedent by path;
- require no judgement call about scope.

Good shapes for this: a doc mirror that has drifted, a missing table-test case
for a function that already has a test file, a stale example in a README.

Record the three issue numbers. You need them for the keys.

**Optional fourth issue, for contrast.** The `harvest` slide note asks for a
rejection on screen. Create one deliberately unbounded issue — "refactor the
config layer", no files named, no acceptance criteria — so the report shows a
`park` or `TRAP` row. Do not fake this by editing the report.

### 2.2 Clean slate

```bash
# No stale records for these keys, so the harvest table is honest.
lmstack-task list --host "$ROLE"

# If the demo keys are already present from a rehearsal, remove their files.
# Path: ~/.lmstack/<role>/tasks/<owner>__<repo>/<number>.json
```

### 2.3 Rehearse once, then delete the rehearsal cast

Harvest takes real reading time and exec can run for minutes to hours. Rehearse
end to end before you record. Delete the rehearsal cast and reset §2.2.

---

## 3. Recording 1 — `harvest.cast`

### 3.1 Start the recorder

Run this in a **plain terminal, not inside tmux**. The recorder must own the
terminal so that the tmux client started inside it is captured, including
session and window switching.

```bash
cd /home/devashish/workspace/ric03uec/lmstack/website/static/decks/ai-tinkerers

asciinema rec harvest.cast \
  --overwrite \
  --idle-time-limit 2 \
  --title "lmstack harvest"
```

`--idle-time-limit 2` collapses dead air to two seconds. Without it a slide
that autoplays and loops will sit on a frozen frame while the model reads.

### 3.2 Inside the recording

Open the orchestrator session first, so the audience sees where they are:

```bash
tmux new-session -A -s lmstack-demo
```

Then, inside that session:

```bash
cd ~/workspace/ric03uec/clawrium      # the demo repo
claude
```

At the Claude Code prompt, type exactly:

```
/lmstack:harvest ric03uec/clawrium
```

Let it run. It will:

1. resolve the role from `~/.lmstack/*/host.yml`;
2. run `gh issue list --state open --limit 10 --json … | lmstack-sanitize --json > /tmp/lmstack-harvest.json`;
3. classify each issue into `T1` / `T2` / `park` / `TRAP` against the installed model;
4. write one record per task to `~/.lmstack/<role>/tasks/<owner>__<repo>/<number>.json`;
5. log the pass: `lmstack-log --event decision --action backlog.harvested`;
6. print the **Harvest** report table.

Do not interrupt it. Do not answer for it unless it asks a direct question.

### 3.3 Prove the queue is real

The report is model output. Follow it with the queue read from disk — that is
the part that matters:

```
!lmstack-task list --host <ROLE>
```

(`!` runs a shell command from inside Claude Code. Substitute the real role.)

Expected: three `T1 queued` rows, plus the contrast row if you created one.

### 3.4 Stop

```
/exit
```

then in the shell:

```bash
exit          # leaves the tmux session
exit          # or Ctrl-D — stops asciinema
```

Confirm: `asciinema: asciicast saved to harvest.cast`.

**Checkpoint 1.** You now have three dispatchable tasks and a cast that proves
it. Verify before continuing:

```bash
ls -l harvest.cast
lmstack-task list --host "$ROLE" --tier T1 --status queued
```

---

## 4. Recording 2 — `exec.cast`

This is the harder one. It runs long, and the interesting content is two agents
in two windows, not scrolling text.

### 4.1 Pick the key

Use the smallest of the three T1 tasks:

```bash
lmstack-task list --host "$ROLE" --tier T1 --status queued --json | jq -r '.[].key'
KEY="ric03uec__clawrium#<number>"
SLUG="${KEY//[#.]/-}"                  # ric03uec__clawrium-<number>
echo "session will be: lmstack-$SLUG"
```

### 4.2 Start the recorder

```bash
cd /home/devashish/workspace/ric03uec/lmstack/website/static/decks/ai-tinkerers

asciinema rec exec.cast \
  --overwrite \
  --idle-time-limit 2 \
  --title "lmstack exec"
```

### 4.3 Dispatch

```bash
tmux new-session -A -s lmstack-demo
cd ~/workspace/ric03uec/clawrium
claude
```

At the Claude Code prompt:

```
/lmstack:exec ric03uec__clawrium#<number>
```

Exec will, in order:

1. `lmstack-task get` — refuse unless tier is `T1` and status is `queued`;
2. re-check staleness against HEAD;
3. `git worktree add ~/.lmstack/worktrees/<slug> -b lmstack/<slug> main`;
4. `lmstack-forge create --key … --worktree … --run-dir … --exec-cmd 'pi …' --judge-cmd 'claude --dangerously-skip-permissions'`
   — which creates the session `lmstack-<slug>` with windows `lm-exec` and `lm-judge`,
   pipes both to `~/.lmstack/runs/<slug>/{exec,judge}.log`;
5. `lmstack-task set --status running`;
6. write `~/.lmstack/runs/<slug>/brief.md` and paste it into `lm-exec` as one message.

### 4.4 Show the forge — this is the money shot

The forge session exists alongside the orchestrator. Show that first:

```
Ctrl+a s
```

Two sessions listed: `lmstack-demo` and `lmstack-<slug>`. Select the forge.

Now show that it is two agents, not one:

```
Ctrl+a w          # window list: lm-exec and lm-judge
Ctrl+a 0          # lm-exec  — pi, running the local model, writing code
Ctrl+a 1          # lm-judge — claude, idle until called
```

Hold on `lm-exec` while it works. Let real output scroll. `--idle-time-limit`
handles the pauses.

Narration beats, in order:

- `lm-exec` runs the **local** model via `pi`. Name the model on screen.
- Its brief forbids `gh` entirely and forbids pushing. It commits locally.
- `lm-judge` is a separate agent with a separate contract (`skills/exec/judge.md`).
- They never run at the same time — one worktree, two agents, strictly alternating.

### 4.5 The judge round

Back in the orchestrator window, exec waits on
`lmstack-forge idle --key "$KEY" --window lm-exec` (byte-identical captures ~90 s
apart), then types the judge in:

```
Read <plugin>/skills/exec/judge.md and follow it for <KEY>, round 1.
The brief is at <run>/brief.md. Write your findings to <run>/judge-1.md.
```

Switch to `lm-judge` and let the review happen on camera. The judge checks scope
fence, task completion, `make test` / `make lint`, coverage, convention fit,
staleness, scope creep — then returns `SATISFIED`, `REVISE`, or `STUCK`.

If `REVISE`: the findings are sanitized (`lmstack-sanitize`) and pasted back into
the live `lm-exec` session, and the round counter increments. Ceiling is three
rounds. A revise round on camera is **good** — it is the argument for having a
judge at all. Do not restart to avoid one.

### 4.6 The PR

The judge opens it, not the exec agent — "the model that wrote the code is the
wrong one to certify it".

Expect the orchestrator to type into `lm-judge`:

```
Open the PR for <KEY>. Rebase on origin/main first. Wall time <~Nm>,
judge rounds <n>, human interventions <n>. Include a Callouts section.
Do not create any labels.
```

Stay on the `lm-judge` window through `gh pr create` so the PR URL appears on
screen. **Stop the recording once the PR URL is printed.** Do not record the
merge — the merge is a human decision and the slide says so out loud.

### 4.7 Stop

```
Ctrl+a s          # back to lmstack-demo
```

Optional closing frame, one command, then stop:

```
!lmstack-task list --host <ROLE>
```

`in-review` with a PR url. Then `/exit`, `exit`, `exit`.

Confirm: `asciinema: asciicast saved to exec.cast`.

---

## 5. After recording

```bash
cd /home/devashish/workspace/ric03uec/lmstack/website/static/decks/ai-tinkerers

# Casts must be valid asciicast v2 — first line is the header object.
head -c 200 harvest.cast; echo
head -c 200 exec.cast; echo

# Geometry check. Width should be 100; rows should be <= 26.
head -1 harvest.cast | jq '{width, height}'
head -1 exec.cast    | jq '{width, height}'

# File size sanity. The placeholders were ~1.5 KB; real ones will be far larger.
ls -l harvest.cast exec.cast
```

Then view the deck and confirm both players mount and autoplay:

```
http://localhost:3000/lmstack/decks/ai-tinkerers/
```

The browser caches these assets hard. Hard-refresh with `Ctrl+Shift+R`.

Finally, clean up the forge:

```bash
# Only after the PR is merged or closed.
# In Claude Code:  /lmstack:exec --sweep
```

---

## 6. Abort conditions

Stop and report rather than working around any of these:

- The large host does not answer. Exec is designed to refuse rather than fall
  back to a smaller model; a demo on an 8B is documented to fail multi-file work.
- Fewer than three issues classify as `T1`. Fix the issues, not the report.
- A forge is already live. `lmstack-forge kill --key <key>` first, deliberately.
- The judge returns `STUCK`, or hits the three-round ceiling. That is a real
  outcome; it is not a recordable demo. Pick a different task.
- Anything prompts for a secret, or a token appears on screen. Stop the
  recording and delete the cast — casts are committed to a public repo.

## 7. Never do these

- Do not hand-edit a `.cast` file to fix a mistake. Re-record.
- Do not create a GitHub label. The implementation forbids it and the audience
  may go look.
- Do not merge the PR on camera.
- Do not show `~/.lmstack/stack.env`, `~/.pi/agent/extensions/.env`, or any
  `LITELLM_MASTER_KEY` / `HF_TOKEN` / `sk-…` value.
- Do not record the `real-example.cast` slide from this script. It is a
  different artifact — a walkthrough of one already-merged PR — and it is not
  yet specified.
