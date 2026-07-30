#!/usr/bin/env bash
# Negative tests for validate_models.py.
#
# A validator that passes everything is worse than no validator, because it
# buys false confidence. Each case below builds a throwaway repo containing
# exactly one defect and asserts the validator rejects it for the right reason.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATOR="$REPO_ROOT/tests/validate_models.py"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

pass=0
fail=0
ok()  { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail + 1)); }

# Build a minimal single-host repo. Callers mutate it to introduce one defect.
scaffold() {
  local root="$1"
  mkdir -p "$root/hosts/h1-nvidia/ansible" \
           "$root/hosts/h1-nvidia/vllm/models" \
           "$root/hosts/h1-nvidia/vllm/chat-templates"

  cat > "$root/hosts/h1-nvidia/ansible/vars.yml" <<'EOF'
host_alias: h1-nvidia
engine: vllm
litellm_port: 4000
vram_budget_gib: 8
active_models:
  - model-a
EOF

  cat > "$root/hosts/h1-nvidia/vllm/models/model-a.yml" <<'EOF'
slug: model-a
engine: vllm
hf_model: org/model-a
image: vllm/vllm-openai:latest
port: 8001
gpu_memory_utilization: 0.9
max_model_len: 16384
max_num_seqs: 2
dtype: auto
vram_estimate_gib: 6
tier: 8g
mandatory: true
notes: fixture
EOF
}

# assert_rejects <case name> <expected substring> <mutator function>
assert_rejects() {
  local name="$1" expect="$2" mutate="$3"
  local root
  root="$TMPROOT/$(echo "$name" | tr ' /' '__')"
  scaffold "$root"
  "$mutate" "$root"

  local output rc
  output="$(python3 "$VALIDATOR" --root "$root" 2>&1)" && rc=0 || rc=$?

  if [[ "$rc" -eq 0 ]]; then
    bad "$name — validator accepted it"
  elif grep -qi -- "$expect" <<<"$output"; then
    ok "$name"
  else
    bad "$name — rejected, but not for the expected reason (wanted /$expect/)"
    sed 's/^/        /' <<<"$output"
  fi
}

printf '\n== validate_models negative cases ==\n'

# Baseline: the clean scaffold must pass, or every case below is meaningless.
scaffold "$TMPROOT/clean"
if python3 "$VALIDATOR" --root "$TMPROOT/clean" >/dev/null 2>&1; then
  ok "clean fixture passes"
else
  bad "clean fixture does not pass — all negative cases are unreliable"
  python3 "$VALIDATOR" --root "$TMPROOT/clean" 2>&1 | sed 's/^/        /'
fi

m_slug_mismatch() {
  sed -i 's/^slug: model-a/slug: model-typo/' "$1/hosts/h1-nvidia/vllm/models/model-a.yml"
}
assert_rejects "T0.4 slug must match filename" "does not match filename stem" m_slug_mismatch

m_missing_field() {
  sed -i '/^max_model_len:/d' "$1/hosts/h1-nvidia/vllm/models/model-a.yml"
}
assert_rejects "T0.3 missing engine-required field" "requires field 'max_model_len'" m_missing_field

m_unknown_slug() {
  sed -i 's/^  - model-a/  - model-does-not-exist/' "$1/hosts/h1-nvidia/ansible/vars.yml"
}
assert_rejects "T0.9 unknown slug in active_models" "has no config at" m_unknown_slug

m_dup_port() {
  sed 's/^slug: model-a/slug: model-b/' "$1/hosts/h1-nvidia/vllm/models/model-a.yml" \
    > "$1/hosts/h1-nvidia/vllm/models/model-b.yml"
  printf '  - model-b\n' >> "$1/hosts/h1-nvidia/ansible/vars.yml"
  sed -i 's/^vram_budget_gib: 8/vram_budget_gib: 32/' "$1/hosts/h1-nvidia/ansible/vars.yml"
}
assert_rejects "T0.5 duplicate engine ports" "claimed by both" m_dup_port

