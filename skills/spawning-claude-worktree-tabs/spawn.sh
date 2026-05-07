#!/usr/bin/env bash
# Spawn N parallel Claude instances in cmux tabs, each in its own git worktree.
# See SKILL.md for full documentation.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: spawn.sh -n <N> [-s suffix1,suffix2,...] [-p prompts-file] [--dry-run]

  -n N            number of tabs to spawn (required)
  -s suffixes     comma-separated suffix names; missing positions auto-fill (a, b, c, …)
  -p prompts      file with one initial prompt per line (used in order)
  --dry-run       print the plan without creating anything

Branch:    wt/<current-branch>/<suffix>
Worktree:  .worktrees/<suffix>
Port:      3001, 3002, 3003, … (written to each worktree's .env.local)
EOF
}

N=""
SUFFIXES_ARG=""
PROMPTS_FILE=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case $1 in
    -n) N="${2:-}"; shift 2 ;;
    -s) SUFFIXES_ARG="${2:-}"; shift 2 ;;
    -p) PROMPTS_FILE="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

[[ "$N" =~ ^[0-9]+$ && "$N" -gt 0 ]] \
  || { echo "ERROR: -n <N> required (positive integer)" >&2; exit 1; }

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

# --- plan ---
echo "Source branch:  $SOURCE_BRANCH"
echo "Repo root:      $REPO_ROOT"
echo "Anchor surface: $ANCHOR_SURFACE"
[[ $NEEDS_IGNORE -eq 1 ]] && echo "Setup:          will add .worktrees/ to .gitignore (one-time, auto-commit)"
echo "Plan:"
for ((i=0; i<N; i++)); do
  s="${SUFFIXES[i]}"
  port=$((3001 + i))
  prompt_preview="${PROMPTS[i]:-<no prompt>}"
  echo "  [$((i+1))] .worktrees/$s  ←  wt/$SOURCE_BRANCH/$s  (PORT=$port)  prompt=$prompt_preview"
done
echo

if [[ $DRY_RUN -eq 1 ]]; then
  echo "(dry-run, exiting)"
  exit 0
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

# --- main loop ---
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

  # 4. spawn cmux tab anchored to current
  NEW_SURFACE=$(cmux --json tab-action --action new-terminal-right --tab "$ANCHOR_SURFACE" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["created_surface_ref"])')

  # let the new shell come up
  sleep 0.4

  # 5. cd + claude (with optional prompt)
  CD_CMD="cd $(printf '%q' "$WTREE_ABS")"
  if [[ -n "$PROMPT" ]]; then
    CLAUDE_CMD="claude $(printf '%q' "$PROMPT")"
  else
    CLAUDE_CMD="claude"
  fi
  cmux send --surface "$NEW_SURFACE" "$CD_CMD && $CLAUDE_CMD"$'\n'

  # 6. rename tab
  cmux rename-tab --surface "$NEW_SURFACE" "$BRANCH :$PORT" >/dev/null

  echo "        → surface $NEW_SURFACE"
done

echo
echo "Done. $N tab(s) spawned. Worktrees:"
git worktree list | grep ".worktrees/" || true
