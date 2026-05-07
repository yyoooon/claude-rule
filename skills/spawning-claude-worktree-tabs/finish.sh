#!/usr/bin/env bash
# Merge wt/<source>/<suffix> worktree(s) back into the source branch via
# rebase + ff-merge (no merge commits), then remove the worktree, branch,
# and cmux tab.
#
# See SKILL.md for full documentation.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: finish.sh (-s suffix1,suffix2,... | --all) [--no-merge]

  -s suffixes     comma-separated worktree suffixes (e.g., "login,signup")
  --all           target every wt/<current-branch>/* worktree
  --no-merge      skip merge, only cleanup (worktree + branch + cmux tab)

Default behavior, per worktree:
  1. Verify clean working tree in the worktree.
  2. Rebase wt/<source>/<suffix> onto <source>   (linear history).
  3. Fast-forward merge into <source>            (no merge commit).
  4. Remove worktree, delete branch, close cmux tab.

If --no-merge is set, steps 2 and 3 are skipped — use when discarding work
or when the merge was already done externally (e.g., via PR).
EOF
}

SUFFIXES_ARG=""
ALL=0
NO_MERGE=0

while [[ $# -gt 0 ]]; do
  case $1 in
    -s) SUFFIXES_ARG="${2:-}"; shift 2 ;;
    --all) ALL=1; shift ;;
    --no-merge) NO_MERGE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$SUFFIXES_ARG" && $ALL -eq 0 ]]; then
  echo "ERROR: must specify -s <suffixes> or --all" >&2
  usage
  exit 1
fi

# --- verify state ---
command -v cmux >/dev/null 2>&1 \
  || { echo "ERROR: cmux not found in PATH" >&2; exit 1; }

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || { echo "ERROR: not inside a git repo" >&2; exit 1; }

GIT_DIR=$(cd "$(git rev-parse --git-dir)" && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" && pwd -P)
[[ "$GIT_DIR" == "$GIT_COMMON" ]] \
  || { echo "ERROR: must run from main checkout, not a linked worktree" >&2; exit 1; }

SOURCE_BRANCH=$(git branch --show-current)
[[ -n "$SOURCE_BRANCH" ]] \
  || { echo "ERROR: detached HEAD — switch to the source branch first" >&2; exit 1; }

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

# main checkout: ff-merge survives untracked files, so only block on
# uncommitted tracked changes (modified or staged).
if [[ $NO_MERGE -eq 0 ]] && [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  echo "ERROR: main checkout has uncommitted tracked changes — commit or stash first." >&2
  exit 1
fi

# --- collect target suffixes ---
declare -a TARGETS=()

if [[ $ALL -eq 1 ]]; then
  while IFS= read -r line; do
    if [[ "$line" == "branch refs/heads/wt/$SOURCE_BRANCH/"* ]]; then
      TARGETS+=("${line#branch refs/heads/wt/$SOURCE_BRANCH/}")
    fi
  done < <(git worktree list --porcelain)
else
  IFS=',' read -ra TARGETS <<< "$SUFFIXES_ARG"
fi

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  echo "No matching worktrees found for source branch '$SOURCE_BRANCH'."
  exit 0
fi

echo "Source branch: $SOURCE_BRANCH"
echo "Targets:       ${TARGETS[*]}"
echo "Mode:          $([[ $NO_MERGE -eq 1 ]] && echo 'cleanup only' || echo 'merge + cleanup')"
echo

# --- helper: find cmux surface by branch-name title prefix ---
find_surface_by_branch() {
  local branch="$1"
  cmux --json list-pane-surfaces 2>/dev/null | python3 -c "
import json, sys
prefix = sys.argv[1] + ' '
data = json.load(sys.stdin)
for s in data.get('surfaces', []):
    if s.get('title', '').startswith(prefix):
        print(s['ref'])
        break
" "$branch"
}

# --- per-target loop ---
declare -a SUCCESS=()
declare -a SKIPPED=()

for SUFFIX in "${TARGETS[@]}"; do
  SUFFIX="${SUFFIX// /}"  # trim whitespace
  [[ -z "$SUFFIX" ]] && continue

  BRANCH="wt/$SOURCE_BRANCH/$SUFFIX"
  WTREE_REL=".worktrees/$SUFFIX"
  WTREE_ABS="$REPO_ROOT/$WTREE_REL"

  echo "[finish] $SUFFIX  ($BRANCH)"

  if [[ ! -d "$WTREE_ABS" ]]; then
    echo "  SKIP: worktree not found at $WTREE_REL"
    SKIPPED+=("$SUFFIX")
    continue
  fi

  if [[ $NO_MERGE -eq 0 ]]; then
    # 1. worktree clean?
    if [[ -n "$(git -C "$WTREE_ABS" status --porcelain)" ]]; then
      echo "  SKIP: $WTREE_REL has uncommitted changes (commit or stash first)"
      SKIPPED+=("$SUFFIX")
      continue
    fi

    # 2. rebase onto source (linear history)
    if ! git -C "$WTREE_ABS" rebase "$SOURCE_BRANCH" >/dev/null 2>&1; then
      echo "  SKIP: rebase conflict on $BRANCH — aborting rebase"
      git -C "$WTREE_ABS" rebase --abort 2>/dev/null || true
      SKIPPED+=("$SUFFIX")
      continue
    fi

    # 3. ff-merge into source
    if ! git merge --ff-only "$BRANCH" >/dev/null 2>&1; then
      echo "  SKIP: fast-forward merge failed for $BRANCH"
      SKIPPED+=("$SUFFIX")
      continue
    fi
  fi

  # 4. remove worktree
  git worktree remove "$WTREE_REL"

  # 5. delete branch
  if [[ $NO_MERGE -eq 1 ]]; then
    git branch -D "$BRANCH" >/dev/null
  else
    git branch -d "$BRANCH" >/dev/null
  fi

  # 6. close cmux tab
  SURFACE=$(find_surface_by_branch "$BRANCH")
  if [[ -n "$SURFACE" ]]; then
    cmux close-surface --surface "$SURFACE" >/dev/null
    echo "  closed tab: $SURFACE"
  else
    echo "  (no matching cmux tab found — already closed?)"
  fi

  SUCCESS+=("$SUFFIX")
  echo "  done"
done

echo
echo "Finished:  ${#SUCCESS[@]}  (${SUCCESS[*]:-none})"
echo "Skipped:   ${#SKIPPED[@]}  (${SKIPPED[*]:-none})"
