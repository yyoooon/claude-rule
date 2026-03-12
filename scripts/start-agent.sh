#!/bin/bash
# Usage: bash start-agent.sh <agent-name> <main-surface>
# Example: bash start-agent.sh dev-agent surface:1
set -e

AGENT_NAME="${1:?Usage: start-agent.sh <agent-name> <main-surface>}"
MAIN_SURFACE="${2:?Usage: start-agent.sh <agent-name> <main-surface>}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENTS_DIR="$SCRIPT_DIR/../agents"
AGENT_FILE="$AGENTS_DIR/$AGENT_NAME.md"

if [ ! -f "$AGENT_FILE" ]; then
  echo "❌ Agent file not found: $AGENT_FILE"
  exit 1
fi

# Strip YAML frontmatter (between first and second ---) and replace surface ID
PROMPT=$(awk '/^---/{count++; if(count==2){found=1; next}} found{print}' "$AGENT_FILE" \
  | sed "s/surface:n/$MAIN_SURFACE/g")

exec claude --dangerously-skip-permissions --system-prompt "$PROMPT"
