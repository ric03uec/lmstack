#!/usr/bin/env bash
# T0.1 / T0.2 — yamllint, ansible-lint, shellcheck, and playbook syntax checks.
#
# Every linter is optional: missing ones are reported as SKIP rather than
# failing the run, so a contributor without the full toolchain can still get
# useful signal. CI installs all of them, so nothing is skipped there.
#
#   uv tool install ansible-lint
#   uv tool install yamllint
#   uv tool install shellcheck-py   # PyPI wheel; no sudo needed

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

rc=0
skipped=()

section() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }
ok()      { printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad()     { printf '  \033[31mFAIL\033[0m %s\n' "$1"; rc=1; }
skip()    { printf '  \033[33mSKIP\033[0m %s\n' "$1"; skipped+=("$2"); }

# ---------------------------------------------------------------------------
section "yamllint"
if command -v yamllint >/dev/null 2>&1; then
  if yamllint -c .yamllint.yml .; then ok "yaml style"; else bad "yaml style"; fi
else
  skip "yamllint not installed" "uv tool install yamllint"
fi

# ---------------------------------------------------------------------------
section "shellcheck"
# Everything in bin/ is extensionless so it reads as a command rather than a
# file, so a *.sh glob alone would silently skip the shipped scripts. Match on
# the shebang instead; the python3 ones fall out on their own.
mapfile -t scripts < <({
  find . -name '*.sh' -not -path './website/*' -not -path './.git/*'
  for f in bin/*; do
    [[ -f $f ]] && head -n1 "$f" | grep -qE '^#!.*[ /](bash|sh)$' && printf '%s\n' "$f"
  done
} | sort -u)
if command -v shellcheck >/dev/null 2>&1; then
  if [[ ${#scripts[@]} -eq 0 ]]; then
    ok "no shell scripts to check"
  elif shellcheck --severity=warning "${scripts[@]}"; then
    ok "${#scripts[@]} shell script(s)"
  else
    bad "shellcheck reported issues"
  fi
else
  skip "shellcheck not installed" "uv tool install shellcheck-py"
fi

# ---------------------------------------------------------------------------
section "ansible playbook syntax"
mapfile -t playbooks < <(
  { find hosts -name '*.yml' -path '*/ansible/*' -not -name 'vars.yml' 2>/dev/null
    ls tests/render.yml 2>/dev/null
  } | sort
)
if [[ ${#playbooks[@]} -eq 0 ]]; then
  ok "no playbooks yet"
elif command -v ansible-playbook >/dev/null 2>&1; then
  for pb in "${playbooks[@]}"; do
    if ansible-playbook --syntax-check -i inventory/hosts.ini.example "$pb" >/dev/null 2>&1; then
      ok "$pb"
    else
      bad "$pb"
      ansible-playbook --syntax-check -i inventory/hosts.ini.example "$pb" 2>&1 | sed 's/^/        /'
    fi
  done
else
  skip "ansible-playbook not installed" "uv tool install ansible-core"
fi

# ---------------------------------------------------------------------------
section "ansible-lint"
if [[ ${#playbooks[@]} -eq 0 ]]; then
  ok "no playbooks yet"
elif command -v ansible-lint >/dev/null 2>&1; then
  if ansible-lint "${playbooks[@]}"; then ok "ansible-lint"; else bad "ansible-lint"; fi
else
  skip "ansible-lint not installed" "uv tool install ansible-lint"
fi

# ---------------------------------------------------------------------------
# Secret hygiene. The Python section of .gitignore ignores `env/` for
# virtualenvs, which silently swallowed every host's env directory — templates
# and all. The inverse mistake is worse, so both directions are checked.
section "secret hygiene"
mapfile -t env_examples < <(
  { find hosts -path '*/env/*.env.example' 2>/dev/null
    find pi-config -name '.env.example' 2>/dev/null
  } | sort
)

if [[ ${#env_examples[@]} -eq 0 ]]; then
  ok "no env templates yet"
else
  for example in "${env_examples[@]}"; do
    if git check-ignore -q "$example"; then
      bad "$example is gitignored — it is a template and must be tracked"
    else
      ok "$example is tracked"
    fi

    real="${example%.example}"
    if git check-ignore -q "$real"; then
      ok "$(basename "$real") alongside it would be ignored"
    else
      bad "$real is NOT ignored — a real secret file could be committed"
    fi
  done
fi

mapfile -t tracked_env < <(git ls-files '*.env' | sort)
if [[ ${#tracked_env[@]} -eq 0 ]]; then
  ok "no .env files tracked"
else
  bad "tracked .env files: ${tracked_env[*]}"
fi

# ---------------------------------------------------------------------------
if [[ ${#skipped[@]} -gt 0 ]]; then
  printf '\n\033[33mSkipped checks. To run the full suite:\033[0m\n'
  printf '  %s\n' "${skipped[@]}"
fi

exit "$rc"
