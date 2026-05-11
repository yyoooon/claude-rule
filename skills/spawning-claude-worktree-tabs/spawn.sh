#!/usr/bin/env bash
# Spawn N parallel Claude instances in cmux tabs, each in its own git worktree.
# See SKILL.md for full documentation.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: spawn.sh -n <N> [-s suffix1,...] [-p prompts] [--layout <mode>] [--no-dev] [--dry-run]

  -n N            number of tabs/panes to spawn (required)
  -s suffixes     comma-separated suffix names; missing positions auto-fill (a, b, c, …)
  -p prompts      file with one initial prompt per line (used in order)
  --layout MODE   how to place each new surface (default: tab)
                    tab          → new cmux tab (anchored to current)
                    split-right  → split right of the previously-spawned surface
                    split-down   → split down of the previously-spawned surface
                    grid         → 2x2 grid (N=3 only): main TL, P1 BL, P2 TR, P3 BR
  --no-dev        skip auto install + dev server (just `cd && claude`)
  --dry-run       print the plan without creating anything

Branch:    wt/<current-branch>/<suffix>
Worktree:  .worktrees/<suffix>
Port:      3001, 3002, 3003, … (passed as PORT env var to the dev server)

Auto dev (default ON, when package.json has a "dev" script):
  Each surface runs `<pm> install && PORT=<port> nohup <pm> dev > dev.log 2>&1 &`
  before launching claude. PID is saved to .worktrees/<s>/dev.pid so finish.sh
  can stop it. Package manager auto-detected from lockfile (yarn/pnpm/bun/npm).
EOF
}

N=""
SUFFIXES_ARG=""
PROMPTS_FILE=""
DRY_RUN=0
NO_DEV=0
LAYOUT="tab"

while [[ $# -gt 0 ]]; do
  case $1 in
    -n) N="${2:-}"; shift 2 ;;
    -s) SUFFIXES_ARG="${2:-}"; shift 2 ;;
    -p) PROMPTS_FILE="${2:-}"; shift 2 ;;
    --layout) LAYOUT="${2:-}"; shift 2 ;;
    --no-dev) NO_DEV=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

[[ "$N" =~ ^[0-9]+$ && "$N" -gt 0 ]] \
  || { echo "ERROR: -n <N> required (positive integer)" >&2; exit 1; }

case "$LAYOUT" in
  tab|split-right|split-down) ;;
  grid)
    [[ "$N" -eq 3 ]] \
      || { echo "ERROR: --layout grid currently supports only -n 3 (got -n $N)" >&2; exit 1; }
    ;;
  *)
    echo "ERROR: --layout must be one of: tab, split-right, split-down, grid (got '$LAYOUT')" >&2
    exit 1 ;;
esac

# --- verify state ---
command -v cmux >/dev/null 2>&1 \
  || { echo "ERROR: cmux not found in PATH" >&2; exit 1; }
cmux current-workspace >/dev/null 2>&1 \
  || { echo "ERROR: cmux daemon not running or no current workspace" >&2; exit 1; }

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || { echo "ERROR: not inside a git repo" >&2; exit 1; }

