#!/usr/bin/env bash
# T6.3 — `skill-install` binds the correct absolute repo path.
# T6.7 — the skill still resolves a repository when nothing bound one.
#
# The installed skill runs from the agent's skill directory, so a relative path
# to the playbooks would resolve against the wrong tree. The install substitutes
# an absolute path; if that silently failed the skill would look correct and then
# be unable to find anything.
#
# Most people never run this installer — they drop the skill directory in from a
# tarball and let Phase 0 clone the repository. T6.7 covers that path, which is
# the common one and the one with no substitution behind it.
#
# HOME is redirected to a scratch directory, so this never touches the real
# ~/.claude, ~/.config/opencode or ~/.agents.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

pass=0
fail=0
ok()  { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail + 1)); }

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

printf '\n\033[1m== skill install ==\033[0m\n'

# -- The repo copy keeps the placeholder ------------------------------------
# If it ever gets a real path baked in, the checked-in file becomes specific to
# one machine and the diff churns on every contributor's install.
if grep -q '{{LMSTACK_REPO}}' skills/lmstack/SKILL.md; then
  ok "the tracked SKILL.md keeps the {{LMSTACK_REPO}} placeholder"
else
  bad "the tracked SKILL.md has no {{LMSTACK_REPO}} placeholder to substitute"
fi

# -- Install into a fake HOME ------------------------------------------------
mkdir -p "$scratch/home/.claude"
if HOME="$scratch/home" skills/install.sh --agent claude >"$scratch/out" 2>&1; then
  ok "install completed"
else
  bad "install failed"
  sed 's/^/        /' "$scratch/out"
fi

dest="$scratch/home/.claude/skills/lmstack"

if [[ -f "$dest/SKILL.md" ]]; then
  ok "SKILL.md landed in the agent skill directory"
else
  bad "SKILL.md is missing from $dest"
fi

# -- T6.3: the substitution actually happened --------------------------------
if [[ -f "$dest/SKILL.md" ]] && ! grep -q '{{LMSTACK_REPO}}' "$dest/SKILL.md"; then
  ok "T6.3 no unsubstituted placeholder in the installed copy"
else
  bad "T6.3 the installed SKILL.md still contains {{LMSTACK_REPO}}"
fi

if [[ -f "$dest/SKILL.md" ]] && grep -qF "$REPO_ROOT" "$dest/SKILL.md"; then
  ok "T6.3 installed copy names the absolute repo path"
else
  bad "T6.3 installed copy does not contain $REPO_ROOT"
fi

# A relative path here is the bug this test exists to catch. The binding lives
# in Phase 0's resolution snippet, as the `bound=` assignment.
if [[ -f "$dest/SKILL.md" ]]; then
  bound="$(grep -o "^bound='[^']*'" "$dest/SKILL.md" | head -n1 | sed "s/^bound='//; s/'\$//")"
  if [[ "$bound" == /* ]]; then
    ok "T6.3 the bound path is absolute"
  else
    bad "T6.3 the bound path '$bound' is not absolute"
  fi
fi

# -- T6.7: the standalone path resolves without an install -------------------
# Most people never run skills/install.sh — they drop the skill directory in and
# let Phase 0 clone the repo. That leaves the placeholder unsubstituted, so the
# resolution snippet has to fall through to the default location. It is shell
# living in a markdown file, which nothing else executes, so run it here.
snippet="$scratch/phase0.sh"
awk '/^bound=/, /^echo/' skills/lmstack/SKILL.md >"$snippet"

if [[ -s "$snippet" ]]; then
  ok "T6.7 extracted the Phase 0 resolution snippet"
else
  bad "T6.7 could not find the Phase 0 resolution snippet in SKILL.md"
fi

mkdir -p "$scratch/home/lmstack/hosts"
got="$(HOME="$scratch/home" LMSTACK_REPO='' bash "$snippet" 2>&1)"
if [[ "$got" == "$scratch/home/lmstack" ]]; then
  ok "T6.7 unsubstituted skill resolves to the default clone location"
else
  bad "T6.7 default resolution gave '$got'"
fi

got="$(HOME="$scratch/empty-home" LMSTACK_REPO='' bash "$snippet" 2>&1)"
if [[ "$got" == "NOT FOUND" ]]; then
  ok "T6.7 reports NOT FOUND rather than a path that does not exist"
else
  bad "T6.7 with no repo anywhere gave '$got'"
fi

# -- The whole skill is installed, not just the prompt -----------------------
for f in scripts/probe-host.sh scripts/classify.py scripts/stacklog.sh \
         references/troubleshooting.md references/stacklog-schema.md; do
  if [[ -f "$dest/$f" ]]; then
    ok "installed $f"
  else
    bad "$f is missing from the installed copy"
  fi
done

if [[ -x "$dest/scripts/probe-host.sh" ]]; then
  ok "probe-host.sh is executable in the installed copy"
else
  bad "probe-host.sh is not executable in the installed copy"
fi

# -- Re-running replaces rather than merges ----------------------------------
# A stale file left behind by a rename is invisible until the skill reads it.
touch "$dest/references/stale-from-an-old-version.md"
HOME="$scratch/home" skills/install.sh --agent claude >/dev/null 2>&1
if [[ ! -f "$dest/references/stale-from-an-old-version.md" ]]; then
  ok "re-install removes files no longer in the repo"
else
  bad "re-install left a stale file behind"
fi

# -- Not creating config trees for agents the user does not have -------------
# A bulk install must not scatter ~/.config/opencode onto a machine that has
# never run opencode.
rm -rf "$scratch/home2"
mkdir -p "$scratch/home2/.claude"
HOME="$scratch/home2" skills/install.sh >/dev/null 2>&1
if [[ -d "$scratch/home2/.claude/skills/lmstack" && ! -d "$scratch/home2/.config/opencode" ]]; then
  ok "bulk install skips agents that are not configured"
else
  bad "bulk install created a config tree for an unconfigured agent"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
