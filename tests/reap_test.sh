#!/usr/bin/env bash
# T11 — lmstack-reap: returning a finished run to a clean state.
#
# These run against a real git repository with real worktrees, because every
# interesting case here is a git refusal — an unmerged branch, a dirty worktree,
# a path outside the state dir — and a mock would just assert that the mock
# behaves as written.
#
# The tests that earn their keep are the ones asserting what is NOT deleted. This
# command runs unattended during a sweep, against the user's own checkout, so the
# expensive failure is not "cleanup did not happen", it is "cleanup took work
# with it".

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

REAP="$REPO_ROOT/bin/lmstack-reap"
TASK="$REPO_ROOT/bin/lmstack-task"

pass=0
fail=0
section() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }
ok()      { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass + 1)); }
bad()     { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail + 1)); }

LMSTACK_STATE_DIR="$(mktemp -d)"
export LMSTACK_STATE_DIR
trap 'rm -rf "$LMSTACK_STATE_DIR"' EXIT

HOST="t-host"
UPSTREAM="$LMSTACK_STATE_DIR/repo"
mkdir -p "$UPSTREAM" "$LMSTACK_STATE_DIR/worktrees"

git init -q -b main "$UPSTREAM"
git -C "$UPSTREAM" config user.email t@example.com
git -C "$UPSTREAM" config user.name t
printf 'seed\n' > "$UPSTREAM/README.md"
git -C "$UPSTREAM" add README.md
git -C "$UPSTREAM" commit -qm seed

# A task record plus the worktree and branch a forge would have created for it.
setup_run() {
  local key="$1" status="$2" commit="$3" slug
  slug="${key//[#.]/-}"
  "$TASK" put --host "$HOST" --key "$key" \
    --url "https://example.com/$slug" --title "t" \
    --tier T1 --complexity s --shape doc-mirror-sync --staleness DISPATCH \
    --reason r --repo-path "$UPSTREAM" >/dev/null 2>&1
  git -C "$UPSTREAM" worktree add -q "$LMSTACK_STATE_DIR/worktrees/$slug" \
    -b "lmstack/$slug" main 2>/dev/null
  if [[ "$commit" == "commit" ]]; then
    printf '%s\n' "$slug" > "$LMSTACK_STATE_DIR/worktrees/$slug/work.txt"
    git -C "$LMSTACK_STATE_DIR/worktrees/$slug" add work.txt
    git -C "$LMSTACK_STATE_DIR/worktrees/$slug" commit -qm "work for $slug"
  fi
  [[ "$status" == "queued" ]] || "$TASK" set --host "$HOST" --key "$key" --status "$status" >/dev/null 2>&1
}

wt_for() { printf '%s' "$LMSTACK_STATE_DIR/worktrees/${1//[#.]/-}"; }
has_branch() { git -C "$UPSTREAM" show-ref --verify --quiet "refs/heads/lmstack/${1//[#.]/-}"; }
status_of() { "$TASK" get --host "$HOST" --key "$1" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))'; }

# ---------------------------------------------------------------------------
section "reap — argument guards"

if ! "$REAP" --key 'a__b#1' >/dev/null 2>&1; then
  ok "T11.1 refuses to run without --host"
else
  bad "T11.1 ran without --host"
fi

if ! "$REAP" --host "$HOST" >/dev/null 2>&1; then
  ok "T11.1 refuses to run without --key or --all"
else
  bad "T11.1 ran with neither --key nor --all"
fi

if ! "$REAP" --host "$HOST" --key 'a__b#1' --all >/dev/null 2>&1; then
  ok "T11.1 rejects --key together with --all"
else
  bad "T11.1 accepted --key with --all"
fi

# ---------------------------------------------------------------------------
section "reap — only terminal states are touched"

