#!/usr/bin/env bash
# T9 — the harvest primitives: lmstack-sanitize and lmstack-task.
#
# Both are security-relevant in ways a reading of the source does not settle.
# The sanitizer defends the orchestrator's own terminal against text anyone on
# the internet can author, and it has a failure mode unique to this problem: a
# filter written with literal invisible characters looks correct, diffs as a
# no-op, and cannot be reviewed by eye. T9.1 asserts the source stays clean.
#
# The task store enforces the harvest/exec ownership split. If a harvest re-run
# could reset `status`, a second pass would send a task a forge is part-way
# through back to the queue and two forges would race on one worktree.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

SANITIZE="$REPO_ROOT/bin/lmstack-sanitize"
TASK="$REPO_ROOT/bin/lmstack-task"

pass=0
fail=0
section() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }
ok()      { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass + 1)); }
bad()     { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail + 1)); }

# Codepoints are built here the same way they are in the filter: from integers,
# never as literals. A test file full of invisible characters is as unreviewable
# as the filter would be.
u() { python3 -c 'import sys; sys.stdout.write("".join(chr(int(a,16)) for a in sys.argv[1:]))' "$@"; }

# ---------------------------------------------------------------------------
section "sanitize — source hygiene"

# T9.1 — the filter must not contain the characters it strips.
if python3 - "$SANITIZE" <<'PY'
import sys, unicodedata
src = open(sys.argv[1], encoding="utf-8").read()
bad = sorted({hex(ord(c)) for c in src
              if unicodedata.category(c) in ("Cf", "Cc") and c not in "\t\n\r"})
if bad:
    print("        found:", ", ".join(bad))
sys.exit(1 if bad else 0)
PY
then
  ok "T9.1 lmstack-sanitize contains no literal invisible codepoints"
else
  bad "T9.1 lmstack-sanitize contains literal invisible codepoints"
fi

# ---------------------------------------------------------------------------
section "sanitize — stripping"

# A right-to-left override makes a dangerous name render as a harmless one.
# This is the attack the filter exists for, so it is asserted by name.
spoof="report$(u 202E)gnp.exe$(u 202C)"
got="$("$SANITIZE" <<<"$spoof")"
if [[ "$got" == "reportgnp.exe" ]]; then
  ok "T9.2 RLO-spoofed filename is flattened to what it really is"
else
  bad "T9.2 RLO spoof survived: got '$got'"
fi

for cp in 200B 200C 200D 2060 FEFF 00AD 180E; do
  probe="a$(u "$cp")b"
  if [[ "$("$SANITIZE" <<<"$probe")" == "ab" ]]; then
    ok "T9.3 U+$cp stripped"
  else
    bad "T9.3 U+$cp survived"
  fi
done

# Tag characters smuggle a readable ASCII payload past every renderer.
tagged="ok$(u E0041 E0042)"
if [[ "$("$SANITIZE" <<<"$tagged")" == "ok" ]]; then
  ok "T9.4 tag-character payload stripped"
else
  bad "T9.4 tag-character payload survived"
fi

