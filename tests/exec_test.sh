#!/usr/bin/env bash
# T10 — the exec primitives: lmstack-forge and lmstack-ledger.
#
# These drive a real tmux server, but with `cat` and `sh` standing in for pi and
# Claude Code. That is the whole point: the mechanics being tested — that a
# multi-line brief arrives as one message, that idle is inferred correctly, that
# a session name cannot be made ambiguous — are independent of which agent runs
# in the window, and they are the parts that fail silently.
#
# The paste test is the one that earns its keep. `send-keys "$(cat file)"` looks
# correct and works on a single-line file; it corrupts every multi-line brief by
# submitting it a line at a time, so the model begins work before it has read the
# scope fence. Only a multi-line fixture catches that.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

FORGE="$REPO_ROOT/bin/lmstack-forge"
LEDGER="$REPO_ROOT/bin/lmstack-ledger"

pass=0
fail=0
section() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }
ok()      { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass + 1)); }
bad()     { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail + 1)); }
skip()    { printf '  \033[33mSKIP\033[0m %s\n' "$1"; }

if ! command -v tmux >/dev/null 2>&1; then
  skip "tmux not installed — cannot exercise the forge"
  printf '\n%d passed, %d failed\n' "$pass" "$fail"
  exit 0
fi

LMSTACK_STATE_DIR="$(mktemp -d)"
export LMSTACK_STATE_DIR

# An isolated tmux server. Without this the test would attach to the user's own
# server and its kill-session could take out a session they are working in.
SOCKET="$LMSTACK_STATE_DIR/tmux.sock"
export TMUX_TMPDIR="$LMSTACK_STATE_DIR"

# lmstack-forge shells out to `tmux` by name, so the isolated socket has to reach
# it through PATH rather than a shell function.
#
# The shim execs tmux by ABSOLUTE path, resolved before the shim joins PATH. The
# obvious `exec env tmux -S …` re-resolves through PATH, finds this shim again,
# and recurses — each pass appending another -S until the argv is megabytes wide
# and the machine is full of runaway processes. It fails as a fork bomb, not as a
# test failure, so it is worth spelling out.
REAL_TMUX="$(command -v tmux)"
SHIM="$LMSTACK_STATE_DIR/bin"
mkdir -p "$SHIM"
cat > "$SHIM/tmux" <<EOF
#!/usr/bin/env bash
exec "$REAL_TMUX" -S "$SOCKET" "\$@"
EOF
chmod +x "$SHIM/tmux"
PATH="$SHIM:$PATH"
export PATH

cleanup() {
  "$REAL_TMUX" -S "$SOCKET" kill-server 2>/dev/null
  rm -rf "$LMSTACK_STATE_DIR"
}
trap cleanup EXIT

KEY="ric03uec__lmstack#42"
SLUG="ric03uec__lmstack-42"
SESSION="lmstack-$SLUG"
WT="$LMSTACK_STATE_DIR/worktree"
RUN="$LMSTACK_STATE_DIR/runs/$SLUG"
mkdir -p "$WT"

# ---------------------------------------------------------------------------
section "forge — argument guards"

for evil in '../../evil#1' 'a__b' 'has:colon__x#1' 'a__b#x'; do
  if ! "$FORGE" status --key "$evil" >/dev/null 2>&1; then
    ok "T10.1 rejects malformed key '$evil'"
  else
    bad "T10.1 accepted malformed key '$evil'"
  fi
done

if ! "$FORGE" create --key "$KEY" --worktree "$LMSTACK_STATE_DIR/nope" \
     --exec-cmd cat --judge-cmd cat >/dev/null 2>&1; then
  ok "T10.1 refuses a worktree that does not exist"
else
  bad "T10.1 created a forge on a missing worktree"
fi

if ! "$FORGE" bogus --key "$KEY" >/dev/null 2>&1; then
  ok "T10.1 rejects an unknown subcommand"
else
  bad "T10.1 accepted an unknown subcommand"
fi

# ---------------------------------------------------------------------------
section "forge — lifecycle"

# `cat` holds the window open and echoes what is typed, which is exactly what is
# needed to prove the brief arrived intact.
if "$FORGE" create --key "$KEY" --worktree "$WT" --run-dir "$RUN" \
     --exec-cmd 'cat' --judge-cmd 'sh' >/dev/null 2>&1; then
  ok "T10.2 create brings up the session"
else
  bad "T10.2 create failed"
fi

if "$REAL_TMUX" -S "$SOCKET" has-session -t "=$SESSION" 2>/dev/null; then
  ok "T10.2 session is named lmstack-<slug> with # replaced"
else
  bad "T10.2 expected session '$SESSION'"