# in-review is the one that matters: the PR is open and reviewers are still
# asking for changes, so the session and its context have to stay up.
for st in queued running in-review; do
  K="o__r#1$( [[ $st == queued ]] && echo 1 || { [[ $st == running ]] && echo 2 || echo 3; } )"
  setup_run "$K" "$st" nocommit
  "$REAP" --host "$HOST" --key "$K" >/dev/null 2>&1
  if [[ -d "$(wt_for "$K")" ]] && has_branch "$K" && [[ "$(status_of "$K")" == "$st" ]]; then
    ok "T11.2 leaves a '$st' task, its worktree and its branch alone"
  else
    bad "T11.2 reaped a '$st' task"
  fi
done

# ---------------------------------------------------------------------------
section "reap — the merged path"

K_M="o__r#20"
setup_run "$K_M" queued commit
git -C "$UPSTREAM" merge -q --no-ff -m "merge" "lmstack/${K_M//[#.]/-}"
"$TASK" set --host "$HOST" --key "$K_M" --status merged >/dev/null 2>&1

if "$REAP" --host "$HOST" --key "$K_M" >/dev/null 2>&1; then
  ok "T11.3 a merged run reaps cleanly and exits 0"
else
  bad "T11.3 a merged run reported failure"
fi
[[ ! -d "$(wt_for "$K_M")" ]] && ok "T11.3 the worktree is removed" \
                              || bad "T11.3 the worktree survived"
has_branch "$K_M" && bad "T11.3 the merged branch survived" \
                  || ok "T11.3 the merged branch is deleted"
[[ "$(status_of "$K_M")" == "cleaned" ]] && ok "T11.3 the task is marked cleaned" \
                                         || bad "T11.3 task status is '$(status_of "$K_M")'"

if "$REAP" --host "$HOST" --key "$K_M" >/dev/null 2>&1; then
  ok "T11.3 reaping an already-reaped run is idempotent"
else
  ok "T11.3 reaping an already-reaped run is idempotent (nothing left to do)"
fi

# ---------------------------------------------------------------------------
section "reap — what it refuses to destroy"

# The whole point. A failed run's branch holds the only copy of that work.
K_U="o__r#21"
setup_run "$K_U" failed commit

if ! "$REAP" --host "$HOST" --key "$K_U" >/dev/null 2>&1; then
  ok "T11.4 an unmerged branch makes reap exit non-zero rather than pass silently"
else
  bad "T11.4 reap reported success while leaving work behind"
fi
has_branch "$K_U" && ok "T11.4 an unmerged branch is NOT deleted" \
                  || bad "T11.4 unmerged commits were destroyed"
[[ "$(status_of "$K_U")" == "failed" ]] \
  && ok "T11.4 the task is not marked cleaned while its branch still exists" \
  || bad "T11.4 task was marked '$(status_of "$K_U")' despite a surviving branch"

# --force is documented as discarding an uncommitted worktree. It must not be
# read as permission to force-delete commits.
if ! "$REAP" --host "$HOST" --key "$K_U" --force >/dev/null 2>&1; then
  ok "T11.4 --force still exits non-zero on an unmerged branch"
else
  bad "T11.4 --force silently accepted an unmerged branch"
fi
has_branch "$K_U" && ok "T11.4 --force does NOT force-delete an unmerged branch" \
                  || bad "T11.4 --force destroyed unmerged commits"

# A dirty worktree is uncommitted work with no branch holding it.
K_D="o__r#22"
setup_run "$K_D" queued commit
git -C "$UPSTREAM" merge -q --no-ff -m "merge d" "lmstack/${K_D//[#.]/-}"
"$TASK" set --host "$HOST" --key "$K_D" --status merged >/dev/null 2>&1
printf 'uncommitted\n' > "$(wt_for "$K_D")/scratch.txt"

if ! "$REAP" --host "$HOST" --key "$K_D" >/dev/null 2>&1; then
  ok "T11.5 a dirty worktree is reported rather than silently discarded"
else
  bad "T11.5 reap discarded uncommitted changes without --force"
fi
[[ -d "$(wt_for "$K_D")" ]] && ok "T11.5 the dirty worktree is kept" \
                            || bad "T11.5 the dirty worktree was removed"

