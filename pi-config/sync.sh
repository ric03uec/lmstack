#!/usr/bin/env bash
# Install lmstack's pi configuration onto this machine, or capture it back.
#
#   ./sync.sh install   # pi-config/ -> ~/.pi/agent/   (default)
#   ./sync.sh dump      # ~/.pi/agent/ -> pi-config/
#   ./sync.sh install --yes   # no confirmation prompt (CI, tests)
#
# Two things this does that a plain `cp` of each file would not:
#
#   1. It copies extensions/. The script this was ported from synced
#     settings.json and npm/package.json only, so a fresh machine got a
#     settings file listing extension paths that did not exist. pi then starts
#     with no providers registered and no error worth reading. T4.1 is that
#     regression.
#
#   2. It MERGES settings.json and npm/package.json instead of overwriting
#      them. Anyone using pi already has their own packages list, and lmstack is
#      one part of their setup, not a replacement for it. `dump` is symmetric:
#      it captures the lmstack-owned entries and leaves the rest of the user's
#      configuration in their own tree where it belongs.
#
# extensions/.env is never copied in either direction. It holds a LiteLLM key.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${PI_AGENT_DIR:-$HOME/.pi/agent}"

# The entries this repo owns. Everything else in the user's settings is theirs.
readonly OWNED_PACKAGES=(
  "extensions/lmstack-h1.ts"
  "extensions/lmstack-h2.ts"
  "npm:@narumitw/pi-statusline"
)

die()  { printf 'pi-sync: %s\n' "$1" >&2; exit 1; }
step() { printf '\n\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '  ok  %s\n' "$1"; }

command -v jq >/dev/null 2>&1 || die "jq is required to merge JSON without clobbering your settings"

mode="install"
assume_yes=false
skip_npm=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    install|dump) mode="$1"; shift ;;
    -y|--yes)     assume_yes=true; shift ;;
    --no-npm)     skip_npm=true; shift ;;
    -h|--help)    sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)            die "unknown argument: $1" ;;
  esac
done

