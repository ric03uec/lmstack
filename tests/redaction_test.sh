#!/usr/bin/env bash
# T0.12 — feed known secrets through the stacklog writer and assert none survive.
#
# This is the test that lets us claim "the change log contains no sensitive content".
# If it ever goes red, the claim is false and the writer must be fixed, not the
# test relaxed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACKLOG="$REPO_ROOT/bin/lmstack-log"

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT
export LMSTACK_STACKLOG_DIR="$TMPDIR_TEST"

pass=0
fail=0

ok()   { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail + 1)); }

# Canaries. If any of these strings appears in the written log, we have leaked.
SK_KEY='sk-abcdef0123456789abcdef0123456789'
HF_TOKEN_VAL='hf_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345'
GH_PAT='ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
AWS_ID='AKIAIOSFODNN7EXAMPLE'
DB_PASS='hunter2-correct-horse'

printf '\n== stacklog redaction ==\n'

# ---------------------------------------------------------------------------
# 1. Secrets hidden behind innocuous-looking key names are dropped by value shape
# ---------------------------------------------------------------------------
detail=$(jq -cn \
  --arg sk "$SK_KEY" --arg hf "$HF_TOKEN_VAL" --arg gh "$GH_PAT" --arg aws "$AWS_ID" '
  {note: $sk, comment: $hf, misc: $gh, account: $aws}')

out=$("$STACKLOG" --host h1-nvidia --event apply --action test.value_shapes \
        --status ok --detail "$detail")

for canary in "$SK_KEY" "$HF_TOKEN_VAL" "$GH_PAT" "$AWS_ID"; do
  if grep -qF -- "$canary" "$out"; then
    bad "value-shape redaction leaked: ${canary:0:12}…"
  else
    ok "value-shape redaction dropped ${canary:0:12}…"
  fi
done

# ---------------------------------------------------------------------------
# 2. Ordinary-looking values under sensitive key names are dropped by key name
# ---------------------------------------------------------------------------
detail=$(jq -cn --arg p "$DB_PASS" '
  {litellm_db_password: $p, nested: {api_key: $p, deep: {auth_token: $p}}}')

out=$("$STACKLOG" --host h2-amd --event apply --action test.key_names \
        --status ok --detail "$detail")

if grep -qF -- "$DB_PASS" "$out"; then
  bad "key-name redaction leaked a password that matched no value pattern"
else
  ok "key-name redaction dropped password at every nesting depth"
fi

# ---------------------------------------------------------------------------
# 3. Bearer headers in free text are dropped
# ---------------------------------------------------------------------------
out=$("$STACKLOG" --host h1-nvidia --event error --action test.bearer --status failed \
        --error-msg "curl failed with Authorization: Bearer $SK_KEY")

if grep -qF -- "$SK_KEY" "$out"; then
  bad "bearer-in-free-text leaked"
else
  ok "bearer-in-free-text dropped"
fi

# ---------------------------------------------------------------------------
# 4. Host identity must be an inventory alias, never a routable address
# ---------------------------------------------------------------------------
if "$STACKLOG" --host 192.168.1.17 --event probe --action test.ip --status ok >/dev/null 2>&1; then
  bad "writer accepted an IP address as --host"
else
  ok "writer rejected an IP address as --host"
fi

if "$STACKLOG" --host box.example.com --event probe --action test.fqdn --status ok >/dev/null 2>&1; then
  bad "writer accepted an FQDN as --host"
else
  ok "writer rejected an FQDN as --host"
fi

# ---------------------------------------------------------------------------
# 5. Non-sensitive content survives — redaction must not be a black hole
# ---------------------------------------------------------------------------
out=$("$STACKLOG" --host h1-nvidia --event verify --action smoke.chat_completion \
        --status ok --duration-ms 812 --models 'qwen2.5-coder-7b' \
        --hw '{"gpu":"NVIDIA RTX 4070","vram_gib":12}' \
        --detail '{"aliases":2,"latency_ms":812}')

line=$(tail -n 1 "$out")
if [[ "$(jq -r '.hw.gpu' <<<"$line")" == "NVIDIA RTX 4070" ]] \
   && [[ "$(jq -r '.models[0]' <<<"$line")" == "qwen2.5-coder-7b" ]] \
   && [[ "$(jq -r '.detail.latency_ms' <<<"$line")" == "812" ]]; then
  ok "non-sensitive fields survive redaction"
else
  bad "redaction destroyed non-sensitive fields"
fi

# ---------------------------------------------------------------------------
# 6. Schema shape (T6.4) — every line parses and carries the required keys
# ---------------------------------------------------------------------------
required='["ts","run_id","host","actor","event","action","status","duration_ms","hw","models","detail","error"]'
bad_lines=0
while IFS= read -r l; do
  jq -e --argjson req "$required" \
     'if ([keys_unsorted[]] | sort) == ($req | sort) then . else empty end' \
     <<<"$l" >/dev/null 2>&1 || bad_lines=$((bad_lines + 1))
done < <(cat "$TMPDIR_TEST"/*.jsonl)

if [[ "$bad_lines" -eq 0 ]]; then
  ok "every emitted line is schema-valid JSONL"
else
  bad "$bad_lines line(s) failed schema validation"
fi

# ---------------------------------------------------------------------------
# 7. Invalid enum values are rejected
# ---------------------------------------------------------------------------
if "$STACKLOG" --host h1-nvidia --event nonsense --action x --status ok >/dev/null 2>&1; then
  bad "writer accepted an invalid --event"
else
  ok "writer rejected an invalid --event"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
