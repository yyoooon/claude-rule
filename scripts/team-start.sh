#!/bin/bash
# Usage: bash team-start.sh <main-surface> [num-dev-agents]
# Example: bash team-start.sh surface:1 3
set -e

MAIN_SURFACE="${1:?Usage: team-start.sh <main-surface> [num-dev-agents]}"
NUM_DEVS="${2:-2}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_FILE="$PROJECT_ROOT/.claude/team-state.json"
START_AGENT="$SCRIPT_DIR/start-agent.sh"

chmod +x "$START_AGENT"

# ── 기존 팀 정리 ─────────────────────────────────────────────
if [ -f "$STATE_FILE" ]; then
  echo "🧹 Cleaning up existing team..."

  # devs 배열 + assembly 읽기 (구 스키마 dev1/dev2도 호환)
  OLD_SURFACES=$(jq -r '
    (if .devs then .devs[] else ((.dev1 // empty), (.dev2 // empty)) end),
    (.assembly // empty)
  ' "$STATE_FILE" 2>/dev/null || true)

  for SURFACE in $OLD_SURFACES; do
    [ -z "$SURFACE" ] && continue
    echo "  /exit → $SURFACE"
    cmux send --surface "$SURFACE" "/exit" 2>/dev/null || true
    cmux send-key --surface "$SURFACE" "enter" 2>/dev/null || true
  done

  # claude가 /exit 처리할 시간 대기
  sleep 2

  for SURFACE in $OLD_SURFACES; do
    [ -z "$SURFACE" ] && continue
    echo "  closing $SURFACE"
    cmux close-surface --surface "$SURFACE" 2>/dev/null || true
  done

  rm -f "$STATE_FILE"
  echo "✅ Cleanup done."
  echo ""
fi
# ─────────────────────────────────────────────────────────────

echo "🚀 Starting team... (Dev Agents: $NUM_DEVS)"
echo "  Main Planner: $MAIN_SURFACE"
cmux rename-tab --surface "$MAIN_SURFACE" "Main Planner"

# 상단 우: Assembly Agent (Planner 오른쪽 split)
ASSEMBLY_SURFACE=$(cmux new-split right --surface "$MAIN_SURFACE" | awk '{print $2}')
echo "  Assembly    : $ASSEMBLY_SURFACE"
cmux rename-tab --surface "$ASSEMBLY_SURFACE" "Assembly Agent"
cmux send --surface "$ASSEMBLY_SURFACE" "bash $START_AGENT assembly-agent $MAIN_SURFACE"
cmux send-key --surface "$ASSEMBLY_SURFACE" "enter"

# Dev Agent 생성 (N개 동적)
DEV_SURFACES=()

for i in $(seq 1 "$NUM_DEVS"); do
  if [ "$i" -eq 1 ]; then
    # Dev 1: Main Planner 아래
    SPLIT_TARGET="$MAIN_SURFACE"
    DIRECTION="down"
  elif [ "$i" -eq 2 ]; then
    # Dev 2: Assembly 아래
    SPLIT_TARGET="$ASSEMBLY_SURFACE"
    DIRECTION="down"
  else
    # Dev 3+: 직전 Dev 오른쪽
    SPLIT_TARGET="${DEV_SURFACES[$((i-2))]}"
    DIRECTION="right"
  fi

  DEV_SURFACE=$(cmux new-split "$DIRECTION" --surface "$SPLIT_TARGET" | awk '{print $2}')
  echo "  Dev Agent $i : $DEV_SURFACE"
  cmux rename-tab --surface "$DEV_SURFACE" "Dev Agent $i"
  cmux send --surface "$DEV_SURFACE" "bash $START_AGENT dev-agent $MAIN_SURFACE"
  cmux send-key --surface "$DEV_SURFACE" "enter"
  DEV_SURFACES+=("$DEV_SURFACE")
done

# Save state (devs를 JSON 배열로 저장)
DEVS_JSON=$(printf '%s\n' "${DEV_SURFACES[@]}" | jq -R . | jq -s .)
jq -n \
  --arg main "$MAIN_SURFACE" \
  --arg assembly "$ASSEMBLY_SURFACE" \
  --argjson devs "$DEVS_JSON" \
  '{ main: $main, devs: $devs, assembly: $assembly }' \
  > "$STATE_FILE"

echo ""
echo "✅ Team ready! State saved to .claude/team-state.json"
