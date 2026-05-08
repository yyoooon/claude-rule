#!/usr/bin/env bash
# Relaunch claude (and restart the dev server) inside existing worktrees
# spawned earlier by spawn.sh. Use when claude died/exited in one or more
# tabs but the worktree itself is still set up — avoids re-running spawn.sh
# (which skips existing worktrees) and avoids the manual `<pm> dev`
# port-collision footgun.
#
# See SKILL.md for full documentation.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: relaunch.sh (-s suffix1,... | --all) [-p prompts] [--no-dev]

  -s suffixes   comma-separated suffixes of existing worktrees (e.g., "a,b")
  --all         every wt/<current-branch>/* worktree
  -p prompts    file with one initial prompt per line (used in order)
  --no-dev      skip restarting dev server (just re-attach claude)

Per worktree:
  1. Stop existing dev server (via dev.pid; falls back to lsof on PORT).
  2. Restart dev with PORT from .env.local; new PID → dev.pid, logs → dev.log.
  3. Find the cmux tab by title prefix; create a new tab if missing.
  4. Send `claude [prompt]` to that tab.

Port comes from <wtree>/.env.local (written by spawn.sh). If absent the
worktree is skipped — we won't guess a port.
EOF
}

SUFFIXES_ARG=""
ALL=0
NO_DEV=0
PROMPTS_FILE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -s) SUFFIXES_ARG="${2:-}"; shift 2 ;;
    --all) ALL=1; shift ;;
    --no-dev) NO_DEV=1; shift ;;
    -p) PROMPTS_FILE="${2:-}"; shift 2 ;;
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

# --- read prompts ---
declare -a PROMPTS=()
if [[ -n "$PROMPTS_FILE" ]]; then
  [[ -f "$PROMPTS_FILE" ]] || { echo "ERROR: prompts file not found: $PROMPTS_FILE" >&2; exit 1; }
  while IFS= read -r line || [[ -n "$line" ]]; do
    PROMPTS+=("$line")
  done < "$PROMPTS_FILE"
fi

# --- anchor surface for new tabs (current pane) ---
ANCHOR_SURFACE=$(cmux --json identify | python3 -c \
  'import json,sys; print(json.load(sys.stdin)["caller"]["surface_ref"])')

# --- detect package manager from lockfile ---
detect_pm() {
  local dir="$1"
  if   [[ -f "$dir/pnpm-lock.yaml" ]]; then echo "pnpm"
  elif [[ -f "$dir/yarn.lock" ]]; then echo "yarn"
  elif [[ -f "$dir/bun.lockb" || -f "$dir/bun.lock" ]]; then echo "bun"
  elif [[ -f "$dir/package-lock.json" ]]; then echo "npm"
  else echo "npm"
  fi
}

# --- find cmux surface by branch-name title prefix (mirrors finish.sh) ---
find_surface_by_branch() {
  local branch="$1"
  cmux --json list-panes 2>/dev/null | python3 -c '
import json, subprocess, sys
prefix = sys.argv[1] + " "
try:
    panes = json.load(sys.stdin).get("panes", [])
except json.JSONDecodeError:
    sys.exit(0)
for p in panes:
    pane_ref = p.get("ref")
    if not pane_ref:
        continue
    out = subprocess.run(
        ["cmux", "--json", "list-pane-surfaces", "--pane", pane_ref],
        capture_output=True, text=True,
    )
    if out.returncode != 0:
        continue
    try:
        data = json.loads(out.stdout)
    except json.JSONDecodeError:
        continue
    for s in data.get("surfaces", []):
        if s.get("title", "").startswith(prefix):
            print(s["ref"])
            sys.exit(0)
' "$branch"
}

echo "Source branch: $SOURCE_BRANCH"
echo "Targets:       ${TARGETS[*]}"
echo "Mode:          $([[ $NO_DEV -eq 1 ]] && echo 'reattach claude only' || echo 'restart dev + reattach claude')"
echo

# --- per-target loop ---
declare -a SUCCESS=()
declare -a SKIPPED=()

for i in "${!TARGETS[@]}"; do
  SUFFIX="${TARGETS[i]// /}"
  [[ -z "$SUFFIX" ]] && continue

  BRANCH="wt/$SOURCE_BRANCH/$SUFFIX"
  WTREE_REL=".worktrees/$SUFFIX"
  WTREE_ABS="$REPO_ROOT/$WTREE_REL"

  echo "[relaunch] $SUFFIX  ($BRANCH)"

  if [[ ! -d "$WTREE_ABS" ]]; then
    echo "  SKIP: worktree not found at $WTREE_REL"
    SKIPPED+=("$SUFFIX")
    continue
  fi

  # Read PORT from .env.local (written by spawn.sh).
  PORT=""
  if [[ -f "$WTREE_ABS/.env.local" ]]; then
    PORT=$(grep -E '^PORT=' "$WTREE_ABS/.env.local" | head -1 | cut -d= -f2)
  fi
  if [[ -z "$PORT" ]]; then
    echo "  SKIP: PORT not found in $WTREE_REL/.env.local — was this worktree created by spawn.sh?"
    SKIPPED+=("$SUFFIX")
    continue
  fi

  # 1. stop existing dev (only if we're going to restart it)
  if [[ $NO_DEV -eq 0 ]]; then
    if [[ -f "$WTREE_ABS/dev.pid" ]]; then
      OLD_PID=$(cat "$WTREE_ABS/dev.pid" 2>/dev/null || true)
      if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
        pkill -P "$OLD_PID" 2>/dev/null || true
        kill "$OLD_PID" 2>/dev/null || true
        echo "  stopped previous dev (PID $OLD_PID)"
      fi
      rm -f "$WTREE_ABS/dev.pid"
    fi
    # Catch any other holder of PORT (untracked dev, stale orphan, etc.).
    HOLDER=$(lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null | head -1 || true)
    if [[ -n "$HOLDER" ]]; then
      pkill -P "$HOLDER" 2>/dev/null || true
      kill "$HOLDER" 2>/dev/null || true
      # Walk up a couple levels to also kill the parent shell that nohup'd it.
      p="$HOLDER"
      for _ in 1 2; do
        p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
        [[ -z "$p" || "$p" -le 1 ]] && break
        kill "$p" 2>/dev/null || true
      done
      echo "  stopped port $PORT holder (PID $HOLDER)"
    fi
    sleep 0.5
  fi

  # 2. find or create the cmux surface
  SURFACE=$(find_surface_by_branch "$BRANCH" || true)
  if [[ -z "$SURFACE" ]]; then
    echo "  no existing tab — creating new tab"
    SURFACE=$(cmux --json tab-action --action new-terminal-right --tab "$ANCHOR_SURFACE" \
      | python3 -c 'import json,sys; print(json.load(sys.stdin)["created_surface_ref"])')
    cmux rename-tab --surface "$SURFACE" "$BRANCH :$PORT" >/dev/null 2>&1 || true
    sleep 0.4
  fi

  # 3. build optional dev block
  DEV_BLOCK=""
  if [[ $NO_DEV -eq 0 ]] && [[ -f "$WTREE_ABS/package.json" ]] \
       && grep -q '"dev"[[:space:]]*:' "$WTREE_ABS/package.json"; then
    pm=$(detect_pm "$WTREE_ABS")
    case "$pm" in
      yarn) dev_cmd="yarn dev" ;;
      pnpm) dev_cmd="pnpm dev" ;;
      bun)  dev_cmd="bun run dev" ;;
      npm|*) dev_cmd="npm run dev" ;;
    esac
    # Same `bash -c '...'` shielding as spawn.sh so zsh history expansion
    # doesn't choke on `$!`. PID is recorded to dev.pid so finish.sh can stop it.
    dev_inner="(PORT=$PORT nohup $dev_cmd > dev.log 2>&1 < /dev/null & echo \$!) > dev.pid"
    DEV_BLOCK=" && bash -c '$dev_inner'"
  fi

  # 4. send command into the tab
  CD_CMD="cd $(printf '%q' "$WTREE_ABS")"
  PROMPT="${PROMPTS[i]:-}"
  if [[ -n "$PROMPT" ]]; then
    CLAUDE_CMD="claude $(printf '%q' "$PROMPT")"
  else
    CLAUDE_CMD="claude"
  fi
  cmux send --surface "$SURFACE" "$CD_CMD$DEV_BLOCK && $CLAUDE_CMD"$'\n'

  echo "  → surface $SURFACE  (PORT=$PORT)"
  SUCCESS+=("$SUFFIX")
done

echo
echo "Relaunched: ${#SUCCESS[@]}  (${SUCCESS[*]:-none})"
echo "Skipped:    ${#SKIPPED[@]}  (${SKIPPED[*]:-none})"
