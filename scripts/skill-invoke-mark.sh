#!/usr/bin/env bash
# PostToolUse hook on Skill tool.
# 특정 스킬이 invoke되면 세션별 sentinel 파일을 생성.
# 현재 추적 대상: browser-verifier (추가 스킬은 아래 case에 패턴 추가).

set -euo pipefail

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
SKILL_NAME=$(echo "$INPUT" | jq -r '.tool_input.skill // empty')

[[ -z "$SESSION_ID" || -z "$SKILL_NAME" ]] && exit 0

case "$SKILL_NAME" in
  browser-verifier)
    touch "/tmp/claude-skill-invoked-browser-verifier-$SESSION_ID"
    ;;
esac

exit 0
