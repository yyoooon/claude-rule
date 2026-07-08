#!/usr/bin/env bash
# PostToolUse hook: auto-format files Claude edits.
# Runs Prettier --write (only when the project has a resolvable Prettier config)
# then ESLint --fix last, so each project's own config wins. Projects that
# delegate formatting to ESLint (e.g. @huray/eslint-config-*) have no standalone
# Prettier config, so Prettier is skipped and ESLint governs. On real failures
# (tool installed but exited non-zero), surfaces output via {"systemMessage": ...}
# so Claude sees it in the next turn. Silently skips when tools aren't installed
# locally. Always exits 0.

set -u

f=$(jq -r '.tool_input.file_path // empty')
[ -z "$f" ] && exit 0

case "$f" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) ;;
  *) exit 0 ;;
esac

cd "$(dirname "$f")" 2>/dev/null || exit 0

# Heuristic: distinguish "tool not installed locally" from "real failure".
# npx --no-install prints these when the binary isn't found in node_modules.
is_missing_tool() {
  echo "$1" | grep -qE "could not determine executable|npx canceled|command not found"
}

tmp=$(mktemp)

# Prettier --write — only when the project actually configures Prettier
# (resolvable .prettierrc / package.json "prettier" / etc. for this file).
# `--find-config-path` exits non-zero when no config is found, in which case we
# skip Prettier and let ESLint's own formatting rules govern (avoids a default-
# config Prettier fighting the project's ESLint style, e.g. quote style).
if npx --no-install prettier --find-config-path "$f" >/dev/null 2>&1; then
  prettier_out=$(npx --no-install prettier --write "$f" 2>&1)
  prettier_rc=$?
  if [ "$prettier_rc" -ne 0 ] && ! is_missing_tool "$prettier_out"; then
    {
      echo "[post-edit-format] Prettier failed for $f (exit $prettier_rc):"
      echo "$prettier_out"
      echo ""
    } >> "$tmp"
  fi
fi

# ESLint --fix — runs last so the project's ESLint config (including any
# integrated formatting rules) has the final say.
eslint_out=$(npx --no-install eslint --fix "$f" 2>&1)
eslint_rc=$?
if [ "$eslint_rc" -ne 0 ] && ! is_missing_tool "$eslint_out"; then
  {
    echo "[post-edit-format] ESLint reported issues in $f (exit $eslint_rc):"
    echo "$eslint_out"
  } >> "$tmp"
fi

if [ -s "$tmp" ]; then
  jq -R -s '{systemMessage: .}' < "$tmp"
fi

rm -f "$tmp"
exit 0