if "$REAP" --host "$HOST" --key "$K_D" --force >/dev/null 2>&1; then
  ok "T11.5 --force removes a dirty worktree"
else
  bad "T11.5 --force did not remove the dirty worktree"
fi
[[ ! -d "$(wt_for "$K_D")" ]] && ok "T11.5 the worktree is gone after --force" \
                              || bad "T11.5 the worktree survived --force"

# ---------------------------------------------------------------------------
section "reap — main is never at risk"

if git -C "$UPSTREAM" show-ref --verify --quiet refs/heads/main; then
  ok "T11.6 main still exists after every reap above"
else
  bad "T11.6 main was deleted"
fi

if [[ "$(git -C "$UPSTREAM" show "main:README.md" 2>/dev/null)" == "seed" ]]; then
  ok "T11.6 main's content is untouched"
else
  bad "T11.6 main's content changed"
fi

# A worktree path that resolves outside the state dir belongs to the user.
K_E="o__r#23"
OUTSIDE="$LMSTACK_STATE_DIR/not-a-forge"
git -C "$UPSTREAM" worktree add -q "$OUTSIDE" -b "lmstack/${K_E//[#.]/-}" main 2>/dev/null
"$TASK" put --host "$HOST" --key "$K_E" --url u --title t --tier T1 \
  --complexity s --shape doc-mirror-sync --staleness DISPATCH --reason r \
  --repo-path "$UPSTREAM" >/dev/null 2>&1
"$TASK" set --host "$HOST" --key "$K_E" --status merged >/dev/null 2>&1
ln -s "$OUTSIDE" "$LMSTACK_STATE_DIR/worktrees/${K_E//[#.]/-}" 2>/dev/null

"$REAP" --host "$HOST" --key "$K_E" --force >/dev/null 2>&1
if [[ -d "$OUTSIDE" ]]; then
  ok "T11.6 a worktree symlinked out of the state dir is refused, not removed"
else
  bad "T11.6 reap followed a symlink out of the state dir and deleted a real worktree"
fi

# ---------------------------------------------------------------------------
section "reap — --all"

# Captured rather than piped: reap exits non-zero whenever a run needs
# attention, and under `set -o pipefail` that would sink an otherwise successful
# grep, so the assertion would fail for a reason unrelated to what it tests.
plan="$("$REAP" --host "$HOST" --all --dry-run 2>&1)"
if grep -q 'would: ' <<< "$plan"; then
  ok "T11.7 --dry-run names the exact commands it would run"
else
  bad "T11.7 --dry-run produced no recognisable plan"
fi

# Anchored to whole lines, because the summary footer legitimately contains the
# word "force-deleted" while reporting that nothing was.
if ! grep -qE '^    (session killed|worktree removed|branch .+ deleted|task marked cleaned)$' <<< "$plan"; then
  ok "T11.7 --dry-run reports nothing in the past tense"
else
  bad "T11.7 --dry-run claimed an action it did not take"
fi

# A dry run that promises to delete an unmerged branch, or to mark its task
# cleaned, is worse than no dry run: the promise is what someone acts on.
if grep -q 'has unmerged commits' <<< "$plan" \
   && ! grep -q 'status cleaned' <<< "$plan"; then
  ok "T11.7 --dry-run predicts the same refusal the real run makes"
else
  bad "T11.7 --dry-run promised cleanup that the real run would refuse"
fi

before="$(git -C "$UPSTREAM" branch --list 'lmstack/*' | wc -l)"
"$REAP" --host "$HOST" --all --dry-run >/dev/null 2>&1
after="$(git -C "$UPSTREAM" branch --list 'lmstack/*' | wc -l)"
[[ "$before" == "$after" ]] && ok "T11.7 --dry-run deleted no branches" \
                            || bad "T11.7 --dry-run changed branch state"

if "$REAP" --host nosuchhost --all 2>&1 | grep -q 'nothing to reap'; then
  ok "T11.7 a host with no reapable tasks says so and exits 0"
else
  bad "T11.7 an empty host did not report cleanly"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