confirm() {
  $assume_yes && return 0
  read -rp "$1 [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

show_diff() {
  local src="$1" dst="$2" label="$3"
  if [[ ! -f "$dst" ]]; then
    printf '  %s: new\n' "$label"
  elif diff -q "$src" "$dst" >/dev/null 2>&1; then
    printf '  %s: unchanged\n' "$label"
  else
    printf '  %s:\n' "$label"
    diff -u "$dst" "$src" | sed 's/^/    /' || true
  fi
}

owned_json() { printf '%s\n' "${OWNED_PACKAGES[@]}" | jq -Rn '[inputs]'; }

# The user's packages, with ours appended. `unique` would reorder the list and
# pi loads packages in order, so dedupe by hand instead.
merged_settings() {
  local existing="$1"
  local base='{"packages":[]}'
  [[ -f "$existing" ]] && base="$(cat "$existing")"
  jq --argjson owned "$(owned_json)" '
    .packages = (
      ((.packages // []) + $owned)
      | reduce .[] as $p ([]; if index($p) then . else . + [$p] end)
    )' <<<"$base"
}

# Their dependencies win on conflict for anything we do not own; ours win for
# the entries we do, because that version is what this repo is tested against.
merged_npm() {
  local existing="$1"
  local ours="$SCRIPT_DIR/npm/package.json"
  if [[ -f "$existing" ]]; then
    jq -s '.[0] * {dependencies: ((.[0].dependencies // {}) + (.[1].dependencies // {}))}' \
      "$existing" "$ours"
  else
    cat "$ours"
  fi
}

install_config() {
  step "Installing lmstack pi configuration -> $TARGET"

  local tmp
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064  # expand $tmp now, not at trap time
  trap "rm -rf '$tmp'" EXIT

  merged_settings "$TARGET/settings.json" > "$tmp/settings.json"
  merged_npm "$TARGET/npm/package.json"   > "$tmp/package.json"

  step "Changes to apply"
  show_diff "$tmp/settings.json" "$TARGET/settings.json" "settings.json"
  show_diff "$tmp/package.json" "$TARGET/npm/package.json" "npm/package.json"
  show_diff "$SCRIPT_DIR/pi-statusline.json" "$TARGET/pi-statusline.json" "pi-statusline.json"
  for ext in "$SCRIPT_DIR"/extensions/*.ts; do
    show_diff "$ext" "$TARGET/extensions/$(basename "$ext")" "extensions/$(basename "$ext")"
  done
  if [[ -f "$TARGET/extensions/.env" ]]; then
    printf '  extensions/.env: exists, will not be touched\n'
  else
    printf '  extensions/.env: will be created from the example, for you to fill\n'
  fi

  if ! confirm "Apply?"; then
    printf 'Aborted. Nothing was written.\n'
    exit 0
  fi

  mkdir -p "$TARGET/npm" "$TARGET/extensions"

  install -m 0644 "$tmp/settings.json" "$TARGET/settings.json"; ok "settings.json"
  install -m 0644 "$tmp/package.json" "$TARGET/npm/package.json"; ok "npm/package.json"
  install -m 0644 "$SCRIPT_DIR/pi-statusline.json" "$TARGET/pi-statusline.json"; ok "pi-statusline.json"

  for ext in "$SCRIPT_DIR"/extensions/*.ts; do
    install -m 0644 "$ext" "$TARGET/extensions/$(basename "$ext")"
    ok "extensions/$(basename "$ext")"
  done

  # Never overwrite: this is the one file with a credential in it.
  if [[ ! -f "$TARGET/extensions/.env" ]]; then
    install -m 0600 "$SCRIPT_DIR/extensions/.env.example" "$TARGET/extensions/.env"
    ok "extensions/.env created (0600) — fill in your host URL and key"
  fi

  if $skip_npm; then
    printf '  skipped npm install (--no-npm)\n'
  elif command -v npm >/dev/null 2>&1; then
    step "Installing npm extensions"
    (cd "$TARGET/npm" && npm install --silent) && ok "npm extensions"
  else
    printf '  npm is not installed; skipping the npm-published extensions\n'
  fi

  cat <<EOF

Next:
  1. fill $TARGET/extensions/.env with your host URL and LiteLLM key
  2. pi --list-models        # lmstack-h1 / lmstack-h2 should appear
  3. cp $SCRIPT_DIR/bin/lmstack-ask ~/bin/   # or add pi-config/bin to PATH
EOF
}

dump_config() {
  step "Capturing lmstack pi configuration <- $TARGET"
  [[ -d "$TARGET" ]] || die "$TARGET does not exist; nothing to capture"

  local tmp
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  # Only the owned entries come back, and machine-local state is dropped.
  # Capturing the whole file would drag the user's unrelated packages into a
  # public repo, which is both noise and a small privacy leak.
  jq --argjson owned "$(owned_json)" \
    '{packages: [(.packages // [])[] | select(. as $p | $owned | index($p))]}' \
    "$TARGET/settings.json" > "$tmp/settings.json"

  # Keep our dependency set; take versions from the live tree where it has
  # them. A package the user added for themselves does not become ours.
  if [[ -f "$TARGET/npm/package.json" ]]; then
    jq -s '
      .[0] as $ours | (.[1].dependencies // {}) as $live
      | $ours * {dependencies: ($ours.dependencies | with_entries(.value = ($live[.key] // .value)))}
    ' "$SCRIPT_DIR/npm/package.json" "$TARGET/npm/package.json" > "$tmp/package.json"
  else
    cp "$SCRIPT_DIR/npm/package.json" "$tmp/package.json"
  fi

  step "Changes to capture"
  show_diff "$tmp/settings.json" "$SCRIPT_DIR/settings.json" "settings.json"
  show_diff "$tmp/package.json" "$SCRIPT_DIR/npm/package.json" "npm/package.json"
  [[ -f "$TARGET/pi-statusline.json" ]] &&
    show_diff "$TARGET/pi-statusline.json" "$SCRIPT_DIR/pi-statusline.json" "pi-statusline.json"
  for ext in "$TARGET"/extensions/*.ts; do
    [[ -f "$ext" ]] || continue
    show_diff "$ext" "$SCRIPT_DIR/extensions/$(basename "$ext")" "extensions/$(basename "$ext")"
  done

  if ! confirm "Save to the repo?"; then
    printf 'Aborted. Nothing was written.\n'
    exit 0
  fi

  cp "$tmp/settings.json" "$SCRIPT_DIR/settings.json"; ok "settings.json"
  cp "$tmp/package.json" "$SCRIPT_DIR/npm/package.json"; ok "npm/package.json"
  [[ -f "$TARGET/pi-statusline.json" ]] && {
    cp "$TARGET/pi-statusline.json" "$SCRIPT_DIR/pi-statusline.json"; ok "pi-statusline.json"
  }
  for ext in "$TARGET"/extensions/*.ts; do
    [[ -f "$ext" ]] || continue
    cp "$ext" "$SCRIPT_DIR/extensions/$(basename "$ext")"
    ok "extensions/$(basename "$ext")"
  done

  printf '\nReview with git diff before committing.\n'
}

case "$mode" in
  install) install_config ;;
  dump)    dump_config ;;
esac
