#!/usr/bin/env bash
# T6.1 / T6.2 — the skill's hardware classification, as a pure function.
#
# The skill itself is a prompt, so its judgement cannot be unit-tested. Its
# arithmetic can be, and that is the part that gets someone an OOM at 3am. Every
# case here is a saved probe in tests/fixtures/probe/ and an expected decision.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

CLASSIFY="bin/lmstack-classify"
FIXTURES="tests/fixtures/probe"

pass=0
fail=0

ok()  { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail + 1)); }

# assert_field <fixture> <jq filter> <expected> <label>
assert_field() {
  local fixture="$1" filter="$2" expected="$3" label="$4" got
  got="$(python3 "$CLASSIFY" --probe "$FIXTURES/$fixture.json" 2>&1 | jq -r "$filter" 2>/dev/null)"
  if [[ "$got" == "$expected" ]]; then
    ok "$label"
  else
    bad "$label — expected '$expected', got '$got'"
  fi
}

printf '\n\033[1m== probe classification ==\033[0m\n'

if ! command -v jq >/dev/null 2>&1; then
  printf '  \033[33mSKIP\033[0m jq not installed\n'
  exit 0
fi

# -- T6.1: probe JSON -> host role ------------------------------------------
assert_field nvidia-12g  '.host_role' h1-nvidia "T6.1 NVIDIA + driver -> h1-nvidia"
assert_field nvidia-12g  '.engine'    vllm      "T6.1 NVIDIA -> vllm"
assert_field amd-apu-6g  '.host_role' h2-amd    "T6.1 AMD APU + render node -> h2-amd"
assert_field amd-dgpu-16g '.host_role' h2-amd   "T6.1 AMD dGPU + render node -> h2-amd"
assert_field amd-apu-6g  '.engine'    llamacpp  "T6.1 AMD -> llamacpp"

# Unsupported hosts must say so and must not name a role the user could try.
assert_field no-gpu             '.supported' false "T6.1 no GPU -> unsupported"
assert_field no-gpu             '.host_role' null  "T6.1 no GPU -> no role offered"
assert_field nvidia-no-driver   '.supported' false "T6.1 NVIDIA without a driver -> unsupported"
assert_field amd-no-render-node '.supported' false "T6.1 amdgpu without a render node -> unsupported"

# An unsupported verdict without a remedy is a dead end for the user.
assert_field no-gpu           '.remedy | length > 0' true "T6.1 unsupported verdict carries a remedy"
assert_field nvidia-no-driver '.remedy | length > 0' true "T6.1 missing-driver verdict carries a remedy"

# -- T6.2: small card -> one model, not a pair -------------------------------
assert_field amd-apu-6g '.tier'                '8g'  "T6.2 6 GiB -> tier 8g"
assert_field amd-apu-6g '.recommended | length' 1    "T6.2 6 GiB -> a single model, not a pair"
assert_field amd-apu-6g '.supported'            true "T6.2 6 GiB is still a usable host"

# 6 GiB minus the 1 GiB reserve cannot hold the 6 GiB default. Silently
# recommending it anyway is the exact failure this test exists to catch.
assert_field amd-apu-6g \
  '.recommended | index("qwen2.5-coder-7b") == null' true \
  "T6.2 the 6 GiB default is not recommended on a 5 GiB budget"

# A larger card may have a pair; that is the point of having a budget at all.
assert_field amd-dgpu-16g '.recommended | length > 1' true \
  "T6.2 20 GiB fits more than one model"
assert_field nvidia-12g '.recommended | index("qwen2.5-coder-7b") != null' true \
  "T6.2 12 GiB gets the mandatory default"

# -- Arithmetic is shown, not just asserted ----------------------------------
# The plan requires the skill to show its working. An empty list would let it
# present a recommendation as an oracle.
assert_field nvidia-12g  '.arithmetic | length > 2' true "recommendation shows its arithmetic"
assert_field amd-apu-6g  '.arithmetic | length > 2' true "small-card recommendation shows its arithmetic"

# On a unified-memory APU the VRAM figure is a carve-out and the GTT budget is
# the real ceiling. Reading the wrong one calls a working laptop unsupported.
assert_field amd-apu-6g '.usable_gib' 6 "APU budget comes from GTT, not the VRAM carve-out"

# NVIDIA unified memory (Grace Blackwell / Grace Hopper / Jetson) is the
# analogue: nvidia-smi returns N/A for memory.total because there is no separate
# framebuffer. The fixture stores what a correct probe reports — a real
# vram_gib populated via CUDA. If the classifier miscounts this class of host
# it calls a $4k box unsupported, which happened once and is what this catches.
assert_field nvidia-gb10-unified '.supported'  true      "T6.2 GB10 unified memory is supported"
assert_field nvidia-gb10-unified '.host_role'  h1-nvidia "T6.2 GB10 -> h1-nvidia"
assert_field nvidia-gb10-unified '.usable_gib' 119       "T6.2 GB10 budget is the whole unified pool"
assert_field nvidia-gb10-unified '.recommended | length > 0' true \
  "T6.2 GB10 recommends at least the default"

# AMD parity for the same shape: sysfs blind (containers with restricted /sys,
# amdgpu still initialising), vulkaninfo's DEVICE_LOCAL heap populated. This is
# the deterministic fallback — the probe writes it into gtt_gib. Classify must
# treat it as a usable budget, not zero.
assert_field amd-apu-vulkan-fallback '.supported'  true   "T6.2 AMD APU with vulkan-only budget is supported"
assert_field amd-apu-vulkan-fallback '.host_role'  h2-amd "T6.2 AMD APU with vulkan-only budget -> h2-amd"
assert_field amd-apu-vulkan-fallback '.usable_gib' 21     "T6.2 vulkan DEVICE_LOCAL heap is the budget when sysfs is blind"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