# ESC opens an ANSI sequence, which can repaint the orchestrator's terminal.
if [[ "$("$SANITIZE" <<<"$(u 001B)[2Jwiped")" == "[2Jwiped" ]]; then
  ok "T9.5 ESC stripped, so ANSI sequences cannot execute"
else
  bad "T9.5 ESC survived"
fi

# Multi-byte text must come through untouched. A byte-oriented filter fails here.
intact='héllo — naïve “quotes” 日本語 🎉'
if [[ "$("$SANITIZE" <<<"$intact")" == "$intact" ]]; then
  ok "T9.6 legitimate multi-byte text is unchanged"
else
  bad "T9.6 legitimate multi-byte text was corrupted"
fi

if [[ "$(printf 'a\tb\nc\n' | "$SANITIZE")" == "$(printf 'a\tb\nc\n')" ]]; then
  ok "T9.7 tab and newline survive"
else
  bad "T9.7 tab or newline was stripped"
fi

# ---------------------------------------------------------------------------
section "sanitize — json and check modes"

payload="$(python3 -c '
import json, sys
json.dump({"title": "fix" + chr(0x202E) + "the thing", "n": 42, "ok": True,
           "labels": ["bug" + chr(0x200B)]}, sys.stdout)')"

out="$(printf '%s' "$payload" | "$SANITIZE" --json)"
if python3 -c '
import json, sys
d = json.loads(sys.argv[1])
assert d["title"] == "fixthe thing", d["title"]
assert d["labels"] == ["bug"], d["labels"]
assert d["n"] == 42 and d["ok"] is True
' "$out" 2>/dev/null; then
  ok "T9.8 --json sanitizes strings and preserves non-string types"
else
  bad "T9.8 --json mangled the document"
fi

printf 'clean text\n' | "$SANITIZE" --check >/dev/null 2>&1
[[ $? -eq 0 ]] && ok "T9.9 --check exits 0 on clean input" \
               || bad "T9.9 --check exited non-zero on clean input"

"$SANITIZE" --check <<<"dirty$(u 200B)" >/dev/null 2>&1
[[ $? -eq 1 ]] && ok "T9.9 --check exits 1 when something was stripped" \
               || bad "T9.9 --check did not signal a strip"

printf 'not json' | "$SANITIZE" --json >/dev/null 2>&1
[[ $? -eq 2 ]] && ok "T9.10 --json exits 2 on malformed input" \
               || bad "T9.10 --json did not reject malformed input"

# ---------------------------------------------------------------------------
section "task store"

LMSTACK_STATE_DIR="$(mktemp -d)"
export LMSTACK_STATE_DIR
trap 'rm -rf "$LMSTACK_STATE_DIR"' EXIT

KEY="ric03uec__lmstack#42"

if "$TASK" put --host h2-amd --key "$KEY" --tier T1 --staleness DISPATCH \
     --reason "precedent at hosts/h1-nvidia/ansible/10-stack.yml" \
     --url "https://example.invalid/42" --title "Fix the thing" \
     --complexity s --shape doc-mirror-sync >/dev/null; then
  ok "T9.11 put writes a record"
else
  bad "T9.11 put failed"
fi

want="$LMSTACK_STATE_DIR/h2-amd/tasks/ric03uec__lmstack/42.json"
[[ -f "$want" ]] && ok "T9.11 record lands at <role>/tasks/<owner>__<repo>/<n>.json" \
                 || bad "T9.11 record not at $want"

# The whole point of the split: a re-harvest must not disturb a running forge.
"$TASK" set --host h2-amd --key "$KEY" --status running >/dev/null
"$TASK" put --host h2-amd --key "$KEY" --tier T2 --staleness RESCOPE \
  --reason "half of it already shipped" >/dev/null

if "$TASK" get --host h2-amd --key "$KEY" | python3 -c '
import json, sys
r = json.load(sys.stdin)
assert r["status"] == "running", f"status was reset to {r['"'"'status'"'"']}"
assert r["tier"] == "T2", "tier was not refreshed"
assert r["title"] == "Fix the thing", "title was lost on merge"
' 2>/dev/null; then
  ok "T9.12 re-harvest refreshes the verdict, keeps status and prior fields"
else
  bad "T9.12 re-harvest disturbed a running task"
fi

if ! "$TASK" put --host h2-amd --key "$KEY" --tier T1 --staleness DISPATCH \
       --reason x --status merged >/dev/null 2>&1; then
  ok "T9.13 put refuses --status; exec owns it"
else
  bad "T9.13 put accepted --status"
fi

if ! "$TASK" set --host h2-amd --key "ric03uec__lmstack#999" \
       --status merged >/dev/null 2>&1; then
  ok "T9.13 set refuses to conjure an unharvested task"
else
  bad "T9.13 set created a record from a status change"
fi

# Both --host and --key become path segments, so both are traversal surfaces.
if ! "$TASK" get --host "../../etc" --key "$KEY" >/dev/null 2>&1; then
  ok "T9.14 --host rejects a traversal attempt"
else
  bad "T9.14 --host accepted '../../etc'"
fi

for evil in '../../evil#1' 'a__b#notanumber' 'noseparator#1' 'a__b'; do
  if ! "$TASK" put --host h2-amd --key "$evil" --tier T1 \
         --staleness DISPATCH --reason x >/dev/null 2>&1; then
    ok "T9.14 --key rejects '$evil'"
  else
    bad "T9.14 --key accepted '$evil'"
  fi
done

if ! "$TASK" put --host h2-amd --key "a__b#1" --tier BOGUS \
       --staleness DISPATCH --reason x >/dev/null 2>&1; then
  ok "T9.15 an unknown tier is rejected"
else
  bad "T9.15 an unknown tier was accepted"
fi

"$TASK" put --host h2-amd --key "ric03uec__lmstack#7" --tier park \
  --staleness DISPATCH --reason "scope needs a human split" >/dev/null

if [[ "$("$TASK" list --host h2-amd --tier T2 --json | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')" == "1" ]]; then
  ok "T9.16 list filters by tier"
else
  bad "T9.16 tier filter is wrong"
fi

if "$TASK" list --host h2-amd --json | python3 -c '
import json, sys
keys = [r["key"] for r in json.load(sys.stdin)]
assert len(keys) == 2, keys
' 2>/dev/null; then
  ok "T9.16 list returns every record across the repo directory"
else
  bad "T9.16 list did not return both records"
fi

if [[ "$("$TASK" list --host h2-amd-empty)" == "no tasks match" ]]; then
  ok "T9.17 an empty queue reports plainly rather than failing"
else
  bad "T9.17 an empty queue did not report cleanly"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
