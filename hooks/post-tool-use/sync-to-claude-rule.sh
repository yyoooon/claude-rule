#!/bin/sh
# Mirror ~/.claude/{CLAUDE.md,skills/,settings.json,hooks/,agents/,scripts/} to ~/Desktop/claude_rule
# and commit+push. Invoked by PostToolUse hook (Edit|Write).
#
# Filter: only runs when the edited path is one of the synced targets above.

set -e

F=$(jq -r '.tool_response.filePath // .tool_input.file_path // ""' 2>/dev/null || echo "")
[ -z "$F" ] && exit 0

case "$F" in
  "$HOME/.claude/CLAUDE.md"|"$HOME/.claude/skills/"*|"$HOME/.claude/settings.json"|"$HOME/.claude/hooks/"*|"$HOME/.claude/agents/"*|"$HOME/.claude/scripts/"*) ;;
  *) exit 0 ;;
esac

REPO="$HOME/Desktop/claude_rule"
[ -d "$REPO/.git" ] || exit 0

cp "$HOME/.claude/CLAUDE.md" "$REPO/CLAUDE.md" 2>/dev/null || true
cp "$HOME/.claude/settings.json" "$REPO/settings.json" 2>/dev/null || true
rsync -a --delete "$HOME/.claude/skills/" "$REPO/skills/" 2>/dev/null || true
rsync -a --delete "$HOME/.claude/hooks/" "$REPO/hooks/" 2>/dev/null || true
rsync -a --delete "$HOME/.claude/agents/" "$REPO/agents/" 2>/dev/null || true
rsync -a --delete "$HOME/.claude/scripts/" "$REPO/scripts/" 2>/dev/null || true

cd "$REPO" || exit 0
git add CLAUDE.md skills settings.json hooks agents scripts >/dev/null 2>&1 || true
git diff --cached --quiet && exit 0

REL="${F#$HOME/.claude/}"
git -c commit.gpgsign=false commit -m "sync: $REL" >/dev/null 2>&1 || exit 0
git push origin HEAD >/dev/null 2>&1 || true
