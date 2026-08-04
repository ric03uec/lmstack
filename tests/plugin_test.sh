#!/usr/bin/env bash
# T8 — the repository is a valid Claude Code plugin.
#
# This replaces T6.3, which proved that `skills/install.sh` baked an absolute
# repo path into the installed skill. That mechanism is gone: a plugin knows its
# own root, so the checks that matter now are structural. A plugin that fails
# any of these loads silently wrong — the commands are simply absent, with no
# error anywhere the user will look.
#
# `claude plugin validate` covers the manifests. Everything below covers the
# things it does not: that bin/ is actually invokable, that skill directory
# names match their frontmatter, and that no path-binding placeholder survived.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

pass=0
fail=0
section() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }
ok()      { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass + 1)); }
bad()     { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail + 1)); }
skip()    { printf '  \033[33mSKIP\033[0m %s\n' "$1"; }

# ---------------------------------------------------------------------------
section "manifests"

for manifest in .claude-plugin/plugin.json .claude-plugin/marketplace.json; do
  if [[ ! -f "$manifest" ]]; then
    bad "$manifest is missing"
  elif jq empty "$manifest" 2>/dev/null; then
    ok "$manifest is valid JSON"
  else
    bad "$manifest is not valid JSON"
  fi
done

# The plugin name is the command namespace. Changing it silently renames every
# command the user has in their muscle memory.
name="$(jq -r '.name // empty' .claude-plugin/plugin.json 2>/dev/null)"
if [[ "$name" == "lmstack" ]]; then
  ok "plugin name is 'lmstack' — commands are /lmstack:*"
else
  bad "plugin name is '$name', so commands would be /$name:* "
fi

# The repository is its own marketplace, so the entry has to point at the root.
src="$(jq -r '.plugins[0].source // empty' .claude-plugin/marketplace.json 2>/dev/null)"
if [[ "$src" == "./" ]]; then
  ok "marketplace entry sources the repository root"
else
  bad "marketplace entry source is '$src', expected './'"
fi

entry="$(jq -r '.plugins[0].name // empty' .claude-plugin/marketplace.json 2>/dev/null)"
if [[ "$entry" == "$name" ]]; then
  ok "marketplace entry name matches the plugin name"
else
  bad "marketplace entry is '$entry' but the plugin is '$name' — the entry name wins"
fi

if command -v claude >/dev/null 2>&1; then
  if out="$(claude plugin validate . 2>&1)"; then
    ok "claude plugin validate"
  else
    bad "claude plugin validate"
    sed 's/^/        /' <<<"$out"
  fi
else
  skip "claude not installed — cannot run the official validator"
fi

# ---------------------------------------------------------------------------
section "skills"

mapfile -t skill_dirs < <(find skills -mindepth 1 -maxdepth 1 -type d | sort)

if [[ ${#skill_dirs[@]} -eq 0 ]]; then
  bad "no skills — the plugin would expose no commands at all"
fi

for dir in "${skill_dirs[@]}"; do
  base="$(basename "$dir")"

  if [[ ! -f "$dir/SKILL.md" ]]; then
    bad "$base has no SKILL.md, so it is not a skill"
    continue
  fi

  # The invocation name comes from frontmatter when present and the directory
  # basename otherwise. Letting them disagree means /lmstack:<dir> is not the
  # command, which is only discoverable by trying it.
  fm_name="$(awk '/^---$/{n++; next} n==1 && /^name:/{sub(/^name:[[:space:]]*/,""); print; exit}' "$dir/SKILL.md")"
  if [[ "$fm_name" == "$base" ]]; then
    ok "/$name:$base"
  else
    bad "$dir/SKILL.md declares name '$fm_name' but sits in '$base'"
  fi

  # The description is the entire basis on which the model decides whether a
  # skill is relevant. An empty one makes the command effectively invisible.
  fm_desc="$(awk '/^---$/{n++; next} n==1 && /^description:/{print; exit}' "$dir/SKILL.md")"
  if [[ -n "$fm_desc" ]]; then
    ok "$base declares a description"
  else
    bad "$base has no description in its frontmatter"
  fi
done

# ---------------------------------------------------------------------------
section "bin"

mapfile -t bins < <(find bin -maxdepth 1 -type f 2>/dev/null | sort)

if [[ ${#bins[@]} -eq 0 ]]; then
  bad "bin/ is empty — the skills call these as bare commands"
fi

for b in "${bins[@]}"; do
  base="$(basename "$b")"

  if [[ -x "$b" ]]; then
    ok "$base is executable"
  else
    bad "$base is not executable, so PATH lookup finds it and then fails"
  fi

  if head -c2 "$b" | grep -q '#!'; then
    ok "$base has a shebang"
  else
    bad "$base has no shebang"
  fi

  # bin/ joins the Bash tool's PATH for the whole session, not just for this
  # plugin's own commands. An unprefixed name here would shadow a system binary
  # for every command the user runs while the plugin is enabled.
  if [[ "$base" == lmstack-* ]]; then
    ok "$base is namespaced"
  else
    bad "$base is not prefixed 'lmstack-' and would shadow that name on PATH"
  fi
done

# ---------------------------------------------------------------------------
section "no stale path binding"

# v1 substituted an absolute repository path into the installed SKILL.md. A
# plugin resolves its own root, so a surviving placeholder is a leftover that
# would render literally in the model's context.
if grep -rl '{{LMSTACK_REPO}}' skills bin references 2>/dev/null | grep -q .; then
  bad "a {{LMSTACK_REPO}} placeholder survives:"
  grep -rln '{{LMSTACK_REPO}}' skills bin references 2>/dev/null | sed 's/^/        /'
else
  ok "no {{LMSTACK_REPO}} placeholders remain"
fi

if grep -rn 'LMSTACK_REPO' skills bin 2>/dev/null | grep -q .; then
  bad "LMSTACK_REPO is still referenced:"
  grep -rn 'LMSTACK_REPO' skills bin 2>/dev/null | sed 's/^/        /'
else
  ok "nothing depends on \$LMSTACK_REPO"
fi

# Skills reference bundled files through the plugin root variable. A bare
# relative path resolves against the user's cwd, which is their repository.
missing=0
while IFS= read -r ref; do
  path="${ref#\$\{CLAUDE_PLUGIN_ROOT\}/}"
  [[ -e "$path" ]] || { bad "skills reference a missing file: $path"; missing=1; }
done < <(grep -rho '\${CLAUDE_PLUGIN_ROOT}/[A-Za-z0-9._/-]*' skills 2>/dev/null | sort -u)
[[ $missing -eq 0 ]] && ok "every \${CLAUDE_PLUGIN_ROOT} reference resolves"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
