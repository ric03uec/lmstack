#!/usr/bin/env bash
# Install the lmstack skill for Claude Code, opencode, or pi.
#
#   make skill-install              # every agent directory that exists
#   make skill-install AGENT=claude # just one
#   skills/install.sh --list        # show what would be installed where
#
# The installed copy has the absolute path of this repository substituted for
# {{LMSTACK_REPO}} in SKILL.md. Without that the skill has no way to find the
# playbooks: it runs from the agent's skill directory, not from here. T6.3 is
# that substitution.
#
# Re-running is safe. The skill directory is replaced, not merged, so a rename
# in the repo does not leave an orphaned file behind in the installed copy.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_SRC="$REPO_ROOT/skills/lmstack"
SKILL_NAME="lmstack"

# Agent name -> skills directory. A directory is only written if its parent
# already exists, so installing does not create a config tree for an agent the
# user does not have.
agent_dir() {
  case "$1" in
    claude)   printf '%s/.claude/skills' "$HOME" ;;
    opencode) printf '%s/.config/opencode/skills' "$HOME" ;;
    pi)       printf '%s/.agents/skills' "$HOME" ;;
    *)        return 1 ;;
  esac
}

readonly AGENTS=(claude opencode pi)

die() { printf 'skill-install: %s\n' "$1" >&2; exit 1; }
info() { printf '%s\n' "$1"; }

list_only=false
only_agent=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list)  list_only=true; shift ;;
    --agent) only_agent="$2"; shift 2 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -d "$SKILL_SRC" ]] || die "$SKILL_SRC does not exist"
[[ -f "$SKILL_SRC/SKILL.md" ]] || die "$SKILL_SRC/SKILL.md does not exist"

if [[ -n "$only_agent" ]]; then
  agent_dir "$only_agent" >/dev/null || die "unknown agent '$only_agent' (claude|opencode|pi)"
  targets=("$only_agent")
else
  targets=("${AGENTS[@]}")
fi

installed=0
skipped=()

for agent in "${targets[@]}"; do
  dir="$(agent_dir "$agent")"
  parent="$(dirname "$dir")"

  # An explicit --agent is a request, so create the tree. A bulk install only
  # touches agents the user already has configured.
  if [[ ! -d "$parent" && -z "$only_agent" ]]; then
    skipped+=("$agent (no $parent)")
    continue
  fi

  dest="$dir/$SKILL_NAME"

  if [[ "$list_only" == true ]]; then
    info "would install -> $dest"
    installed=$((installed + 1))
    continue
  fi

  mkdir -p "$dir"
  rm -rf "$dest"
  cp -r "$SKILL_SRC" "$dest"

  # The path binding. Done on the installed copy only — the repo's SKILL.md
  # keeps the placeholder so it stays machine-independent and reviewable.
  # REPO_ROOT is a filesystem path and may contain characters sed treats as
  # special in a replacement, so | is the delimiter and & is escaped.
  sed -i "s|{{LMSTACK_REPO}}|${REPO_ROOT//&/\\&}|g" "$dest/SKILL.md"

  if grep -q '{{LMSTACK_REPO}}' "$dest/SKILL.md"; then
    die "path substitution failed in $dest/SKILL.md"
  fi

  find "$dest/scripts" -name '*.sh' -exec chmod +x {} + 2>/dev/null || true

  info "installed -> $dest"
  installed=$((installed + 1))
done

if [[ ${#skipped[@]} -gt 0 ]]; then
  printf '\nskipped (agent not configured on this machine):\n'
  printf '  %s\n' "${skipped[@]}"
  printf 'Force one with: skills/install.sh --agent <name>\n'
fi

if [[ $installed -eq 0 ]]; then
  die "no agent directories found. Pick one explicitly: skills/install.sh --agent claude"
fi

if [[ "$list_only" == false ]]; then
  cat <<EOF

The skill is bound to $REPO_ROOT.
Moving or renaming this repository means re-running the install.

Now ask your agent:

  use the lmstack skill to give me a starting point
EOF
fi
