#!/usr/bin/env bash
# T4.1 / T4.6 — the offline half of the control-host configuration.
#
# T4.2 to T4.5 need a running host and a real model, so they live in the manual
# checklist. What can be tested without one is the file movement, and that is
# where the bug was: the script this was ported from synced settings.json but
# not the extensions it names, producing a pi that starts clean with no
# providers registered.
#
# PI_AGENT_DIR is redirected to a scratch directory, so this never touches a
# real ~/.pi/agent.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

pass=0
fail=0
ok()  { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail + 1)); }

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

printf '\n\033[1m== pi-config sync ==\033[0m\n'

if ! command -v jq >/dev/null 2>&1; then
  printf '  \033[33mSKIP\033[0m jq is not installed\n'
  exit 0
fi

target="$scratch/agent"
run() { PI_AGENT_DIR="$target" pi-config/sync.sh "$@" --yes --no-npm; }

# -- Clean install -----------------------------------------------------------
if run install >"$scratch/out" 2>&1; then
  ok "install completed on an empty target"
else
  bad "install failed on an empty target"
  sed 's/^/        /' "$scratch/out"
fi

# T4.1 — the regression this script exists for.
for ext in lmstack-h1.ts lmstack-h2.ts; do
  if [[ -f "$target/extensions/$ext" ]]; then
    ok "T4.1 extensions/$ext was copied"
  else
    bad "T4.1 extensions/$ext is missing — settings.json names a file that does not exist"
  fi
done

# Every package entry that points at a local file must resolve, or pi starts
# with a provider silently absent.
missing=0
while read -r pkg; do
  [[ "$pkg" == npm:* ]] && continue
  [[ -f "$target/$pkg" ]] || { missing=$((missing + 1)); printf '        dangling: %s\n' "$pkg"; }
done < <(jq -r '.packages[]' "$target/settings.json")
if [[ $missing -eq 0 ]]; then
  ok "T4.1 every local package entry resolves to a file"
else
  bad "T4.1 $missing package entr(ies) point at nothing"
fi

if [[ -f "$target/pi-statusline.json" ]]; then
  ok "pi-statusline.json was copied"
else
  bad "pi-statusline.json is missing"
fi

# -- The credential file -----------------------------------------------------
if [[ -f "$target/extensions/.env" ]]; then
  ok "extensions/.env was seeded from the example"
else
  bad "extensions/.env was not created"
fi

mode="$(stat -c '%a' "$target/extensions/.env" 2>/dev/null)"
if [[ "$mode" == "600" ]]; then
  ok "extensions/.env is 0600"
else
  bad "extensions/.env is mode $mode, expected 600"
fi

printf 'LMSTACK_H2_KEY=sk-do-not-clobber\n' > "$target/extensions/.env"
run install >/dev/null 2>&1
if grep -q 'sk-do-not-clobber' "$target/extensions/.env"; then
  ok "re-install leaves a filled .env alone"
else
  bad "re-install overwrote the .env, destroying the user's key"
fi

# -- Merging, not clobbering -------------------------------------------------
# Someone who already uses pi must not lose their configuration to this.
rm -rf "$target"
mkdir -p "$target"
cat > "$target/settings.json" <<'EOF'
{
  "packages": ["npm:pi-hud", "extensions/my-own-thing.ts"],
  "quietStartup": true
}
EOF

run install >/dev/null 2>&1

if jq -e '.packages | index("npm:pi-hud")' "$target/settings.json" >/dev/null; then
  ok "an existing package entry survives the merge"
else
  bad "the merge dropped a package the user already had"
fi

if jq -e '.quietStartup == true' "$target/settings.json" >/dev/null; then
  ok "an unrelated settings key survives the merge"
else
  bad "the merge dropped an unrelated settings key"
fi

if jq -e '.packages | index("extensions/lmstack-h1.ts")' "$target/settings.json" >/dev/null; then
  ok "the lmstack entries were added"
else
  bad "the lmstack entries were not added"
fi

run install >/dev/null 2>&1
count="$(jq '[.packages[] | select(. == "extensions/lmstack-h1.ts")] | length' "$target/settings.json")"
if [[ "$count" == "1" ]]; then
  ok "install is idempotent — no duplicate package entries"
else
  bad "a second install produced $count copies of the same entry"
fi

# -- T4.6: round trip --------------------------------------------------------
# dump must capture only what this repo owns. Capturing the whole live file
# would drag the user's unrelated packages into a public repository.
dumped="$scratch/dumped"
cp -r pi-config "$dumped"
if PI_AGENT_DIR="$target" "$dumped/sync.sh" dump --yes >"$scratch/dump.out" 2>&1; then
  ok "T4.6 dump completed"
else
  bad "T4.6 dump failed"
  sed 's/^/        /' "$scratch/dump.out"
fi

if jq -e '.packages | index("npm:pi-hud") | not' "$dumped/settings.json" >/dev/null; then
  ok "T4.6 dump did not capture the user's own package entry"
else
  bad "T4.6 dump pulled a package this repo does not own into the tracked file"
fi

if diff -q pi-config/settings.json "$dumped/settings.json" >/dev/null; then
  ok "T4.6 install -> dump round-trips to an identical settings.json"
else
  bad "T4.6 round trip changed settings.json"
  diff -u pi-config/settings.json "$dumped/settings.json" | sed 's/^/        /'
fi

for f in npm/package.json extensions/lmstack-h1.ts extensions/lmstack-h2.ts pi-statusline.json; do
  if diff -q "pi-config/$f" "$dumped/$f" >/dev/null; then
    ok "T4.6 $f round-trips unchanged"
  else
    bad "T4.6 $f changed across the round trip"
  fi
done

# -- The advertised ids are real aliases -------------------------------------
# validate_models.py owns this check (T0.10); assert here that the extensions
# are actually reachable by it, so the check cannot pass by finding no files.
found="$(grep -c 'id: "' pi-config/extensions/*.ts | awk -F: '{s+=$2} END {print s}')"
if [[ "${found:-0}" -ge 2 ]]; then
  ok "T0.10 has $found advertised model id(s) to check"
else
  bad "T0.10 would pass vacuously — no model ids found in the extensions"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