fi

windows="$("$REAL_TMUX" -S "$SOCKET" list-windows -t "=$SESSION" -F '#{window_name}' | sort | tr '\n' ',')"
if [[ "$windows" == "lm-exec,lm-judge," ]]; then
  ok "T10.2 both windows exist (windows, not split panes)"
else
  bad "T10.2 windows were '$windows'"
fi

[[ -f "$RUN/started" ]] && ok "T10.3 a started stamp file is written" \
                        || bad "T10.3 no started stamp"

if grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$RUN/started"; then
  ok "T10.3 the stamp is UTC ISO-8601"
else
  bad "T10.3 stamp is malformed: $(cat "$RUN/started")"
fi

# A second forge for the same task would put two agents in one worktree.
if ! "$FORGE" create --key "$KEY" --worktree "$WT" --run-dir "$RUN" \
     --exec-cmd 'cat' --judge-cmd 'sh' >/dev/null 2>&1; then
  ok "T10.4 refuses a second forge for a task already running"
else
  bad "T10.4 created a duplicate forge"
fi

if [[ "$("$FORGE" status --key "$KEY")" == "live $SESSION" ]]; then
  ok "T10.5 status reports a live forge"
else
  bad "T10.5 status did not report the live forge"
fi

if "$FORGE" status | grep -q "^$SESSION$"; then
  ok "T10.5 status with no key lists every forge (used by --sweep)"
else
  bad "T10.5 keyless status did not list the forge"
fi

# ---------------------------------------------------------------------------
section "forge — the brief arrives as one message"

cat > "$RUN/brief.md" <<'BRIEF'
## Scope fence
Touch ONLY: bin/lmstack-log
Do NOT touch: tests/
## Tasks
1. Widen the guard.
BRIEF

sleep 1
"$FORGE" paste --key "$KEY" --window lm-exec --file "$RUN/brief.md" >/dev/null 2>&1
sleep 1
captured="$("$FORGE" capture --key "$KEY" --window lm-exec --lines 40)"

# Every line has to be present. send-keys would deliver these too, so presence
# alone is not the discriminator — ordering and completeness together are.
missing=0
while IFS= read -r want; do
  [[ -z "$want" ]] && continue
  grep -Fq "$want" <<<"$captured" || { missing=1; printf '        missing: %s\n' "$want"; }
done < "$RUN/brief.md"
[[ $missing -eq 0 ]] && ok "T10.6 every line of the brief reached the window" \
                     || bad "T10.6 the brief arrived incomplete"

if grep -Fq "Do NOT touch: tests/" <<<"$captured" \
   && grep -Fq "1. Widen the guard." <<<"$captured"; then
  ok "T10.6 the scope fence arrives ahead of the tasks, intact"
else
  bad "T10.6 the scope fence did not survive delivery"
fi

if ! "$FORGE" type --key "$KEY" --window lm-exec --line "$(printf 'a\nb')" >/dev/null 2>&1; then
  ok "T10.7 type refuses multi-line input, so a brief cannot go in that way"
else
  bad "T10.7 type accepted multi-line input"
fi

if ! "$FORGE" paste --key "$KEY" --window lm-exec \
     --file "$LMSTACK_STATE_DIR/absent.md" >/dev/null 2>&1; then
  ok "T10.7 paste refuses a missing file"
else
  bad "T10.7 paste accepted a missing file"
fi

# lm-judge runs a bare shell here, standing in for an agent that failed to
# start. Delivering the brief there would let a shell execute it line by line.
if ! "$FORGE" paste --key "$KEY" --window lm-judge --file "$RUN/brief.md" >/dev/null 2>&1; then
  ok "T10.7 paste refuses a window sitting at a shell prompt"
else
  bad "T10.7 paste delivered a brief into a live shell"
fi

if ! "$FORGE" type --key "$KEY" --window lm-judge --line 'echo hi' >/dev/null 2>&1; then
  ok "T10.7 type refuses a window sitting at a shell prompt"
else
  bad "T10.7 type sent a line into a live shell"
fi

# capture-pane pads its output out to the full pane height. pi keeps a status bar
# on the bottom row so its panes look full, but Claude Code draws from the top and
# leaves the rest blank, so a plain `tail -n 40` returns nothing but padding. That
# made capture print nothing and — much worse — made idle compare "" with "" and
# call a judge that had not started yet finished.
tm() { "$REAL_TMUX" -S "$SOCKET" "$@"; }

tm send-keys -t "$SESSION:lm-exec" 'SENTINEL_TOP' Enter
sleep 1
rows="$(tm display-message -p -t "$SESSION:lm-exec" '#{pane_height}')"
blanks="$(tm capture-pane -p -t "$SESSION:lm-exec" | tail -n 5 | tr -d '[:space:]')"