GIT_DIR=$(cd "$(git rev-parse --git-dir)" && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" && pwd -P)
[[ "$GIT_DIR" == "$GIT_COMMON" ]] \
  || { echo "ERROR: already in a linked worktree — refusing to nest. Switch to the main checkout first." >&2; exit 1; }

SOURCE_BRANCH=$(git branch --show-current)
[[ -n "$SOURCE_BRANCH" ]] \
  || { echo "ERROR: detached HEAD — switch to a branch first" >&2; exit 1; }

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

# --- check if .worktrees needs to be added to .gitignore ---
NEEDS_IGNORE=0
if ! git check-ignore -q .worktrees 2>/dev/null; then
  NEEDS_IGNORE=1
fi

# --- compute suffixes ---
declare -a USER_SUFFIXES=()
if [[ -n "$SUFFIXES_ARG" ]]; then
  IFS=',' read -ra USER_SUFFIXES <<< "$SUFFIXES_ARG"
fi

CHARS="abcdefghijklmnopqrstuvwxyz"
declare -a SUFFIXES=()
for ((i=0; i<N; i++)); do
  if [[ -n "${USER_SUFFIXES[i]:-}" ]]; then
    SUFFIXES[i]="${USER_SUFFIXES[i]}"
  elif [[ $i -lt 26 ]]; then
    SUFFIXES[i]="${CHARS:i:1}"
  else
    SUFFIXES[i]="t$((i+1))"
  fi
done

# --- read prompts ---
declare -a PROMPTS=()
if [[ -n "$PROMPTS_FILE" ]]; then
  [[ -f "$PROMPTS_FILE" ]] || { echo "ERROR: prompts file not found: $PROMPTS_FILE" >&2; exit 1; }
  while IFS= read -r line || [[ -n "$line" ]]; do
    PROMPTS+=("$line")
  done < "$PROMPTS_FILE"
fi

# --- get current cmux surface (anchor for new tabs) ---
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

# --- build install + dev shell snippet for a worktree, or empty string if N/A ---
build_dev_block() {
  local wtree="$1" port="$2"
  [[ $NO_DEV -eq 1 ]] && return 0
  [[ -f "$wtree/package.json" ]] || return 0
  grep -q '"dev"[[:space:]]*:' "$wtree/package.json" || return 0

  local pm install dev
  pm=$(detect_pm "$wtree")
  case "$pm" in
    yarn) install="yarn install"; dev="yarn dev" ;;
    pnpm) install="pnpm install"; dev="pnpm dev" ;;
    bun)  install="bun install";  dev="bun run dev" ;;
    npm|*) install="npm install"; dev="npm run dev" ;;
  esac
  # Wrap the launch in `bash -c '...'` so the single quotes shield `$!` from
  # zsh interactive history expansion (which would error on `!)`). bash inside
  # the quotes still expands `$!` to the backgrounded dev server's PID.
  local dev_inner
  dev_inner="(PORT=$port nohup $dev > dev.log 2>&1 < /dev/null & echo \$!) > dev.pid"
  printf " && %s && bash -c '%s'" "$install" "$dev_inner"
}

# --- copy gitignored allowlist ---
copy_allowlist() {
  local dest="$1"
  shopt -s nullglob
  local patterns=(".env" ".env.local" ".env.development" ".env.production" ".env.staging" ".env.test" ".env.development.local" ".env.production.local" ".mcp.json" ".mcp" ".claude/settings.local.json")
  for pattern in "${patterns[@]}"; do
    for src in $pattern; do
      [[ -e "$src" ]] || continue
      local target="$dest/$src"
      mkdir -p "$(dirname "$target")"
      cp -R "$src" "$target"
    done
  done
  shopt -u nullglob
}

# --- pre-compute split plan (anchor + direction per iter) for non-tab layouts ---
# SPLIT_ANCHOR[i] = "main" or "<j>" (index of CREATED_SURFACES = the j-th spawned)
declare -a SPLIT_ANCHOR=()
declare -a SPLIT_DIR=()

case "$LAYOUT" in
  split-right)
    for ((i=0; i<N; i++)); do
      [[ $i -eq 0 ]] && SPLIT_ANCHOR[i]="main" || SPLIT_ANCHOR[i]="$((i-1))"
      SPLIT_DIR[i]="right"
    done ;;
  split-down)
    for ((i=0; i<N; i++)); do
      [[ $i -eq 0 ]] && SPLIT_ANCHOR[i]="main" || SPLIT_ANCHOR[i]="$((i-1))"
      SPLIT_DIR[i]="down"
    done ;;
  grid)
    # N=3 only (validated above): main TL, P1 BL, P2 TR, P3 BR
    SPLIT_ANCHOR=("main" "main" "0")
    SPLIT_DIR=("down" "right" "right") ;;
esac

