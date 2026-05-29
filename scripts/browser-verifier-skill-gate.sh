#!/usr/bin/env bash
# PreToolUse hook on mcp__browser-verifier__* tools.
# browser-verifier 스킬이 이 세션에서 invoke되지 않았으면 차단.

set -euo pipefail

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

# session_id 못 읽으면 통과 (안전 디폴트)
[[ -z "$SESSION_ID" ]] && exit 0

SENTINEL="/tmp/claude-skill-invoked-browser-verifier-$SESSION_ID"

# 스킬 invoke 기록 있으면 통과
if [[ -f "$SENTINEL" ]]; then
  exit 0
fi

# 차단 + 명시 안내
jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: "browser-verifier MCP 도구는 Skill(browser-verifier) invoke 후에만 사용 가능합니다. 먼저 Skill 툴로 스킬을 invoke한 뒤 재시도하세요."
  }
}'
exit 0