if [[ -n "$blanks" ]]; then
  skip "T10.8 pane is not bottom-padded here ($rows rows), cannot exercise the tail"
elif "$FORGE" capture --key "$KEY" --window lm-exec --lines 5 | grep -q SENTINEL_TOP; then
  ok "T10.8 capture strips trailing blank rows, so a top-drawing agent is still visible"
else
  bad "T10.8 capture returned only blank padding from a ${rows}-row pane"
fi

# An empty pane is not an idle pane, it is one that has not drawn yet. Two
# identical empty captures must not be read as "finished".
tm new-window -t "$SESSION" -n lm-exec -d 'sleep 300' >/dev/null 2>&1
tm kill-window -t "$SESSION:lm-exec" >/dev/null 2>&1
sleep 1
if [[ -z "$("$FORGE" capture --key "$KEY" --window lm-exec --lines 40 | tr -d '[:space:]')" ]]; then
  if ! "$FORGE" idle --key "$KEY" --window lm-exec --interval 1 >/dev/null 2>&1; then
    ok "T10.8 an undrawn pane reports busy, not a false idle"
  else
    bad "T10.8 an empty pane was reported idle"
  fi
else
  skip "T10.8 could not produce an empty pane in this terminal"
fi

if ! "$FORGE" capture --key "$KEY" --window lm-bogus >/dev/null 2>&1; then
  ok "T10.7 an unknown window name is rejected"
else
  bad "T10.7 an unknown window name was accepted"
fi

[[ -f "$RUN/exec.log" ]] && ok "T10.8 pipe-pane is recording exec.log" \
                         || bad "T10.8 exec.log was not created"

# ---------------------------------------------------------------------------
section "forge — idle detection"

# Quiet window: two captures match, so this is idle.
if "$FORGE" idle --key "$KEY" --window lm-judge --interval 1 >/dev/null 2>&1; then
  ok "T10.9 a quiet window reads as idle"
else
  bad "T10.9 a quiet window did not read as idle"
fi

# Busy window: output changes between captures, so this is not idle. This is the
# case that stops the orchestrator reviewing a half-written tree.
"$REAL_TMUX" -S "$SOCKET" send-keys -t "$SESSION:lm-judge" \
  'while true; do date +%s%N; sleep 0.1; done' Enter
sleep 1
if ! "$FORGE" idle --key "$KEY" --window lm-judge --interval 2 >/dev/null 2>&1; then
  ok "T10.9 a window still producing output does not read as idle"
else
  bad "T10.9 a busy window was reported idle"
fi

# ---------------------------------------------------------------------------
section "forge — teardown"

if "$FORGE" kill --key "$KEY" | grep -q "killed $SESSION"; then
  ok "T10.10 kill removes the session"
else
  bad "T10.10 kill did not remove the session"
fi

if [[ "$("$FORGE" kill --key "$KEY")" == "no live session $SESSION" ]]; then
  ok "T10.10 kill is idempotent, so a sweep can run twice"
else
  bad "T10.10 a second kill was not clean"
fi

"$FORGE" status --key "$KEY" >/dev/null 2>&1
[[ $? -eq 1 ]] && ok "T10.10 status exits 1 for a dead forge" \
               || bad "T10.10 status did not signal a dead forge"

if ! "$FORGE" paste --key "$KEY" --window lm-exec --file "$RUN/brief.md" >/dev/null 2>&1; then
  ok "T10.10 paste to a dead forge fails loudly rather than silently"
else
  bad "T10.10 paste to a dead forge appeared to succeed"
fi

# ---------------------------------------------------------------------------
section "ledger"

stamp="$LMSTACK_STATE_DIR/started"
python3 -c '
import datetime as d, sys
print((d.datetime.now(d.timezone.utc) - d.timedelta(minutes=37)).strftime("%Y-%m-%dT%H:%M:%SZ"))
' > "$stamp"

# 37 minutes rounds to 35, not 40: (37+2)//5*5.
if [[ "$("$LEDGER" --wall-only --started-file "$stamp")" == "~35m" ]]; then
  ok "T10.11 wall time rounds to the nearest five minutes"
else
  bad "T10.11 wall time was $("$LEDGER" --wall-only --started-file "$stamp"), expected ~35m"
fi

if [[ "$("$LEDGER" --wall-only --started-file "$LMSTACK_STATE_DIR/absent")" == "unknown" ]]; then
  ok "T10.12 a missing stamp yields 'unknown', never an estimate"
else
  bad "T10.12 a missing stamp did not yield 'unknown'"
fi