# --- plan ---
echo "Source branch:  $SOURCE_BRANCH"
echo "Repo root:      $REPO_ROOT"
echo "Anchor surface: $ANCHOR_SURFACE"
echo "Layout:         $LAYOUT"
[[ $NEEDS_IGNORE -eq 1 ]] && echo "Setup:          will add .worktrees/ to .gitignore (one-time, auto-commit)"
if [[ $NO_DEV -eq 1 ]]; then
  echo "Auto dev:       OFF (--no-dev)"
elif [[ -f package.json ]] && grep -q '"dev"[[:space:]]*:' package.json; then
  echo "Auto dev:       ON ($(detect_pm .) install + nohup $(detect_pm .) dev → dev.log)"
else
  echo "Auto dev:       skipped (no package.json or no \"dev\" script)"
fi
echo "Plan:"
for ((i=0; i<N; i++)); do
  s="${SUFFIXES[i]}"
  port=$((3001 + i))
  prompt_preview="${PROMPTS[i]:-<no prompt>}"
  if [[ "$LAYOUT" == "tab" ]]; then
    placement="new tab"
  else
    placement="split ${SPLIT_DIR[i]} of ${SPLIT_ANCHOR[i]}"
  fi
  echo "  [$((i+1))] .worktrees/$s  ←  wt/$SOURCE_BRANCH/$s  (PORT=$port)  $placement  prompt=$prompt_preview"
done
echo

if [[ $DRY_RUN -eq 1 ]]; then
  echo "(dry-run, exiting)"
  exit 0
fi

# --- preflight: target port collisions ---
# If a target port is already bound, distinguish "our own stale dev server"
# (process tree rooted at one of .worktrees/*/dev.pid) from a foreign holder.
# Kill ours, abort on foreign — this prevents the silent EADDRINUSE failure
# where the new dev fails but a stale older dev keeps serving on the same port.

