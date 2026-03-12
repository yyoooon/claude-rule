#!/bin/bash
# Usage: bash team-add-dev.sh
# Adds one Dev Agent to the current team.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_FILE="$PROJECT_ROOT/.claude/team-state.json"
START_AGENT="$SCRIPT_DIR/start-agent.sh"

if [ ! -f "$STATE_FILE" ]; then
  echo "❌ team-state.json not found. Run /team-start first."
  exit 1
fi

MAIN_SURFACE=$(jq -r '.main' "$STATE_FILE")
ASSEMBLY_SURFACE=$(jq -r '.assembly' "$STATE_FILE")

# devs 배열 읽기 (구 스키마 dev1/dev2 호환)
DEVS_JSON=$(jq -r '
  if .devs then .devs
  else [(.dev1 // empty), (.dev2 // empty)] | map(select(. != ""))
  end
' "$STATE_FILE")

NUM_DEVS=$(echo "$DEVS_JSON" | jq 'length')
NEXT_NUM=$((NUM_DEVS + 1))

# 레이아웃: 0개→Main 아래, 1개→Assembly 아래, 2개+→직전 Dev 오른쪽
if [ "$NUM_DEVS" -eq 0 ]; then
  SPLIT_TARGET="$MAIN_SURFACE"
  DIRECTION="down"
elif [ "$NUM_DEVS" -eq 1 ]; then
  SPLIT_TARGET="$ASSEMBLY_SURFACE"
  DIRECTION="down"
else
  SPLIT_TARGET=$(echo "$DEVS_JSON" | jq -r '.[-1]')
  DIRECTION="right"
fi

NEW_SURFACE=$(cmux new-split "$DIRECTION" --surface "$SPLIT_TARGET" | awk '{print $2}')
echo "  Dev Agent $NEXT_NUM : $NEW_SURFACE"
cmux rename-tab --surface "$NEW_SURFACE" "Dev Agent $NEXT_NUM"
cmux send --surface "$NEW_SURFACE" "bash $START_AGENT dev-agent $MAIN_SURFACE"
cmux send-key --surface "$NEW_SURFACE" "enter"

# state 업데이트
UPDATED_DEVS=$(echo "$DEVS_JSON" | jq --arg s "$NEW_SURFACE" '. + [$s]')
jq --argjson devs "$UPDATED_DEVS" '.devs = $devs | del(.dev1) | del(.dev2)' "$STATE_FILE" > "$STATE_FILE.tmp"
mv "$STATE_FILE.tmp" "$STATE_FILE"

echo ""
echo "✅ Dev Agent $NEXT_NUM added. Total devs: $NEXT_NUM"
