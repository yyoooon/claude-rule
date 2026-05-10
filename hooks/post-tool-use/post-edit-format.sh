#!/usr/bin/env bash
# PostToolUse hook: auto-format files Claude edits.
# Reads tool input JSON from stdin, runs ESLint --fix then Prettier --write.
# Silently skips when tools aren't installed locally. Always exits 0.

set -u

f=$(jq -r '.tool_input.file_path // empty')
[ -z "$f" ] && exit 0

case "$f" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) ;;
  *) exit 0 ;;
esac

cd "$(dirname "$f")" 2>/dev/null || exit 0

# --no-install: don't fetch from registry; if not in local node_modules, fail fast.
# Stderr/stdout silenced so lint warnings don't leak into Claude's transcript.
npx --no-install eslint --fix "$f" >/dev/null 2>&1
npx --no-install prettier --write "$f" >/dev/null 2>&1

exit 0