m_over_budget() {
  sed -i 's/^vram_estimate_gib: 6/vram_estimate_gib: 7/' "$1/hosts/h1-nvidia/vllm/models/model-a.yml"
  sed -i 's/^vram_budget_gib: 8/vram_budget_gib: 6/' "$1/hosts/h1-nvidia/ansible/vars.yml"
}
assert_rejects "T0.6 active set exceeds VRAM budget" "vram_budget_gib" m_over_budget

m_tier_ceiling() {
  sed -i 's/^vram_estimate_gib: 6/vram_estimate_gib: 20/' "$1/hosts/h1-nvidia/vllm/models/model-a.yml"
  sed -i 's/^vram_budget_gib: 8/vram_budget_gib: 40/' "$1/hosts/h1-nvidia/ansible/vars.yml"
}
assert_rejects "T0.13 model exceeds its declared tier" "exceeds the 8g tier ceiling" m_tier_ceiling

m_dup_alias() {
  sed 's/^slug: model-a/slug: model-b/; s/^port: 8001/port: 8002/' \
    "$1/hosts/h1-nvidia/vllm/models/model-a.yml" > "$1/hosts/h1-nvidia/vllm/models/model-b.yml"
  cat >> "$1/hosts/h1-nvidia/vllm/models/model-a.yml" <<'EOF'
virtual_models:
  - name: shared-alias
EOF
  cat >> "$1/hosts/h1-nvidia/vllm/models/model-b.yml" <<'EOF'
virtual_models:
  - name: shared-alias
EOF
  printf '  - model-b\n' >> "$1/hosts/h1-nvidia/ansible/vars.yml"
  sed -i 's/^vram_budget_gib: 8/vram_budget_gib: 32/' "$1/hosts/h1-nvidia/ansible/vars.yml"
}
assert_rejects "T0.8 duplicate LiteLLM alias" "exposed by both" m_dup_alias

m_engine_mismatch() {
  sed -i 's/^engine: vllm/engine: llamacpp/' "$1/hosts/h1-nvidia/vllm/models/model-a.yml"
}
assert_rejects "model engine disagrees with host engine" "does not match the host engine" m_engine_mismatch

m_dangling_template() {
  printf 'chat_template_file: nope.jinja\n' >> "$1/hosts/h1-nvidia/vllm/models/model-a.yml"
}
assert_rejects "T0.7 dangling chat_template_file" "not found at" m_dangling_template

m_litellm_collision() {
  sed -i 's/^port: 8001/port: 4000/' "$1/hosts/h1-nvidia/vllm/models/model-a.yml"
}
assert_rejects "engine port collides with gateway" "collides with the LiteLLM gateway" m_litellm_collision

m_parity_violation() {
  mkdir -p "$1/tests"
  cat > "$1/tests/parity.yml" <<'EOF'
required_common_aliases:
  - qwen2.5-coder-7b
hosts:
  - h1-nvidia
EOF
}
assert_rejects "T0.11 host misses a required common alias" "does not expose the required common alias" m_parity_violation

m_bad_tier() {
  sed -i 's/^tier: 8g/tier: enormous/' "$1/hosts/h1-nvidia/vllm/models/model-a.yml"
}
assert_rejects "unknown tier value" "is not one of" m_bad_tier

m_empty_active() {
  sed -i '/^  - model-a/d' "$1/hosts/h1-nvidia/ansible/vars.yml"
}
assert_rejects "empty active_models" "active_models is empty" m_empty_active

m_pi_drift() {
  mkdir -p "$1/pi-config/extensions"
  cat > "$1/pi-config/extensions/lmstack-h1.ts" <<'EOF'
export default function (pi) {
  pi.registerProvider("lmstack-h1", {
    models: [
      { id: "model-that-no-host-serves", name: "drifted" },
    ],
  });
}
EOF
}
assert_rejects "T0.10 pi advertises an unserved model" "which no host exposes" m_pi_drift

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
