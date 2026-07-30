#!/usr/bin/env bash
# T7 — prove hosts/*-template is a skeleton that still works.
#
# A template is exempt from `make validate` and from the render suite, which
# means nothing would otherwise notice it rotting. This is what notices:
#
#   T7.1  the template has every file a configured host has
#   T7.2  its .j2 templates match the reference host's, comments aside
#   T7.3  filling the placeholders produces a host the validator accepts
#   T7.4  no placeholder survives that fill
#   T7.5  the live catalog does not count the template as a host
#
# The reference host is the one the template was cut from. Improving that
# host's templates without carrying the change across fails T7.2 — deliberately.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

REFERENCE="hosts/h1-nvidia"
ENGINE_DIR="vllm"

pass=0
fail=0
section() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }
ok()      { printf '  \033[32mPASS\033[0m %s\n' "$1"; ((pass++)); }
bad()     { printf '  \033[31mFAIL\033[0m %s\n' "$1"; ((fail++)); }

mapfile -t templates < <(find hosts -maxdepth 1 -name '*-template' -type d | sort)

if [[ ${#templates[@]} -eq 0 ]]; then
  section "template"
  printf '  \033[33mSKIP\033[0m no hosts/*-template directory\n'
  exit 0
fi

# Strip comments and blank lines so a template can explain itself differently
# from the host it was cut from without failing the comparison.
strip_comments() { grep -Ev '^\s*(#|$)' "$1"; }

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

for template in "${templates[@]}"; do
  section "$template"

  # -- T7.1 -----------------------------------------------------------------
  # Model YAMLs are excluded: the template ships none on purpose. AGENTS.md is
  # excluded because both have one and the contents are meant to differ.
  missing=0
  while IFS= read -r ref_file; do
    rel="${ref_file#"$REFERENCE"/}"
    [[ -f "$template/$rel" ]] || { bad "T7.1 missing $rel"; missing=1; }
  done < <(
    find "$REFERENCE" -type f \
      -not -path "$REFERENCE/$ENGINE_DIR/models/*" \
      -not -name 'AGENTS.md' | sort
  )
  [[ $missing -eq 0 ]] && ok "T7.1 has every file $REFERENCE has"

  # -- T7.2 -----------------------------------------------------------------
  while IFS= read -r ref_j2; do
    rel="${ref_j2#"$REFERENCE"/}"
    if [[ ! -f "$template/$rel" ]]; then
      continue   # already reported by T7.1
    elif diff -q <(strip_comments "$ref_j2") <(strip_comments "$template/$rel") >/dev/null; then
      ok "T7.2 $rel matches $REFERENCE"
    else
      bad "T7.2 $rel has drifted from $REFERENCE"
      diff -u <(strip_comments "$ref_j2") <(strip_comments "$template/$rel") | sed 's/^/        /'
    fi
  done < <(find "$REFERENCE" -name '*.j2' | sort)

  # -- T7.3 / T7.4 ----------------------------------------------------------
  # Instantiate into a scratch repo root. validate_models.py takes --root, and
  # skips parity and pi-extension checks when those trees are absent, so a root
  # containing nothing but one host validates cleanly.
  root="$scratch/$(basename "$template")"
  host="h9-test"
  mkdir -p "$root/hosts"
  cp -r "$template" "$root/hosts/$host"

  sed -i \
    -e "s/CHANGE_ME_HOST/$host/g" \
    -e "s/CHANGE_ME_VRAM_BUDGET_GIB/8/" \
    -e 's/^active_models: \[\]$/active_models: [qwen2.5-coder-7b]/' \
    "$root/hosts/$host/ansible/vars.yml"
  sed -i "s/CHANGE_ME_HOST/$host/g" \
    "$root/hosts/$host/ansible/"*.yml \
    "$root/hosts/$host/$ENGINE_DIR/env/stack.env.example"

  cp "$REFERENCE/$ENGINE_DIR/models/qwen2.5-coder-7b.yml" \
     "$root/hosts/$host/$ENGINE_DIR/models/"

  if out="$(python3 tests/validate_models.py --root "$root" 2>&1)"; then
    ok "T7.3 instantiated template validates"
  else
    bad "T7.3 instantiated template fails validation"
    sed 's/^/        /' <<<"$out"
  fi

  # AGENTS.md documents the placeholders by name, so it is expected to mention
  # them after substitution. Everything else must be free of them.
  if leftover="$(grep -rn 'CHANGE_ME' "$root/hosts/$host" --exclude=AGENTS.md)"; then
    bad "T7.4 placeholder survived the fill — the substitution list is incomplete"
    sed 's/^/        /' <<<"$leftover"
  else
    ok "T7.4 no placeholder survives the fill"
  fi
done

# -- T7.5 -------------------------------------------------------------------
section "live catalog"
if python3 tests/validate_models.py | grep -q -- '-template'; then
  bad "T7.5 a template is being validated as a real host"
else
  ok "T7.5 templates are excluded from the live catalog"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