find_owning_pidfile() {
  # Echo the dev.pid path whose recorded PID is an ancestor (≤4 levels up)
  # of the listening PID. Returns 1 if no match.
  local listening_pid="$1"
  shopt -s nullglob
  for pidfile in .worktrees/*/dev.pid; do
    local our_pid
    our_pid=$(cat "$pidfile" 2>/dev/null)
    [[ -n "$our_pid" ]] || continue
    local p="$listening_pid"
    for _ in 0 1 2 3; do
      if [[ "$p" == "$our_pid" ]]; then
        echo "$pidfile"
        shopt -u nullglob
        return 0
      fi
      p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
      [[ -z "$p" || "$p" -le 1 ]] && break
    done
  done
  shopt -u nullglob
  return 1
}

declare -a FOREIGN_CONFLICTS=()
for ((i=0; i<N; i++)); do
  PORT=$((3001 + i))
  HOLDER_PID=$(lsof -nP -iTCP:$PORT -sTCP:LISTEN -t 2>/dev/null | head -1 || true)
  [[ -z "$HOLDER_PID" ]] && continue

  if OWNED_PIDFILE=$(find_owning_pidfile "$HOLDER_PID"); then
    OUR_PID=$(cat "$OWNED_PIDFILE")
    echo "[preflight] port $PORT held by our own stale dev server ($OWNED_PIDFILE, PID $OUR_PID) — killing"
    pkill -P "$OUR_PID" 2>/dev/null || true
    kill "$OUR_PID" 2>/dev/null || true
    rm -f "$OWNED_PIDFILE"
    sleep 0.3
  else
    HOLDER_CMD=$(ps -p "$HOLDER_PID" -o command= 2>/dev/null | head -c 80)
    FOREIGN_CONFLICTS+=("port $PORT held by PID $HOLDER_PID: $HOLDER_CMD")
  fi
done

if [[ ${#FOREIGN_CONFLICTS[@]} -gt 0 ]]; then
  echo "ERROR: target ports already bound by foreign processes:" >&2
  for c in "${FOREIGN_CONFLICTS[@]}"; do echo "  $c" >&2; done
  echo "Free those ports (e.g., 'kill <PID>') and re-run spawn.sh." >&2
  exit 1
fi

# --- auto-add .worktrees/ to .gitignore if needed (one-time per project) ---
if [[ $NEEDS_IGNORE -eq 1 ]]; then
  if [[ -n "$(git diff --cached --name-only)" ]]; then
    cat >&2 <<EOF
ERROR: .worktrees/ needs to be added to .gitignore, but you have other staged
changes. spawn.sh refuses to fold them into its commit.

Either commit/stash your staged changes first, or set up manually:

  echo '.worktrees/' >> .gitignore
  git add .gitignore && git commit -m "chore: ignore .worktrees/"
EOF
    exit 1
  fi
  echo "[setup] adding .worktrees/ to .gitignore"
  printf '\n.worktrees/\n' >> .gitignore
  git add .gitignore
  git commit -m "chore: ignore .worktrees/" >/dev/null
fi

# --- main loop ---
declare -a CREATED_SURFACES=()  # spawned surface refs, in iteration order

for ((i=0; i<N; i++)); do
  SUFFIX="${SUFFIXES[i]}"
  BRANCH="wt/$SOURCE_BRANCH/$SUFFIX"
  WTREE_REL=".worktrees/$SUFFIX"
  WTREE_ABS="$REPO_ROOT/$WTREE_REL"
  PORT=$((3001 + i))
  PROMPT="${PROMPTS[i]:-}"

  if [[ -e "$WTREE_REL" ]]; then
    echo "[$((i+1))/$N] SKIP: $WTREE_REL already exists. Pick a different suffix."
    continue
  fi

  echo "[$((i+1))/$N] $WTREE_REL  ←  $BRANCH  (port $PORT)"

  # 1. worktree
  git worktree add "$WTREE_REL" -b "$BRANCH" "$SOURCE_BRANCH"

  # 2. copy gitignored config
  copy_allowlist "$WTREE_REL"

  # 3. set PORT in .env.local
  ENV_FILE="$WTREE_REL/.env.local"
  if [[ -f "$ENV_FILE" ]] && grep -q '^PORT=' "$ENV_FILE"; then
    sed -i '' "s|^PORT=.*|PORT=$PORT|" "$ENV_FILE"
  else
    printf 'PORT=%s\n' "$PORT" >> "$ENV_FILE"
  fi

  # 4. create the cmux surface — new tab, or split pane
  if [[ "$LAYOUT" == "tab" ]]; then
    NEW_SURFACE=$(cmux --json tab-action --action new-terminal-right --tab "$ANCHOR_SURFACE" \
      | python3 -c 'import json,sys; print(json.load(sys.stdin)["created_surface_ref"])')
  else
    ANCHOR_KEY="${SPLIT_ANCHOR[$i]}"
    if [[ "$ANCHOR_KEY" == "main" ]]; then
      SPLIT_TARGET="$ANCHOR_SURFACE"
    else
      SPLIT_TARGET="${CREATED_SURFACES[$ANCHOR_KEY]}"
    fi
    DIR="${SPLIT_DIR[$i]}"
    NEW_SURFACE=$(cmux --json new-split "$DIR" --surface "$SPLIT_TARGET" \
      | python3 -c 'import json,sys; print(json.load(sys.stdin)["surface_ref"])')
  fi
  CREATED_SURFACES+=("$NEW_SURFACE")

  # let the new shell come up
  sleep 0.4

  # 5. cd + (optional) install + dev + claude
  CD_CMD="cd $(printf '%q' "$WTREE_ABS")"
  DEV_BLOCK=$(build_dev_block "$WTREE_REL" "$PORT")
  if [[ -n "$PROMPT" ]]; then
    CLAUDE_CMD="claude $(printf '%q' "$PROMPT")"
  else
    CLAUDE_CMD="claude"
  fi
  cmux send --surface "$NEW_SURFACE" "$CD_CMD$DEV_BLOCK && $CLAUDE_CMD"$'\n'

  # 6. rename tab/pane (best-effort; some layouts may not support rename via --surface)
  cmux rename-tab --surface "$NEW_SURFACE" "$BRANCH :$PORT" >/dev/null 2>&1 || true

  echo "        → surface $NEW_SURFACE"
done

echo
echo "Done. $N tab(s) spawned. Worktrees:"
git worktree list | grep ".worktrees/" || true
