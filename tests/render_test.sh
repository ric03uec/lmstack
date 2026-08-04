#!/usr/bin/env bash
# T1 — render every host's templates and assert the invariants. No GPU, no
# target machine, no network.
#
#   T1.1  rendered compose passes `docker compose config -q`
#   T1.2  golden-file diff
#   T1.3  every engine port is bound to 127.0.0.1
#   T1.4  postgres publishes no ports
#   T1.5  the LiteLLM routing table has exactly the declared aliases
#
# Bless golden files after an intentional template change:
#   BLESS=1 ./tests/render_test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

RENDER_DIR="tests/.render"
GOLDEN_DIR="tests/golden"
BLESS="${BLESS:-0}"

# The install root the templates render against. Fictional and fixed, so golden
# files are byte-identical on every machine. Must match tests/render.yml.
FIXTURE_ROOT="/home/lmstack/.lmstack"

rc=0
section() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }
ok()      { printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad()     { printf '  \033[31mFAIL\033[0m %s\n' "$1"; rc=1; }
skip()    { printf '  \033[33mSKIP\033[0m %s\n' "$1"; }

# Hosts are renderable only once they have templates; before Phase 1 there are
# none, and this whole suite is a no-op rather than a failure.
#
# `*-template` directories are skeletons to copy, not hosts. Their placeholders
# cannot render. tests/template_test.sh is what keeps them honest instead.
mapfile -t hosts < <(
  find hosts -mindepth 3 -name '*.j2' 2>/dev/null \
    | cut -d/ -f2 | grep -v -- '-template$' | sort -u
)

if [[ ${#hosts[@]} -eq 0 ]]; then
  section "render"
  skip "no host templates yet — nothing to render"
  exit 0
fi

if ! command -v ansible-playbook >/dev/null 2>&1; then
  section "render"
  skip "ansible-playbook not installed — uv tool install ansible-core"
  exit 0
fi

rm -rf "$RENDER_DIR"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
out="$scratch/out"

for host in "${hosts[@]}"; do
  section "$host"

  if ! ansible-playbook tests/render.yml -e "host=$host" >"$out" 2>&1; then
    bad "render failed"
    sed 's/^/        /' "$out"
    continue
  fi
  ok "templates rendered"

  # -- T1.1 -----------------------------------------------------------------
  # `docker compose config` insists every env_file exists, and the rendered
  # paths point at a fictional install root so the golden files stay identical
  # on every machine. Redirect those paths into the scratch dir for validation
  # only — T1.1 is checking structure, not where the bind mounts live.
  compose="$RENDER_DIR/$host/docker-compose.yml"
  if [[ ! -f "$compose" ]]; then
    bad "T1.1 no docker-compose.yml rendered"
  elif ! command -v docker >/dev/null 2>&1; then
    skip "T1.1 docker not installed"
  else
    mkdir -p "$scratch/root"
    printf 'HF_TOKEN=%s\nLITELLM_MASTER_KEY=%s\nLITELLM_DB_PASSWORD=%s\n' \
      render-fixture render-fixture render-fixture >"$scratch/root/stack.env"
    sed "s|$FIXTURE_ROOT|$scratch/root|g" "$compose" >"$scratch/compose.yml"

    if docker compose -f "$scratch/compose.yml" \
        --env-file "$scratch/root/stack.env" config -q 2>"$out"; then
      ok "T1.1 compose file is valid"
    else
      bad "T1.1 compose file rejected by docker compose"
      sed 's/^/        /' "$out"
    fi
  fi

  # -- T1.3 / T1.4 / T1.5 ---------------------------------------------------
  python3 tests/render_assert.py "$host" || rc=1

  # -- T1.2 -----------------------------------------------------------------
  golden="$GOLDEN_DIR/$host"
  if [[ "$BLESS" == "1" ]]; then
    rm -rf "$golden"
    mkdir -p "$GOLDEN_DIR"
    cp -r "$RENDER_DIR/$host" "$golden"
    ok "T1.2 golden files blessed"
  elif [[ ! -d "$golden" ]]; then
    skip "T1.2 no golden files — create them with: BLESS=1 ./tests/render_test.sh"
  elif diff -ru "$golden" "$RENDER_DIR/$host" >"$out"; then
    ok "T1.2 output matches golden files"
  else
    bad "T1.2 output differs from golden files"
    sed 's/^/        /' "$out"
  fi
done

exit "$rc"