printf 'not-a-timestamp\n' > "$LMSTACK_STATE_DIR/bad-stamp"
if [[ "$("$LEDGER" --wall-only --started-file "$LMSTACK_STATE_DIR/bad-stamp")" == "unknown" ]]; then
  ok "T10.12 an unparseable stamp yields 'unknown'"
else
  bad "T10.12 an unparseable stamp was not caught"
fi

# A laptop resuming from sleep is enough to step the clock backwards. The naive
# rounding formula turns that into a cheerful '~-5m'.
python3 -c '
import datetime as d
print((d.datetime.now(d.timezone.utc) + d.timedelta(minutes=20)).strftime("%Y-%m-%dT%H:%M:%SZ"))
' > "$LMSTACK_STATE_DIR/future-stamp"
if [[ "$("$LEDGER" --wall-only --started-file "$LMSTACK_STATE_DIR/future-stamp")" == "unknown" ]]; then
  ok "T10.13 a backwards clock yields 'unknown', not a negative duration"
else
  bad "T10.13 a backwards clock produced $("$LEDGER" --wall-only --started-file "$LMSTACK_STATE_DIR/future-stamp")"
fi

"$LEDGER" --key "$KEY" --host h2-amd --tier T1 --shape doc-mirror-sync \
  --judge-rounds 2 --interventions 1 --outcome pr-opened --pr 43 \
  --started-file "$stamp" >/dev/null

if [[ -f "$LMSTACK_STATE_DIR/ledger.jsonl" ]]; then
  ok "T10.14 the ledger sits above the per-role directories"
else
  bad "T10.14 ledger.jsonl not at the state root"
fi

if python3 -c '
import json, sys
line = open(sys.argv[1]).read().strip()
e = json.loads(line)
assert e["key"] == "ric03uec__lmstack#42", e["key"]
assert e["wall_min"] == 37, "expected unrounded 37, got %r" % (e["wall_min"],)
assert e["judge_rounds"] == 2 and e["interventions"] == 1
assert e["outcome"] == "pr-opened"
' "$LMSTACK_STATE_DIR/ledger.jsonl" 2>/dev/null; then
  ok "T10.14 the ledger keeps the UNROUNDED wall time, unlike the PR"
else
  bad "T10.14 ledger entry is wrong"
fi

"$LEDGER" --key "a__b#1" --host h2-amd --outcome failed \
  --started-file "$LMSTACK_STATE_DIR/absent" >/dev/null
if python3 -c '
import json, sys
last = json.loads(open(sys.argv[1]).read().strip().splitlines()[-1])
assert last["wall_min"] is None, last["wall_min"]
' "$LMSTACK_STATE_DIR/ledger.jsonl" 2>/dev/null; then
  ok "T10.15 an unknown duration is recorded as null, never fabricated"
else
  bad "T10.15 a missing stamp did not record null"
fi

if [[ "$(wc -l < "$LMSTACK_STATE_DIR/ledger.jsonl")" == "2" ]]; then
  ok "T10.15 the ledger appends rather than overwrites"
else
  bad "T10.15 the ledger did not append"
fi

if ! "$LEDGER" --key "a__b#1" --host h2-amd --outcome bogus >/dev/null 2>&1; then
  ok "T10.16 an unknown outcome is rejected"
else
  bad "T10.16 an unknown outcome was accepted"
fi

section "T10.17 — a provider lmstack did not generate is still reachable"

# When this was missing, `lmstack-ask -P vllm-inx` reported "no endpoint known"
# and the exec loop fell back to the 8B it is documented never to use. The
# fallback was silent: the run started, so nothing looked wrong until the diff
# came back empty.
ASK="$REPO_ROOT/bin/lmstack-ask"
EXT_DIR="$LMSTACK_STATE_DIR/extensions"
mkdir -p "$EXT_DIR"
cat > "$EXT_DIR/hand-written.ts" <<'EOF'
export default { provider: { baseUrl: "http://elsewhere.invalid:4000/v1" } };
EOF

if [[ "$(LMSTACK_PI_EXTENSIONS="$EXT_DIR" "$ASK" -P hand-written --print-model 2>&1)" != *"no endpoint known"* ]]; then
  ok "T10.17 a hand-written provider's endpoint is read from its pi extension"
else
  bad "T10.17 a provider with an extension was reported as having no endpoint"
fi

if [[ "$(LMSTACK_PI_EXTENSIONS="$EXT_DIR" "$ASK" -P absent --print-model 2>&1)" == *"no endpoint known"* ]]; then
  ok "T10.17 a provider with no extension is reported missing, not invented"
else
  bad "T10.17 an unknown provider did not report a missing endpoint"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
